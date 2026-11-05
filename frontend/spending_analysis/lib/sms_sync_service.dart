import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'sms_parser.dart';

class SmsSyncResult {
  final bool permissionDenied;
  final bool permanentlyDenied;
  final int scanned; // messages read from the inbox
  final int imported; // new transactions saved
  final int duplicates; // already in the database
  final int skipped; // income / transfers to yourself / too old
  final int failed; // could not be saved
  final String? error;

  const SmsSyncResult({
    this.permissionDenied = false,
    this.permanentlyDenied = false,
    this.scanned = 0,
    this.imported = 0,
    this.duplicates = 0,
    this.skipped = 0,
    this.failed = 0,
    this.error,
  });

  String get summary {
    if (error != null) return error!;
    if (imported == 0 && duplicates == 0 && failed == 0) {
      return 'No new transactions found in your messages.';
    }
    final parts = <String>[
      '$imported new',
      if (duplicates > 0) '$duplicates already saved',
      if (skipped > 0) '$skipped skipped',
      if (failed > 0) '$failed failed',
    ];
    return 'SMS sync done: ${parts.join(', ')}.';
  }
}

class SmsSyncService {
  /// Only messages from these senders are read. Personal messages are skipped
  /// without being parsed. Matching ignores case, spaces and symbols, and
  /// "contains" is used so variants like "AirtelMoneyy" still match.
  /// To support another bank, add its sender name here.
  static const List<String> financialSenders = [
    'MPESA',        // Safaricom M-Pesa
    'AIRTELMONEY',  // Airtel Money
    'IANDMBANK',    // I&M Bank
  ];

  static bool isFinancialSender(String? address) {
    final a = (address ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (a.isEmpty) return false;
    return financialSenders.any((s) => a.contains(s));
  }

  /// Reads the inbox, parses transaction messages and saves them.
  ///
  /// [ownName]  your name as it appears on transfers (e.g. "LINCY MUEMA"),
  ///            so transfers between your own accounts are skipped.
  /// [sinceDays] ignore messages older than this many days.
  static Future<SmsSyncResult> sync({
    required int userId,
    String? ownName,
    int sinceDays = 365,
  }) async {
    // 1. Permission
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }
    if (!status.isGranted) {
      return SmsSyncResult(
        permissionDenied: true,
        permanentlyDenied: status.isPermanentlyDenied,
        error: 'SMS permission is needed to find your transactions.',
      );
    }

    // 2. Read the inbox
    final List<SmsMessage> messages;
    try {
      messages = await SmsQuery().querySms(
        kinds: [SmsQueryKind.inbox],
        count: 1000,
      );
    } catch (e) {
      return SmsSyncResult(error: 'Could not read your messages: $e');
    }

    final cutoff = DateTime.now().subtract(Duration(days: sinceDays));
    final cutoffIso =
        '${cutoff.year.toString().padLeft(4, '0')}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';

    int imported = 0, duplicates = 0, skipped = 0, failed = 0;
    int consecutiveFailures = 0;

    for (final m in messages) {
      // Check the sender first: personal messages are never parsed
      if (!isFinancialSender(m.address)) continue;

      final body = (m.body ?? '').trim();
      if (body.isEmpty) continue;

      // If the message text has no readable date, use the date the SMS was
      // received on the phone (not today's date).
      final p = SmsParser.parse(body,
          ownName: ownName, today: m.date, sender: m.address);
      if (p == null) continue; // not a transaction message

      // DEBUG (only during `flutter run`): show messages read by the fallback
      if (kDebugMode && p.isFallback) {
        debugPrint('[SMS-FALLBACK] ${m.address}: $body');
      }

      // Income, transfers to yourself, and messages older than the cutoff
      if (!p.isExpense || p.date.compareTo(cutoffIso) < 0) {
        skipped++;
        continue;
      }

      // M-Pesa / Airtel have a code. Bank SMS do not, so use a stable
      // fingerprint of the message text so a rescan never duplicates it.
      final reference = p.reference.isNotEmpty ? p.reference : _bankRef(body);

      try {
        final res = await ApiService.createTransaction(
          userId: userId,
          amount: p.amount,
          date: p.date,
          source: p.source,
          counterparty: p.counterparty,
          categoryName: p.category,
          isManual: false,
          reference: reference,
        );
        consecutiveFailures = 0;
        if (res['duplicate'] == true) {
          duplicates++;
        } else {
          imported++;
        }
      } catch (_) {
        failed++;
        consecutiveFailures++;
        // Backend probably unreachable: stop instead of failing 100 times.
        if (consecutiveFailures >= 3) {
          return SmsSyncResult(
            scanned: messages.length,
            imported: imported,
            duplicates: duplicates,
            skipped: skipped,
            failed: failed,
            error:
                'Could not reach the server. Imported $imported before it stopped.',
          );
        }
      }
    }

    return SmsSyncResult(
      scanned: messages.length,
      imported: imported,
      duplicates: duplicates,
      skipped: skipped,
      failed: failed,
    );
  }

  static Future<void> openSettings() => openAppSettings();

  /// True if the user has already allowed SMS access (does not prompt).
  static Future<bool> hasPermission() => Permission.sms.isGranted;

  /// Stable 16-hex-digit fingerprint of the message text (fits VARCHAR(30)).
  static String _bankRef(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    var h1 = 0x811c9dc5;
    var h2 = 0x1b873593;
    for (final c in text.codeUnits) {
      h1 = ((h1 ^ c) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 + c) * 0x5bd1e995) & 0xFFFFFFFF;
      h2 ^= (h2 >> 15);
    }
    return 'BANK-${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }
}