import 'package:flutter/material.dart';
import 'api_service.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _agreed = false;
  bool _isLoading = false;
  String _passwordStrength = '';
  Color _strengthColor = Colors.transparent;
  double _strengthValue = 0;

  // Password rules (the backend checks the same five rules)
  static bool _has8(String v) => v.length >= 8;
  static bool _hasUpper(String v) => v.contains(RegExp(r'[A-Z]'));
  static bool _hasLower(String v) => v.contains(RegExp(r'[a-z]'));
  static bool _hasNumber(String v) => v.contains(RegExp(r'[0-9]'));
  static bool _hasSymbol(String v) => v.contains(RegExp(r'[^A-Za-z0-9]'));

  bool get _passwordIsStrong {
    final v = _passwordController.text;
    return _has8(v) && _hasUpper(v) && _hasLower(v) && _hasNumber(v) && _hasSymbol(v);
  }

  void _checkStrength(String val) {
    if (val.isEmpty) {
      setState(() { _passwordStrength = ''; _strengthValue = 0; _strengthColor = Colors.transparent; });
      return;
    }
    final score = [_has8(val), _hasUpper(val), _hasLower(val), _hasNumber(val), _hasSymbol(val)]
        .where((ok) => ok)
        .length;
    setState(() {
      _strengthValue = score / 5;
      if (score <= 2) { _passwordStrength = 'Weak'; _strengthColor = Colors.red; }
      else if (score <= 4) { _passwordStrength = 'Almost there'; _strengthColor = Colors.orange; }
      else { _passwordStrength = 'Strong'; _strengthColor = Colors.green; }
    });
  }

  Future<void> _handleRegister() async {
    if (_fullNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }
    if (!_passwordIsStrong) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a stronger password: tick all five rules below it')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.register(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            fullName: result['full_name'],
            userId: result['user_id'],
            email: _emailController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputStyle(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.black38, size: 20),
      filled: true,
      fillColor: const Color(0xFFF7F7FB), // light grey so fields stand out on the white card
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF5B2EFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Center(
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B2EFF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Center(
                child: Text('Create your account',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text('Start mastering your spending with smart\nAI-driven insights',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45, fontSize: 13, height: 1.5)),
              ),
              const SizedBox(height: 28),

              // Form card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Full Name
                  const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _fullNameController,
                    decoration: _inputStyle('', Icons.person_outline, hint: 'Joan Mwende'),
                  ),
                  const SizedBox(height: 16),

                  // Email
                  const Text('Work or Personal Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputStyle('', Icons.email_outlined, hint: 'jmwende@example.com'),
                  ),
                  const SizedBox(height: 16),

                  // Phone
                  const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputStyle('', Icons.phone_outlined, hint: '+254 000 000 000'),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                      if (_passwordStrength.isNotEmpty)
                        Text(_passwordStrength, style: TextStyle(fontSize: 12, color: _strengthColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    onChanged: _checkStrength,
                    decoration: _inputStyle('', Icons.lock_outline, hint: '••••••••••••••••').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.black38, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_strengthValue > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _strengthValue,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _Check(label: '8+ characters', met: _has8(_passwordController.text)),
                        _Check(label: 'Uppercase', met: _hasUpper(_passwordController.text)),
                        _Check(label: 'Lowercase', met: _hasLower(_passwordController.text)),
                        _Check(label: 'Number', met: _hasNumber(_passwordController.text)),
                        _Check(label: 'Symbol', met: _hasSymbol(_passwordController.text)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Terms checkbox
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreed,
                        activeColor: const Color(0xFF5B2EFF),
                        onChanged: (v) => setState(() => _agreed = v!),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(color: Colors.black54, fontSize: 12),
                              children: [
                                TextSpan(text: "I agree to Pesight's "),
                                TextSpan(text: 'Terms of Service', style: TextStyle(color: Color(0xFF5B2EFF))),
                                TextSpan(text: ' and acknowledge our '),
                                TextSpan(text: 'Privacy Policy', style: TextStyle(color: Color(0xFF5B2EFF))),
                                TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Create account button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B2EFF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: (_agreed && _passwordIsStrong && !_isLoading) ? _handleRegister : null,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                  ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Or continue with
              const Center(child: Text('or continue with', style: TextStyle(color: Colors.black38, fontSize: 13))),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Colors.black12),
                  backgroundColor: Colors.white,
                ),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Google sign-in is coming soon')),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20, height: 20,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4285F4)),
                      child: const Icon(Icons.g_mobiledata, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text('Google', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Sign in link
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? ", style: TextStyle(color: Colors.black45)),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text('Sign In', style: TextStyle(color: Color(0xFF5B2EFF), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final String label;
  final bool met;
  const _Check({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 14, color: met ? const Color(0xFF5B2EFF) : Colors.black26),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: met ? const Color(0xFF5B2EFF) : Colors.black38)),
      ],
    );
  }
}