import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_events.dart';
import 'login_screen.dart';
import 'sms_sync_service.dart';


class ProfileScreen extends StatefulWidget {
  final String fullName;
  final int userId;
  final String? email;
  const ProfileScreen(
      {super.key, required this.fullName, required this.userId, this.email});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _smsAllowed = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.transactionsChanged.addListener(_load);
  }

  @override
  void dispose() {
    AppEvents.transactionsChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final txs = await ApiService.getTransactions(userId: widget.userId);
      final allowed = await SmsSyncService.hasPermission();
      if (!mounted) return;
      setState(() {
        _transactions = txs;
        _smsAllowed = allowed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  double get _totalSpent =>
      _transactions.fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  int get _monthsTracked => _transactions
      .map((t) => (t['date'] as String).substring(0, 7))
      .toSet()
      .length;

  int get _fromSms =>
      _transactions.where((t) => t['is_manual'] == false).length;

  String _fmt(double v) {
    if (v >= 1000000) return 'KSh ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'KSh ${(v / 1000).toStringAsFixed(1)}k';
    return 'KSh ${v.toStringAsFixed(0)}';
  }

  String get _initials {
    final parts = widget.fullName.trim().split(RegExp(r'\s+'));
    return parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final r = await SmsSyncService.sync(
      userId: widget.userId,
      ownName: widget.fullName,
      sinceDays: 365,
    );
    if (!mounted) return;
    setState(() => _syncing = false);
    if (r.imported > 0) AppEvents.notifyTransactionsChanged();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.summary),
      action: r.permanentlyDenied
          ? SnackBarAction(
              label: 'Settings', onPressed: SmsSyncService.openSettings)
          : null,
    ));
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to see your spending.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Log out',
                style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        backgroundColor: const Color(0xFFF5F5FA),
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF5B2EFF),
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Identity
            _Card(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                        color: Color(0xFF5B2EFF), shape: BoxShape.circle),
                    child: Center(
                      child: Text(_initials.isEmpty ? '?' : _initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.fullName,
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        if (widget.email != null &&
                            widget.email!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(widget.email!,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Stats
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF5B2EFF))),
              )
            else
              Row(
                children: [
                  _Stat(label: 'Transactions', value: '${_transactions.length}'),
                  const SizedBox(width: 10),
                  _Stat(label: 'Months tracked', value: '$_monthsTracked'),
                  const SizedBox(width: 10),
                  _Stat(label: 'Total recorded', value: _fmt(_totalSpent)),
                ],
              ),
            const SizedBox(height: 20),

            // SMS import
            const _SectionTitle('SMS import'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _smsAllowed ? Icons.check_circle : Icons.sms_failed_outlined,
                        color: _smsAllowed
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9800),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _smsAllowed
                              ? 'SMS access allowed. Your messages sync automatically each time you open the app.'
                              : 'SMS access not allowed yet. Allow it to import M-Pesa, Airtel Money and bank transactions automatically.',
                          style: const TextStyle(
                              color: Color(0xFF1A1A2E), fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  if (!_loading) ...[
                    const SizedBox(height: 8),
                    Text('$_fromSms of your transactions came from SMS.',
                        style: const TextStyle(color: Colors.black45, fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _syncing ? null : _syncNow,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync, size: 18),
                      label: Text(_smsAllowed ? 'Sync now' : 'Allow SMS access'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B2EFF),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Privacy
            const _SectionTitle('Your data'),
            const _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bullet('Transaction messages are processed on your phone. Only the amount, date, merchant and payment method are saved, never the full message text.'),
                  _Bullet('Only messages from M-Pesa, Airtel Money and I&M Bank are read. Personal messages are skipped without being opened.'),
                  _Bullet('Your password is stored encrypted (hashed).'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // About
            const _SectionTitle('About'),
            const _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pesight  •  version 1.0.0',
                      style: TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  SizedBox(height: 6),
                  Text(
                    'Spending habits, unusual-transaction alerts and weekly forecasts are produced by machine learning models (K-Means, Isolation Forest and Random Forest). Forecasts are estimates, not guarantees.',
                    style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Log out
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE53935),
                side: const BorderSide(color: Color(0xFFE53935)),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small widgets ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Color(0xFF5B2EFF),
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.black45, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.bold,
              fontSize: 15)),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF5B2EFF)),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.black87, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}