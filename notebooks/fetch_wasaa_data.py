import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile
import requests

API = 'https://api-wasaa-lifestyle.webmasterskenya.com/api/v1'
SANDBOX_EMAIL = 'user@wasaalifestyle.com'
SANDBOX_PASSWORD = 'User123!'
DATASETS = ('spending_records', 'budget_categories')
EXPECTED_ROWS = {'spending_records': 293448, 'budget_categories': 80013}


class DownloadError(Exception):
    pass


def check_status(response, stage):
    code = response.status_code
    if code == 200:
        return
    if code in (401, 403):
        detail = 'Check the authorized sandbox credentials and dataset permissions.'
    elif code == 429:
        detail = 'Too many requests. Wait a few minutes before trying again.'
    elif code >= 500:
        detail = 'The server is unavailable. Try again later.'
    elif 300 <= code < 400:
        detail = 'Unexpected redirect; the script will not forward credentials.'
    else:
        detail = 'Check that the sandbox API and dataset are available.'
    raise DownloadError(f'{stage}: HTTP {code}. {detail}')


def csv_summary(path, name):
    try:
        with path.open(encoding='utf-8-sig', newline='') as stream:
            reader = csv.reader(stream, strict=True)
            columns = next(reader, [])
            expected = {'user_profile_id', 'budget_category_id'}
            expected.add('spending_record_id' if name == 'spending_records' else 'allocated_kes')
            if not expected <= set(columns) or len(columns) != len(set(columns)):
                raise DownloadError(f'{name}: response is not the expected CSV table.')
            rows = 0
            for row in reader:
                if not row:
                    continue
                if len(row) != len(columns):
                    raise DownloadError(f'{name}: malformed CSV row; download not accepted.')
                rows += 1
            if rows == 0:
                raise DownloadError(f'{name}: CSV contains no records.')
            return rows, columns
    except (UnicodeError, csv.Error):
        raise DownloadError(f'{name}: unreadable CSV; download not accepted.') from None


def fetch(email, password, output_parent='.'):
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry

    if not email.strip() or not password:
        raise DownloadError('Both email and password are required.')
    parent = Path(output_parent).expanduser().resolve()
    if not parent.is_dir():
        raise DownloadError('The output parent must be an existing directory.')
    client = requests.Session()
    output = None
    try:
        retries = Retry(total=3, backoff_factor=1, allowed_methods={'GET'},
                        status_forcelist=(502, 503, 504), raise_on_status=False)
        client.mount('https://', HTTPAdapter(max_retries=retries))
        print('Signing in to the Wasaa sandbox...')
        with client.post(API+'/auth/login',
                         json={'email': email.strip(), 'password': password},
                         timeout=(30, 60), allow_redirects=False) as response:
            check_status(response, 'Login')
            try:
                payload = response.json()
                token = payload['data']['accessToken']
            except (ValueError, KeyError, TypeError):
                raise DownloadError('Login response did not contain an access token.') from None
            if not isinstance(token, str) or not token or '\r' in token or '\n' in token:
                raise DownloadError('Login returned an invalid access token.')
        client.headers['Authorization'] = 'Bearer ' + token
        output = Path(tempfile.mkdtemp(
            prefix='wasaa_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S') + '_',
            dir=parent
        ))
        report = {
            'synthetic': True,
            'retrieved_utc': datetime.now(timezone.utc).isoformat(),
            'api': API,
            'status': 'incomplete',
            'datasets': {}
        }
        for name in DATASETS:
            partial = output / f'{name}.csv.part'
            print(f'Downloading {name} (this can take several minutes)...')
            try:
                digest = hashlib.sha256()
                with client.get(
                    f'{API}/sandbox/dataset/{name}.csv',
                    timeout=(30, 600),
                    stream=True,
                    allow_redirects=False
                ) as response:
                    check_status(response, name)
                    content_type = response.headers.get('Content-Type', '').lower()
                    if 'text/html' in content_type or 'application/json' in content_type:
                        raise DownloadError(f'{name}: server returned a page instead of CSV.')
                    with partial.open('xb') as stream:
                        for chunk in response.iter_content(chunk_size=1024 * 1024):
                            if chunk:
                                stream.write(chunk)
                                digest.update(chunk)
                rows, columns = csv_summary(partial, name)
                final = output / f'{name}.csv'
                partial.rename(final)
                report['datasets'][name] = {
                    'rows': rows,
                    'columns': columns,
                    'sha256': digest.hexdigest(),
                    'bytes': final.stat().st_size
                }
                print(f'Saved {name}.csv — {rows:,} rows.')
                if rows != EXPECTED_ROWS[name]:
                    print(f'Note: expected {EXPECTED_ROWS[name]:,} rows.')
            finally:
                if partial.exists():
                    partial.unlink()
        report['status'] = 'complete'
        with (output / 'snapshot.json').open('x', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2)
        print(f'\nComplete. Files saved to: {output}')
        print('These are synthetic datasets. Label them as synthetic in your report.')
        return output
    except requests.exceptions.Timeout:
        raise DownloadError('The API timed out. Try again later.') from None
    except requests.exceptions.RequestException:
        raise DownloadError('Network request failed. Check internet access.') from None
    finally:
        client.headers.pop('Authorization', None)
        client.close()
        if output is not None and not (output / 'snapshot.json').exists():
            print(f'Incomplete download. Any completed CSVs were preserved.')


# ── Run the download ──────────────────────────────────────────
output_folder = fetch(
    email=SANDBOX_EMAIL,
    password=SANDBOX_PASSWORD,
    output_parent='/content'
)

print(f'\nFiles are in: {output_folder}')