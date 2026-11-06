import 'package:flutter/material.dart';
import 'api_service.dart';

const Color _purple = Color(0xFF5B2EFF);
const Color _dark = Color(0xFF1A1A2E);

InputDecoration _fieldStyle(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
    prefixIcon: Icon(icon, color: Colors.black38, size: 20),
    filled: true,
    fillColor: Colors.white,
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey.shade200),
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _purple),
      borderRadius: BorderRadius.circular(12),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

ButtonStyle _primaryButton() => ElevatedButton.styleFrom(
      backgroundColor: _purple,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    );

PreferredSizeWidget _appBar(String title) => AppBar(
      title: Text(title,
          style: const TextStyle(color: _dark, fontWeight: FontWeight.bold, fontSize: 18)),
      backgroundColor: const Color(0xFFF5F5FA),
      foregroundColor: _dark,
      elevation: 0,
    );

// ── Edit profile ─────────────────────────────────────────────────────────────

/// Returns the updated profile map when saved, or null if cancelled.
class EditProfileScreen extends StatefulWidget {
  final String fullName;
  final String email;
  final String phone;
  const EditProfileScreen({
    super.key,
    required this.fullName,
    required this.email,
    required this.phone,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.fullName);
    _email = TextEditingController(text: widget.email);
    _phone = TextEditingController(text: widget.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Name and email cannot be empty');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Only send what changed
      final profile = await ApiService.updateProfile(
        fullName: name != widget.fullName ? name : null,
        email: email.toLowerCase() != widget.email.toLowerCase() ? email : null,
        phone: phone != widget.phone ? phone : null,
      );
      if (!mounted) return;
      Navigator.pop(context, profile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: _appBar('Edit profile'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: _fieldStyle('Full name', Icons.person_outline),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: _fieldStyle('Email', Icons.email_outlined),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('You will use this email to log in.',
                  style: TextStyle(color: Colors.black38, fontSize: 12)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: _fieldStyle('Phone number', Icons.phone_outlined),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                  'Your name is also used to recognise transfers to yourself in SMS.',
                  style: TextStyle(color: Colors.black38, fontSize: 12)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              style: _primaryButton(),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save changes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Change password ──────────────────────────────────────────────────────────

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  // Same five rules as registration (the backend checks them too)
  static bool _has8(String v) => v.length >= 8;
  static bool _hasUpper(String v) => v.contains(RegExp(r'[A-Z]'));
  static bool _hasLower(String v) => v.contains(RegExp(r'[a-z]'));
  static bool _hasNumber(String v) => v.contains(RegExp(r'[0-9]'));
  static bool _hasSymbol(String v) => v.contains(RegExp(r'[^A-Za-z0-9]'));

  bool get _isStrong {
    final v = _new.text;
    return _has8(v) && _hasUpper(v) && _hasLower(v) && _hasNumber(v) && _hasSymbol(v);
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password');
      return;
    }
    if (!_isStrong) {
      setState(() => _error = 'The new password must meet all five rules');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'The new passwords do not match');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.changePassword(
        currentPassword: _current.text,
        newPassword: _new.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Widget _passwordField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      obscureText: _obscure,
      onChanged: (_) => setState(() {}),
      decoration: _fieldStyle(label, Icons.lock_outline).copyWith(
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Colors.black38, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _new.text;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: _appBar('Change password'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _passwordField(_current, 'Current password'),
            const SizedBox(height: 14),
            _passwordField(_new, 'New password'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _Rule(label: '8+ characters', met: _has8(v)),
                _Rule(label: 'Uppercase', met: _hasUpper(v)),
                _Rule(label: 'Lowercase', met: _hasLower(v)),
                _Rule(label: 'Number', met: _hasNumber(v)),
                _Rule(label: 'Symbol', met: _hasSymbol(v)),
              ],
            ),
            const SizedBox(height: 14),
            _passwordField(_confirm, 'Confirm new password'),
            if (_confirm.text.isNotEmpty && _confirm.text != _new.text) ...[
              const SizedBox(height: 6),
              const Text('Passwords do not match',
                  style: TextStyle(color: Color(0xFFE53935), fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              style: _primaryButton(),
              onPressed: (_saving || !_isStrong || _new.text != _confirm.text) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Change password',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String label;
  final bool met;
  const _Rule({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 14, color: met ? _purple : Colors.black26),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: met ? _purple : Colors.black38)),
      ],
    );
  }
}