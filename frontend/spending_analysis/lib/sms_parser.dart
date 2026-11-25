/// Parses M-Pesa, Airtel Money and bank (I&M, Co-operative Bank, Absa,
/// Standard Chartered) transaction SMS messages.
///
/// Pure Dart: no Flutter or plugin dependencies, so it can be unit tested
/// with `flutter test`.
///
/// Every format below has been checked against real messages:
///   M-Pesa: buy goods ("paid to"), paybill and send money ("sent to"),
///           money received, airtime
///   Airtel Money: "sent to"
///   I&M Bank: card purchase
///   Co-operative Bank: M-Pesa transfer from the account
///   Absa: debit and credit alerts
///   Standard Chartered: card payment, transfer to M-Pesa, account transfer
/// Anything unrecognised returns null so the user can add it manually.

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

  // Co-operative Bank: money sent from the bank account to an M-Pesa number
  // "Ref:AC53...: Dear JANE, MPESA transfer of KES 1200 to JOHN DOE-2547 at
  //  05-11-2026 04:24 PM was successful.MPESA Ref:UK5P915VW3."
  static final _rCoopMpesa = RegExp(
      r'MPESA transfer of KES\s*([\d,]+(?:\.\d+)?)\s+to\s+(.+?)\s+at\s+(\d{1,2}-\d{1,2}-\d{4})\s+\d{1,2}:\d{2}\s*[AP]M\s+was successful\.?\s*(?:MPESA Ref:\s*([A-Z0-9]+))?',
      caseSensitive: false);

  // Absa: card or account debit. The message has no date (the date the SMS
  // arrived is used) and the merchant is a fixed-width card field:
  // 25 characters of name, 13 of town, then the country code.
  static final _rAbsaDebit = RegExp(
      r'a Debit has been made for KES\s*([\d,]+(?:\.\d+)?)\s+in Account ending\s+\S+\s+AT\s+(.+?)\.?\s*please call',
      caseSensitive: false);
  static final _rAbsaCredit =
      RegExp(r'a Credit has been made for KES\s*([\d,]+(?:\.\d+)?)', caseSensitive: false);

  // Standard Chartered
  // "a transaction of KES 289.00 was made on card ending 1234 at
  //  GOOGLE YouTubePremium on 2026-10-28."
  static final _rScCard = RegExp(
      r'transaction of KES\s*([\d,]+(?:\.\d+)?)\s+was made on card ending\s+\S+\s+at\s+(.+?)\s+on\s+(\d{4}-\d{2}-\d{2})',
      caseSensitive: false);
  // "transaction of KES 1509.00 to MPESA has been processed successfully,
  //  ref. UK00000000 to JOHN DOE For any queries ..."
  static final _rScToMpesa = RegExp(
      r'transaction of KES\s*([\d,]+(?:\.\d+)?)\s+to MPESA has been processed successfully,?\s*ref\.?\s*([A-Z0-9]+)\s+to\s+(.+?)\s*(?:For any|$)',
      caseSensitive: false);
  // "KES 9000.00 was transferred from Acc. ending with 1111 to Acc. ending with 2222."
  static final _rScAccount = RegExp(
      r'KES\s*([\d,]+(?:\.\d+)?)\s+was transferred from Acc\.? ending with\s+\S+\s+to Acc\.? ending with\s+(\d+)',
      caseSensitive: false);
  // "JOHN DOE has transferred KES 1509.00 to your MPESA Account, ref UK00000000."
  // The same transfer as the message above, so it is skipped.
  static final _rScMpesaNotice = RegExp(
      r'has transferred KES\s*[\d,.]+\s+to your MPESA Account', caseSensitive: false);

  // M-Pesa mini-statement: "[20260728; ;Customer Send Money; ...;Ksh30.00]Completed [...]"
  // It summarises the last 5 transactions, which already arrived as their own
  // SMS, so it is skipped to avoid double counting.
  static final _rMiniStatement =
      RegExp(r'\[\d{8};[^\]]*;\s*Ksh[\d,.]+\]\s*Completed', caseSensitive: false);

  // M-Shwari and Ziidi messages are savings and investment moves, not spending.
  static final _rSavings = RegExp(r'm[\s-]?shwari|ziidi', caseSensitive: false);

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

    // Moving money into or out of savings and investments (M-Shwari, Ziidi)
    // is not spending or income, so these messages are not imported
    if (_rSavings.hasMatch(text)) return null;

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

    m = _rCoopMpesa.firstMatch(text);
    if (m != null) {
      final ref = m.group(4) ?? '';
      final r = _person(ref, m.group(1)!, m.group(2)!,
          m.group(3)!.replaceAll('-', '/'), 'CARD', ownName);
      return r;
    }

    // Absa uses runs of spaces inside the merchant field, so it is read from
    // the original message, not the space-collapsed copy.
    final absaText = body.replaceAll(RegExp(r'[\r\n]+'), ' ');
    m = _rAbsaDebit.firstMatch(absaText);
    if (m != null) {
      final merchant = _absaMerchant(m.group(2)!);
      return ParsedSms(
        reference: '',
        amount: _amount(m.group(1)!),
        date: _iso(today ?? DateTime.now()),
        source: 'CARD',
        counterparty: merchant,
        category: categorise(merchant),
        isExpense: true,
      );
    }
    m = _rAbsaCredit.firstMatch(text);
    if (m != null) {
      return ParsedSms(
        reference: '',
        amount: _amount(m.group(1)!),
        date: _iso(today ?? DateTime.now()),
        source: 'CARD',
        counterparty: 'Absa deposit',
        category: 'Other',
        isExpense: false, // money in
      );
    }

    m = _rScCard.firstMatch(text);
    if (m != null) {
      final merchant = _cardMerchant(m.group(2)!);
      return ParsedSms(
        reference: '',
        amount: _amount(m.group(1)!),
        date: m.group(3)!,
        source: 'CARD',
        counterparty: merchant,
        category: categorise(merchant),
        isExpense: true,
      );
    }
    m = _rScToMpesa.firstMatch(text);
    if (m != null) {
      final name = _cleanName(m.group(3)!);
      return ParsedSms(
        reference: m.group(2)!, // the M-Pesa code, so it is never saved twice
        amount: _amount(m.group(1)!),
        date: _iso(today ?? DateTime.now()), // the message has no date
        source: 'CARD',
        counterparty: name,
        category: categorise(name),
        isExpense: !_isOwnName(name, ownName),
      );
    }
    if (_rScMpesaNotice.hasMatch(text)) return null;
    m = _rScAccount.firstMatch(text);
    if (m != null) {
      return ParsedSms(
        reference: '',
        amount: _amount(m.group(1)!),
        date: _iso(today ?? DateTime.now()),
        source: 'CARD',
        counterparty: 'Account ending ${m.group(2)}',
        category: 'Transfer',
        isExpense: true,
      );
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
    final name = _cleanName(rawName
        .replaceAll(RegExp(r'\s+for account\s+\S+$', caseSensitive: false), '') // paybill
        .replaceAll(RegExp(r'\s+(?:teller|till)\s*\d*$', caseSensitive: false), ''));
    final isOwn = _isOwnName(name, ownName);
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

  /// True if [name] is the user's own name, e.g. a transfer to their own
  /// M-Pesa. Every word of [ownName] must appear, so "Jane Doe" matches
  /// "JANE WANJIRU DOE" but not "JANE SMITH".
  static bool _isOwnName(String name, String? ownName) {
    if (ownName == null || ownName.trim().isEmpty) return false;
    final words = name.toUpperCase().split(RegExp(r'[^A-Z]+')).toSet();
    final own = ownName
        .toUpperCase()
        .split(RegExp(r'[^A-Z]+'))
        .where((w) => w.length >= 2)
        .toList();
    return own.isNotEmpty && own.every(words.contains);
  }

  /// Absa merchant field: "BALTIC TEXTILE TRADING LTNAIROBI      KE" ->
  /// "BALTIC TEXTILE TRADING LT" (25 characters of name, then the town).
  static String _absaMerchant(String raw) {
    var field = raw.trim();
    if (field.toUpperCase().startsWith('POS ')) field = field.substring(4);
    // Fixed-width field as sent by the card network
    if (field.length >= 27 && RegExp(r'\s[A-Z]{2}$').hasMatch(field)) {
      return field.substring(0, 25).trim();
    }
    // Otherwise stop at the first run of spaces
    return field.split(RegExp(r'\s{2,}')).first.trim();
  }

  /// Card merchant names: "UBER PENDING" -> "UBER" (a hold not yet settled),
  /// "GOOGLE Google One" -> "Google One" (Google Play purchases).
  static String _cardMerchant(String raw) {
    var name = raw.trim().replaceAll(RegExp(r'\s+PENDING$', caseSensitive: false), '');
    final g = RegExp(r'^GOOGLE\s+(.+)$').firstMatch(name);
    if (g != null) name = g.group(1)!;
    return name.trim();
  }

  static double _amount(String s) => double.parse(s.replaceAll(',', ''));

  /// Removes a trailing phone number / masked number and trailing full stop.
  static String _cleanName(String s) => s
      .replaceAll(RegExp(r'\s*-\s*[\dxX*]{3,}$'), '') // "JOHN DOE-2547..." (masked phone)
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
      'home fibre', 'electricity', 'nhif', 'insurance', 'google one', 'icloud',
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
      'textile', 'china square', 'clothing', 'fashion',
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