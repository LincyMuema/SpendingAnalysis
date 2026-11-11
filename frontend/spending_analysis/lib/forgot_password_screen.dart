import 'package:flutter/material.dart';
import 'api_service.dart';

/// Reset a forgotten password in two steps:
/// 1. enter the account email and receive a 6-digit code by email,
/// 2. enter the code and a new password.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _purple = Color(0xFF5B2EFF);

  late final _emailController = TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Same rules as the server, so the user sees what is missing straight away.
  String? _passwordProblem(String p) {
    final missing = <String>[
      if (p.length < 8) 'at least 8 characters',
      if (!RegExp(r'[A-Z]').hasMatch(p)) 'an uppercase letter',
      if (!RegExp(r'[a-z]').hasMatch(p)) 'a lowercase letter',
      if (!RegExp(r'[0-9]').hasMatch(p)) 'a number',
      if (!RegExp(r'[^A-Za-z0-9]').hasMatch(p)) 'a symbol',
    ];
    return missing.isEmpty ? null : 'Password needs ${missing.join(', ')}';
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _show('Enter the email address you registered with');
      return;
    }
    setState(() => _loading = true);
    try {
      final message = await ApiService.forgotPassword(email: email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _show(message);
    } catch (e) {
      if (mounted) _show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    if (code.length != 6) {
      _show('Enter the 6-digit code from the email');
      return;
    }
    final problem = _passwordProblem(password);
    if (problem != null) {
      _show(problem);
      return;
    }
    if (password != _confirmController.text) {
      _show('The two passwords do not match');
      return;
    }
    setState(() => _loading = true);
    try {
      final message = await ApiService.resetPassword(
        email: _emailController.text.trim(),
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      _show(message);
      Navigator.pop(context, _emailController.text.trim());
    } catch (e) {
      if (mounted) _show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _inputStyle(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      prefixIcon: Icon(icon, color: Colors.black38, size: 20),
      filled: true,
      fillColor: Colors.white,
      counterText: '',
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5FA),
        elevation: 0,
        foregroundColor: const Color(0xFF1A1A2E),
        title: const Text('Reset password',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _codeSent
                      ? 'We sent a 6-digit code to ${_emailController.text.trim()}. '
                          'Enter it below with your new password. The code expires in 10 minutes.'
                      : 'Enter the email you registered with and we will send you a code to reset your password.',
                  style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                _label('Email'),
                TextField(
                  controller: _emailController,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputStyle('jmwende@example.com', Icons.alternate_email),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  _label('Code from the email'),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: _inputStyle('123456', Icons.pin_outlined),
                  ),
                  const SizedBox(height: 16),
                  _label('New password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    decoration: _inputStyle('••••••••', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.black38,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'At least 8 characters with upper and lower case letters, a number and a symbol.',
                    style: TextStyle(color: Colors.black38, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  _label('Confirm new password'),
                  TextField(
                    controller: _confirmController,
                    obscureText: _obscure,
                    decoration: _inputStyle('••••••••', Icons.lock_outline),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : (_codeSent ? _resetPassword : _sendCode),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_codeSent ? 'Reset password' : 'Send code',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : _sendCode,
                      child: const Text('Send a new code',
                          style: TextStyle(color: _purple, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}