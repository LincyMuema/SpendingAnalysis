import 'package:flutter/material.dart';
import 'api_service.dart';
import 'home_screen.dart';

/// Second step of two-step sign-in: the user enters the 6-digit code that
/// was emailed after their password was accepted.
class VerifyLoginScreen extends StatefulWidget {
  final String email;
  final String password;     // kept only to send a new code
  final bool rememberMe;
  final String? emailHint;   // e.g. j*****@gmail.com
  const VerifyLoginScreen({
    super.key,
    required this.email,
    required this.password,
    required this.rememberMe,
    this.emailHint,
  });

  @override
  State<VerifyLoginScreen> createState() => _VerifyLoginScreenState();
}

class _VerifyLoginScreenState extends State<VerifyLoginScreen> {
  static const _purple = Color(0xFF5B2EFF);
  final _codeController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _show('Enter the 6-digit code from the email');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService.verifyLogin(
        email: widget.email,
        code: code,
        rememberMe: widget.rememberMe,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            fullName: result['full_name'],
            userId: result['user_id'],
            email: widget.email,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) _show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Signing in again with the same details emails a new code.
  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      await ApiService.login(
        email: widget.email,
        password: widget.password,
        rememberMe: widget.rememberMe,
      );
      if (mounted) _show('A new code has been sent');
    } catch (e) {
      if (mounted) _show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5FA),
        elevation: 0,
        foregroundColor: const Color(0xFF1A1A2E),
        title: const Text('Check your email',
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
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.mark_email_read_outlined, color: _purple, size: 30),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Two-step sign-in is on for this account. We sent a 6-digit code to '
                  '${widget.emailHint ?? widget.email}. It expires in 10 minutes.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: const TextStyle(
                      fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: '000000',
                    hintStyle: const TextStyle(color: Colors.black12, letterSpacing: 10),
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF5F5FA),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _purple),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : _verify,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Verify and sign in',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _loading ? null : _resend,
                    child: const Text('Send a new code',
                        style: TextStyle(color: _purple, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}