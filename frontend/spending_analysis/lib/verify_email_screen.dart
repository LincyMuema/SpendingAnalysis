import 'package:flutter/material.dart';
import 'api_service.dart';

/// Confirm the account's email address with a 6-digit code.
///
/// Shown right after registering (the code was already emailed; the user can
/// skip and verify later), and from the Profile screen.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  /// Where to go after verifying or skipping (e.g. the Home screen after
  /// registering). If null, the screen just closes and returns true when verified.
  final Widget Function()? next;
  /// Send a code when the screen opens (from Profile). After registering the
  /// code has already been sent, so this is false.
  final bool sendOnOpen;
  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.next,
    this.sendOnOpen = false,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _purple = Color(0xFF5B2EFF);
  final _codeController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.sendOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resend(quiet: true));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _finish(bool verified) {
    if (widget.next != null) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => widget.next!()));
    } else {
      Navigator.pop(context, verified);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _show('Enter the 6-digit code from the email');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.verifyEmail(code: code);
      if (!mounted) return;
      _show('Email verified');
      _finish(true);
    } catch (e) {
      if (mounted) _show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend({bool quiet = false}) async {
    setState(() => _loading = true);
    try {
      final message = await ApiService.sendVerification();
      if (mounted && !quiet) _show(message);
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
        automaticallyImplyLeading: widget.next == null,
        title: const Text('Confirm your email',
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
                    child: const Icon(Icons.mark_email_unread_outlined,
                        color: _purple, size: 30),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'We sent a 6-digit code to ${widget.email}. Enter it to confirm this '
                  'is your email, so password-reset and sign-in codes reach you. '
                  'It expires in 10 minutes. Check your spam folder if you cannot see it.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
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
                      : const Text('Verify email',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : () => _resend(),
                      child: const Text('Send a new code',
                          style: TextStyle(color: _purple, fontWeight: FontWeight.w500)),
                    ),
                    if (widget.next != null)
                      TextButton(
                        onPressed: _loading ? null : () => _finish(false),
                        child: const Text('Skip for now',
                            style: TextStyle(color: Colors.black45)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}