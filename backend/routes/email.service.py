"""
Sending emails (sign-in and password-reset codes).

Render's free plan blocks normal email (SMTP), so emails are sent through
Brevo's web API over HTTPS instead.

Settings (in .env locally, or in Render's Environment tab):
  BREVO_API_KEY  - the API key from Brevo (Settings > SMTP & API > API keys)
  EMAIL_FROM     - a sender address verified in Brevo (Senders, domains & IPs)
  EMAIL_FROM_NAME - optional, defaults to "Pesight"

If BREVO_API_KEY is not set (e.g. when developing on a laptop), the email is
not sent; its text is printed in the backend terminal instead so the code can
still be tested.
"""

import json
import logging
import os
import urllib.error
import urllib.request

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("pesight.email")

BREVO_URL = "https://api.brevo.com/v3/smtp/email"


def send_email(to_email: str, to_name: str, subject: str, text_body: str, html_body: str) -> bool:
    """Send one email. Returns True if it was accepted for delivery."""
    api_key = os.getenv("BREVO_API_KEY")
    sender = os.getenv("EMAIL_FROM")
    sender_name = os.getenv("EMAIL_FROM_NAME", "Pesight")

    if not api_key or not sender:
        # Development: no email service configured, so show the email in the terminal
        print(f"\n[EMAIL NOT SENT - BREVO_API_KEY/EMAIL_FROM not set]\nTo: {to_email}\n"
              f"Subject: {subject}\n{text_body}\n", flush=True)
        return True

    payload = {
        "sender": {"name": sender_name, "email": sender},
        "to": [{"email": to_email, "name": to_name or to_email}],
        "subject": subject,
        "textContent": text_body,
        "htmlContent": html_body,
    }
    request = urllib.request.Request(
        BREVO_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError as e:
        logger.error("Brevo rejected the email (%s): %s", e.code, e.read()[:300])
    except Exception as e:  # network problem, timeout
        logger.error("Could not reach Brevo: %s", e)
    return False


def send_code_email(to_email: str, to_name: str, code: str, purpose: str, minutes: int) -> bool:
    """Email a 6-digit code for signing in or resetting the password."""
    first_name = (to_name or "").split(" ")[0] or "there"
    if purpose == "password_reset":
        subject = "Your Pesight password reset code"
        intro = "Use this code to reset your Pesight password:"
        outro = "If you did not ask to reset your password, you can ignore this email; your password has not changed."
    else:
        subject = "Your Pesight sign-in code"
        intro = "Use this code to finish signing in to Pesight:"
        outro = "If you did not try to sign in, someone may know your password. Please change it in the app."

    text_body = (
        f"Hi {first_name},\n\n{intro}\n\n    {code}\n\n"
        f"The code expires in {minutes} minutes.\n\n{outro}\n\nPesight"
    )
    html_body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;color:#1A1A2E">
      <h2 style="color:#5B2EFF;margin-bottom:4px">Pesight</h2>
      <p>Hi {first_name},</p>
      <p>{intro}</p>
      <p style="font-size:32px;font-weight:bold;letter-spacing:8px;background:#F5F5FA;
                padding:16px;text-align:center;border-radius:12px">{code}</p>
      <p>The code expires in {minutes} minutes.</p>
      <p style="color:#777;font-size:13px">{outro}</p>
    </div>
    """
    return send_email(to_email, to_name, subject, text_body, html_body)