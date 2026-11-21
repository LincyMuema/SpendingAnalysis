import 'package:flutter/material.dart';
import 'app_prefs.dart';
import 'sms_sync_service.dart';

/// Profile > Accounts to read: choose which accounts' SMS Pesight reads,
/// for example to leave out a business bank account.
class SmsAccountsScreen extends StatefulWidget {
  final String ownName;
  const SmsAccountsScreen({super.key, required this.ownName});

  @override
  State<SmsAccountsScreen> createState() => _SmsAccountsScreenState();
}

class _SmsAccountsScreenState extends State<SmsAccountsScreen> {
  static const _purple = Color(0xFF5B2EFF);
  Set<String> _off = {};
  String? _busyKey; // account whose transactions are being removed

  @override
  void initState() {
    super.initState();
    AppPrefs.sourcesOff().then((v) {
      if (mounted) setState(() => _off = v);
    });
  }

  Future<void> _toggle(SmsSource s, bool on) async {
    if (on) {
      setState(() => _off.remove(s.key));
      await AppPrefs.setSourcesOff(_off);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${s.label} will be read from your next sync.')));
      return;
    }

    // Switching off: ask whether to also remove what was already imported
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop reading ${s.label}?'),
        content: Text(
          'New ${s.label} messages will no longer be imported.\n\n'
          'Transactions already imported from ${s.label} can also be removed, '
          'so they leave your analysis. Anything you typed in yourself is kept.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'keep'),
              child: const Text('Stop, keep old ones')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'remove'),
            child: const Text('Stop and remove',
                style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _off.add(s.key));
    await AppPrefs.setSourcesOff(_off);
    if (choice == 'keep' || !mounted) return;

    setState(() => _busyKey = s.key);
    String message;
    try {
      final n = await SmsSyncService.removeImportedFrom(s.key, ownName: widget.ownName);
      message = n == 0
          ? 'No imported ${s.label} transactions were found.'
          : 'Removed $n ${s.label} transaction${n == 1 ? '' : 's'}.';
    } catch (e) {
      message = e.toString().replaceAll('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _busyKey = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5FA),
        elevation: 0,
        title: const Text('Accounts to read',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Pesight only reads messages from the accounts switched on here. '
              'Switch off any account you do not want in your analysis, such as a business account. '
              'These settings are kept on this phone.',
              style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                for (final s in SmsSyncService.sources)
                  SwitchListTile(
                    title: Text(s.label, style: const TextStyle(fontSize: 14.5)),
                    subtitle: _busyKey == s.key
                        ? const Text('Removing imported transactions…',
                            style: TextStyle(fontSize: 12))
                        : null,
                    value: !_off.contains(s.key),
                    activeColor: _purple,
                    onChanged: _busyKey != null ? null : (on) => _toggle(s, on),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}