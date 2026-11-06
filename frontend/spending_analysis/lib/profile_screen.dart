import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_events.dart';
import 'edit_profile_screen.dart';
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

  // Profile details (refreshed from the server; start with what login gave us)
  late String _name = widget.fullName;
  late String _email = widget.email ?? '';
  String _phone = '';
  String? _memberSince;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

  Future<void> _loadProfile() async {
    try {
      final p = await ApiService.getProfile();
      if (!mounted) return;
      setState(() => _applyProfile(p));
    } catch (_) {
      // Keep the details we already have
    }
  }

  void _applyProfile(Map<String, dynamic> p) {
    _name = (p['full_name'] as String?) ?? _name;
    _email = (p['email'] as String?) ?? _email;
    _phone = (p['phone'] as String?) ?? '';
    _memberSince = p['member_since'] as String?;
    AppEvents.fullName.value = _name;
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(fullName: _name, email: _email, phone: _phone),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _applyProfile(updated));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  void _changePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
  }

  String get _memberSinceLabel {
    final d = DateTime.tryParse(_memberSince ?? '');
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Member since ${months[d.month - 1]} ${d.year}';
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  int get _fromSms =>
      _transactions.where((t) => t['is_manual'] == false).length;

  String get _initials {
    final parts = _name.trim().split(RegExp(r'\s+'));
    return parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final r = await SmsSyncService.sync(
      userId: widget.userId,
      ownName: _name,
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
              ApiService.logout();
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
                        Text(_name,
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        if (_email.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(_email,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 13)),
                        ],
                        if (_phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(_phone,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 13)),
                        ],
                        if (_memberSinceLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_memberSinceLabel,
                              style: const TextStyle(
                                  color: Colors.black38, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit profile',
                    onPressed: _editProfile,
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF5B2EFF)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

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

            // Account
            const _SectionTitle('Account'),
            _Card(
              child: Column(
                children: [
                  _ActionRow(
                    icon: Icons.person_outline,
                    label: 'Edit profile',
                    subtitle: 'Name, email and phone number',
                    onTap: _editProfile,
                  ),
                  const Divider(height: 1, color: Colors.black12),
                  _ActionRow(
                    icon: Icons.lock_outline,
                    label: 'Change password',
                    subtitle: 'Requires your current password',
                    onTap: _changePassword,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Privacy (tap to expand)
            const _CollapsibleCard(
              icon: Icons.shield_outlined,
              title: 'Your data and privacy',
              children: [
                  _Bullet('Transaction messages are processed on your phone. Only the amount, date, merchant and payment method are saved, never the full message text.'),
                  _Bullet('Only messages from M-Pesa, Airtel Money and I&M Bank are read. Personal messages are skipped without being opened.'),
                  _Bullet('Your password is stored encrypted (hashed), and every request to the server needs your login token.'),
              ],
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 12),

            // About (tap to expand)
            const _CollapsibleCard(
              icon: Icons.info_outline,
              title: 'About Pesight',
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

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF5B2EFF), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.black45, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

/// A card that shows only its title until tapped.
class _CollapsibleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _CollapsibleCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Theme(
        // Removes the divider lines ExpansionTile draws when open
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: const Color(0xFF5B2EFF)),
          title: Text(title,
              style: const TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          iconColor: const Color(0xFF5B2EFF),
          collapsedIconColor: Colors.black38,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}