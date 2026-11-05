/// Parses M-Pesa, Airtel Money and bank (I&M) transaction SMS messages.
///
/// Pure Dart: no Flutter or plugin dependencies, so it can be unit tested
/// with `flutter test`.
///
/// Formats verified against real messages: M-Pesa "paid to", Airtel Money
/// "sent to", I&M Bank card purchase. M-Pesa "sent to", "received" and airtime
/// formats are written from the standard Safaricom wording and have NOT yet
/// been checked against real messages. Anything unrecognised returns null so
/// the user can add it manually.

class ParsedSms {
  final String reference; // M-Pesa / Airtel code, '' for bank SMS
  final double amount; // KSh
  final String date; // yyyy-MM-dd
  final String source; // MPESA | CARD | WALLET (matches backend values)
  final String counterparty; // merchant or person
  final String category; // a name from the database categories table
  final bool isExpense; // false for income and transfers to yourself
  final bool isFallback; // true when only the generic fallback could read it

  const ParsedSms({
    required this.reference,
    required this.amount,
    required this.date,
    required this.source,
    required this.counterparty,
    required this.category,
    required this.isExpense,
    this.isFallback = false,
  });

  @override
  String toString() =>
      'ParsedSms($reference, $amount, $date, $source, "$counterparty", $category, expense=$isExpense)';
}

class SmsParser {
  // ── Patterns (kept as plain strings so they are easy to read and test) ──
  static const _pPaid =
      r'^\s*([A-Z0-9]{10})\s+Confirmed\.?\s*Ksh\s?([\d,]+(?:\.\d+)?)\s+paid to\s+(.+?)\.?\s+on\s+(\d{1,2}/\d{1,2}/\d{2,4})';
  static const _pSent =
      r'^\s*([A-Z0-9]{10})\s+Confirmed\.?\s*Ksh\s?([\d,]+(?:\.\d+)?)\s+sent to\s+(.+?)\.?\s+on\s+(\d{1,2}/\d{1,2}/\d{2,4})';
  static const _pReceived =
      r'^\s*([A-Z0-9]{10})\s+Confirmed\.?\s*You have received\s+Ksh\s?([\d,]+(?:\.\d+)?)\s+from\s+(.+?)\.?\s+on\s+(\d{1,2}/\d{1,2}/\d{2,4})';
  static const _pAirtime =
      r'^\s*([A-Z0-9]{10})\s+Confirmed\.?\s*You bought\s+Ksh\s?([\d,]+(?:\.\d+)?)\s+of airtime\s+on\s+(\d{1,2}/\d{1,2}/\d{2,4})';
  static const _pAirtel =
      r'^\s*([A-Z0-9]+)\.\s*Ksh\s?([\d,]+(?:\.\d+)?)\s+sent to\s+(.+?)\.?\s+on\s+(\d{1,2}/\d{1,2}/\d{2,4})';
  static const _pBank =
      r'purchase of\s*KES\s*([\d,]+(?:\.\d+)?)\s+on\s+(\d{4}-\d{2}-\d{2})\s+\d{2}:\d{2}:\d{2}\s+at\s+(.+?)\s+using';

  static final _rPaid = RegExp(_pPaid, caseSensitive: false);
  static final _rSent = RegExp(_pSent, caseSensitive: false);
  static final _rReceived = RegExp(_pReceived, caseSensitive: false);
  static final _rAirtime = RegExp(_pAirtime, caseSensitive: false);
  static final _rAirtel = RegExp(_pAirtel, caseSensitive: false);
  static final _rBank = RegExp(_pBank, caseSensitive: false);

  // M-Pesa mini-statement: "[20260728; ;Customer Send Money; ...;Ksh30.00]Completed [...]"
  // It summarises the last 5 transactions, which already arrived as their own
  // SMS, so it is skipped to avoid double counting.
  static final _rMiniStatement =
      RegExp(r'\[\d{8};[^\]]*;\s*Ksh[\d,.]+\]\s*Completed', caseSensitive: false);

  // Fallback for bank alerts we have not seen before
  static final _rAnyAmount =
      RegExp(r'(?:kes|ksh)\s?([\d,]+(?:\.\d+)?)', caseSensitive: false);
  static final _rDebitWord = RegExp(
      r'debited|purchase|purchased|paid|withdrawn|spent|payment',
      caseSensitive: false);
  static final _rCreditWord =
      RegExp(r'credited|received|deposit', caseSensitive: false);
  static final _rIsoDate = RegExp(r'(\d{4}-\d{2}-\d{2})');
  static final _rDmyDate = RegExp(r'(\d{1,2}/\d{1,2}/\d{2,4})');
  static final _rAtMerchant = RegExp(
      r'\b(?:at|to)\s+(.+?)(?:\s+(?:on|using|ref|bal|for|via)\b|\.\s|\.$|$)',
      caseSensitive: false);
  // A "merchant" that is really a time, date or number (e.g. "2:06 PM")
  static final _rNotAName =
      RegExp(r'^(?:\d{1,2}:\d{2}|\d{1,2}/\d{1,2}|[\d\s,.:/-]+$)', caseSensitive: false);

  /// Returns null if [body] is not a recognised transaction message.
  ///
  /// [ownName] (e.g. "LINCY MUEMA"): payments to this name are treated as
  /// transfers between your own accounts, not spending.
  static ParsedSms? parse(String body,
      {String? ownName, DateTime? today, String? sender}) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;

    // Statements and summaries are not individual transactions
    if (_rMiniStatement.hasMatch(text)) return null;

    Match? m;

    m = _rPaid.firstMatch(text);
    if (m != null) {
      return _person(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!,
          'MPESA', ownName);
    }

    m = _rSent.firstMatch(text);
    if (m != null) {
      return _person(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!,
          'MPESA', ownName);
    }

    m = _rReceived.firstMatch(text);
    if (m != null) {
      return ParsedSms(
        reference: m.group(1)!,
        amount: _amount(m.group(2)!),
        date: _isoFromDmy(m.group(4)!),
        source: 'MPESA',
        counterparty: _cleanName(m.group(3)!),
        category: 'Other',
        isExpense: false, // money in
      );
    }

    m = _rAirtime.firstMatch(text);
    if (m != null) {
      return ParsedSms(
        reference: m.group(1)!,
        amount: _amount(m.group(2)!),
        date: _isoFromDmy(m.group(3)!),
        source: 'MPESA',
        counterparty: 'Airtime',
        category: 'Bills & Utilities',
        isExpense: true,
      );
    }

    m = _rAirtel.firstMatch(text);
    if (m != null) {
      return _person(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!,
          'WALLET', ownName);
    }

    m = _rBank.firstMatch(text);
    if (m != null) {
      final merchant = m.group(3)!.trim();
      return ParsedSms(
        reference: '',
        amount: _amount(m.group(1)!),
        date: m.group(2)!,
        source: 'CARD',
        counterparty: merchant,
        category: categorise(merchant),
        isExpense: true,
      );
    }

    return _generic(text, today ?? DateTime.now(), _sourceFromSender(sender));
  }

  /// MPESA / WALLET / CARD based on who sent the message (CARD if unknown).
  static String _sourceFromSender(String? sender) {
    final s = (sender ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.contains('MPESA')) return 'MPESA';
    if (s.contains('AIRTEL')) return 'WALLET';
    return 'CARD';
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static ParsedSms _person(String ref, String amt, String rawName, String dmy,
      String source, String? ownName) {
    final name = _cleanName(rawName);
    final isOwn = ownName != null &&
        ownName.trim().isNotEmpty &&
        name.toUpperCase().contains(ownName.trim().toUpperCase());
    return ParsedSms(
      reference: ref,
      amount: _amount(amt),
      date: _isoFromDmy(dmy),
      source: source,
      counterparty: name,
      category: categorise(name),
      isExpense: !isOwn,
    );
  }

  static ParsedSms? _generic(String text, DateTime today, String source) {
    final amt = _rAnyAmount.firstMatch(text);
    if (amt == null) return null;
    if (!_rDebitWord.hasMatch(text) || _rCreditWord.hasMatch(text)) return null;

    String date;
    final iso = _rIsoDate.firstMatch(text);
    final dmy = _rDmyDate.firstMatch(text);
    if (iso != null) {
      date = iso.group(1)!;
    } else if (dmy != null) {
      date = _isoFromDmy(dmy.group(1)!);
    } else {
      date = _iso(today);
    }

    // Take the first "at X" / "to X" that is a real name, not a time or number
    String? merchant;
    for (final m in _rAtMerchant.allMatches(text)) {
      final cand = _cleanName(m.group(1)!.trim());
      if (cand.isNotEmpty && !_rNotAName.hasMatch(cand)) {
        merchant = cand;
        break;
      }
    }
    merchant ??= source == 'MPESA'
        ? 'M-Pesa payment'
        : source == 'WALLET'
            ? 'Wallet payment'
            : 'Bank transaction';

    return ParsedSms(
      reference: '',
      amount: _amount(amt.group(1)!),
      date: date,
      source: source,
      counterparty: merchant,
      category: categorise(merchant),
      isExpense: true,
      isFallback: true,
    );
  }

  static double _amount(String s) => double.parse(s.replaceAll(',', ''));

  /// Removes a trailing phone number / masked number and trailing full stop.
  static String _cleanName(String s) => s
      .replaceAll(RegExp(r'\s+[\dxX*]{6,}$'), '')
      .replaceAll(RegExp(r'(?<=[A-Za-z])\d{5,}$'), '')
      .replaceAll(RegExp(r'\.+$'), '')
      .trim();

  static String _isoFromDmy(String s) {
    final p = s.split('/');
    final d = int.parse(p[0]);
    final mo = int.parse(p[1]);
    var y = int.parse(p[2]);
    if (y < 100) y += 2000;
    return '${y.toString().padLeft(4, '0')}-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Category guess from the merchant name ─────────────────────────────────
  // Keywords match at the START of a word, so "rent" matches "RENTAL" but not
  // "PARENTS", and "food" matches "FOODS". The user can correct any category,
  // and the backend remembers that choice for the merchant.
  static const Map<String, List<String>> _rules = {
    'Food & Dining': [
      'food', 'kuku', 'restaurant', 'cafe', 'caffe', 'coffee', 'kfc', 'pizza',
      'java', 'artcaffe', 'bakery', 'bakers', 'kitchen', 'chicken', 'burger',
      'eatery', 'hotel', 'galitos', 'simbisa', 'chicken inn', 'mboga',
      'grocer', 'greengrocer', 'vegetable', 'fruits', 'butchery', 'butcher',
      'dairy', 'milk', 'nyama', 'chips', 'fries', 'snacks', 'canteen', 'cafeteria',
    ],
    'Entertainment': [
      'entertainment', 'cinema', 'century', 'imax', 'netflix', 'showmax',
      'spotify', 'youtube', 'betika', 'sportpesa', 'odibets', 'mozzart',
      'club', 'lounge', 'games', 'gaming', 'playstation', 'bowling', 'pins',
    ],
    'Transport': [
      'uber', 'bolt', 'little cab', 'faras', 'matatu', 'sacco', 'fuel',
      'petrol', 'shell', 'rubis', 'total', 'totalenergies', 'hass',
      'parking', 'easy coach', 'modern coast', 'transport',
    ],
    'Bills & Utilities': [
      'kplc', 'kenya power', 'water', 'safaricom', 'zuku', 'faiba', 'jtl',
      'dstv', 'gotv', 'startimes', 'airtime', 'rent', 'wifi', 'internet',
      'home fibre', 'electricity', 'nhif', 'insurance',
    ],
    'Education': [
      'school', 'university', 'college', 'academy', 'tuition', 'fees',
      'strathmore', 'usiu', 'kca', 'text book', 'textbook', 'bookshop',
      'bookpoint', 'books', 'stationery', 'stationers', 'printing', 'cyber',
    ],
    'Travel': [
      'airline', 'airways', 'kenya airways', 'jambojet', 'safarilink',
      'flight', 'sgr', 'madaraka express', 'booking', 'airbnb', 'safari',
      'resort', 'lodge',
    ],
    'Shopping': [
      'carrefour', 'quick mart', 'quickmart', 'naivas', 'chandarana',
      'cleanshelf', 'magunas', 'supermarket', 'shop', 'store',
      'stores', 'mall', 'boutique', 'jumia', 'kilimall', 'mr price',
      'lc waikiki', 'decathlon', 'hotpoint', 'enterprises', 'traders',
      'wholesalers', 'wholesale', 'retail', 'electronics', 'hardware',
      'beauty', 'salon', 'cosmetics', 'pharmacy', 'chemist',
    ],
  };

  static final Map<String, List<RegExp>> _compiled = _rules.map(
    (cat, words) => MapEntry(
      cat,
      words
          .map((w) => RegExp(r'\b' + RegExp.escape(w), caseSensitive: false))
          .toList(),
    ),
  );

  static String categorise(String merchant) {
    for (final entry in _compiled.entries) {
      for (final re in entry.value) {
        if (re.hasMatch(merchant)) return entry.key;
      }
    }
    return 'Other';
  }
}