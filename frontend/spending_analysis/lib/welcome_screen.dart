import 'package:flutter/material.dart';
import 'app_prefs.dart';
import 'login_screen.dart';

/// Three short slides shown the first time the app is opened on a phone.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _Slide {
  final IconData icon;
  final String title;
  final String text;
  const _Slide(this.icon, this.title, this.text);
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _purple = Color(0xFF5B2EFF);
  static const _slides = [
    _Slide(Icons.pie_chart_outline, 'See where your money goes',
        'Pesight reads your M-Pesa and bank messages and groups your spending into habits, so you can see what you really spend on.'),
    _Slide(Icons.notification_important_outlined, 'Spot the unusual',
        'Double charges, late-night payments and spending far above your normal are flagged, with the reason for each.'),
    _Slide(Icons.calendar_month_outlined, 'Plan ahead',
        'See what you are likely to spend in the next four weeks, and which bills are coming up.'),
  ];

  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AppPrefs.setWelcomeSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: last ? null : _finish,
                  child: const Text('Skip', style: TextStyle(color: Colors.black45)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: _purple.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, color: _purple, size: 56),
                        ),
                        const SizedBox(height: 36),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 14),
                        Text(s.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 15, height: 1.5)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? _purple : Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(last ? 'Get started' : 'Next',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}