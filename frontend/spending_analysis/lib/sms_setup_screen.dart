import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_events.dart';
import 'app_prefs.dart';
import 'sms_sync_service.dart';

/// Shown after signing in when SMS access has not been given on this phone:
/// explains what is read, lets the user pick which accounts to read, then
/// asks Android for permission and runs the first sync.
class SmsSetupScreen extends StatefulWidget {
  final int userId;
  final String ownName;
  const SmsSetupScreen({super.key, required this.userId, required this.ownName});

  /// Opens the screen if this user has not seen it on this phone and SMS
  /// access is not allowed yet.
  static Future<void> showIfNeeded(BuildContext context,
      {required int userId, required String ownName}) async {
    if (await SmsSyncService.hasPermission()) return;
    if (await AppPrefs.smsSetupDone(userId)) return;
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SmsSetupScreen(userId: userId, ownName: ownName),
      ),
    );
  }

  @override
  State<SmsSetupScreen> createState() => _SmsSetupScreenState();
}

class _SmsSetupScreenState extends State<SmsSetupScreen> {
  static const _purple = Color(0xFF5B2EFF);
  Set<String> _off = {};
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    AppPrefs.sourcesOff().then((v) {
      if (mounted) setState(() => _off = v);
    });
  }

  Future<void> _notNow() async {
    await AppPrefs.setSmsSetupDone(widget.userId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _allow() async {
    setState(() {
      _working = true;
      _status = null;
    });
    await AppPrefs.setSourcesOff(_off);

    var status = await Permission.sms.status;
    if (!status.isGranted) status = await Permission.sms.request();
    if (!mounted) return;

    if (!status.isGranted) {
      setState(() => _working = false);
      if (status.isPermanentlyDenied) {
        // Android will not show the prompt again: send the user to Settings
        setState(() => _status =
            'SMS access is blocked for Pesight. Open Settings > Permissions > SMS and choose Allow, then come back.');
        await SmsSyncService.openSettings();
      } else {
        setState(() => _status =
            'SMS access was not allowed. You can still add transactions by hand, or allow it later in Profile.');
      }
      return;
    }

    await AppPrefs.setSmsSetupDone(widget.userId);
    if (!mounted) return;

    // Import in the background so the user can start using the app straight
    // away; a message appears when it finishes.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Importing your transactions. You can keep using the app.'),
      duration: Duration(seconds: 3),
    ));
    _importInBackground(messenger, widget.userId, widget.ownName);
  }

  /// Runs the first sync after this screen has closed, then reports the result.
  static Future<void> _importInBackground(
      ScaffoldMessengerState messenger, int userId, String ownName) async {
    try {
      final r = await SmsSyncService.sync(userId: userId, ownName: ownName, sinceDays: 365);
      if (r.cancelled) return;
      if (r.imported > 0) AppEvents.notifyTransactionsChanged();
      messenger.showSnackBar(SnackBar(content: Text(r.summary)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not import your messages. Try "Sync now" in Profile.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                          color: _purple.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.sms_outlined, color: _purple, size: 34),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Import your transactions from SMS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF1A1A2E), fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text(
                    'Pesight finds your payments in your M-Pesa and bank messages, so you do not have to type them in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  const _Point(Icons.check_circle_outline,
                      'Only messages from the accounts below are read.'),
                  const _Point(Icons.lock_outline,
                      'Messages are read on your phone. Only the amount, date, merchant and payment method are saved, never the message itself.'),
                  const _Point(Icons.block,
                      'Personal messages are never opened.'),
                  const SizedBox(height: 18),
                  const Text('Accounts to read',
                      style: TextStyle(
                          color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text(
                    'Switch off any account you do not want in your analysis, such as a business account.',
                    style: TextStyle(color: Colors.black45, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      children: [
                        for (final s in SmsSyncService.sources)
                          SwitchListTile(
                            dense: true,
                            title: Text(s.label, style: const TextStyle(fontSize: 14)),
                            value: !_off.contains(s.key),
                            activeColor: _purple,
                            onChanged: _working
                                ? null
                                : (on) => setState(() => on ? _off.remove(s.key) : _off.add(s.key)),
                          ),
                      ],
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 14),
                    Text(_status!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.4)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _working ? null : _allow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _purple.withOpacity(0.6),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _working
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Allow SMS access',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: _working ? null : _notNow,
                    child: const Text('Not now, I will add transactions myself',
                        style: TextStyle(color: Colors.black54)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF5B2EFF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}