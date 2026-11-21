import 'package:flutter/material.dart';

/// Contact address shown in the Privacy Policy and Terms of Use.
const String kContactEmail = 'pesight26@gmail.com';
const String kLegalUpdated = '20 November 2026';

enum LegalDoc { privacy, terms }

/// Privacy Policy and Terms of Use, as two tabs.
class LegalScreen extends StatelessWidget {
  final LegalDoc initial;
  const LegalScreen({super.key, this.initial = LegalDoc.privacy});

  static void open(BuildContext context, LegalDoc doc) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen(initial: doc)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initial == LegalDoc.privacy ? 0 : 1,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F5FA),
          elevation: 0,
          title: const Text('Terms and Privacy',
              style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold, fontSize: 18)),
          bottom: const TabBar(
            labelColor: Color(0xFF5B2EFF),
            unselectedLabelColor: Colors.black45,
            indicatorColor: Color(0xFF5B2EFF),
            tabs: [Tab(text: 'Privacy Policy'), Tab(text: 'Terms of Use')],
          ),
        ),
        body: const TabBarView(
          children: [_LegalBody(_privacy), _LegalBody(_terms)],
        ),
      ),
    );
  }
}

class _Section {
  final String heading;
  final List<String> paragraphs;
  const _Section(this.heading, this.paragraphs);
}

class _LegalBody extends StatelessWidget {
  final List<_Section> sections;
  const _LegalBody(this.sections);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        const Text('Last updated: $kLegalUpdated',
            style: TextStyle(color: Colors.black45, fontSize: 12)),
        const SizedBox(height: 8),
        for (final s in sections) ...[
          const SizedBox(height: 14),
          Text(s.heading,
              style: const TextStyle(
                  color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          for (final p in s.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                p,
                style: const TextStyle(color: Colors.black87, fontSize: 13.5, height: 1.5),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Privacy Policy ───────────────────────────────────────────────────────────
const List<_Section> _privacy = [
  _Section('Who we are', [
    'Pesight is a personal spending analysis app developed as a final-year university project. '
        'This policy explains what Pesight collects, why, and the choices you have. '
        'For any question or request, email $kContactEmail.',
  ]),
  _Section('What we collect', [
    '• Account details: your name, email address, phone number and password. Your password is stored only in hashed (scrambled) form, so nobody can read it. If you sign in with Google, we receive your name, email address and Google account ID from Google.',
    '• Transaction details: the amount, date and time, merchant or recipient name, payment method (for example M-Pesa or card), category and transaction code of each payment, taken from your SMS or typed in by you.',
    '• Your choices in the app, such as categories you change and payments you mark as not unusual.',
    '• Results of the analysis of your spending, kept so the app can show them to you.',
  ]),
  _Section('What we do not collect', [
    'Pesight reads only messages from the financial senders listed in the app (M-Pesa, Airtel Money, I&M Bank, Co-operative Bank, Absa and Standard Chartered), and only those you have not switched off. '
        'Messages are read on your phone; the full text of a message is never sent to our server. '
        'Personal messages, contacts, photos and your location are never read or collected.',
  ]),
  _Section('Why we use it', [
    'Your information is used only to run Pesight for you: to show your transactions, group them into spending habits, flag unusual payments, forecast your spending and find regular bills. '
        'Your email address is also used to send verification, password-reset and sign-in codes. '
        'We do not sell your information, show you adverts or share it with anyone for marketing.',
    'Because Pesight is a university project, the results may be summarised in the project report without any names, phone numbers or other details that identify you.',
  ]),
  _Section('Your consent', [
    'We process your information with your consent, which you give when you create an account and when you allow SMS access. '
        'You can withdraw it at any time: switch off SMS access or individual accounts in your phone settings or in Profile, or delete your account.',
  ]),
  _Section('Where it is stored and who else handles it', [
    'Your information is stored on servers run by Render in Frankfurt, Germany, which is outside Kenya. Data travels between your phone and the server over an encrypted (HTTPS) connection.',
    'Emails with codes are sent through Brevo, an email service. If you use Google sign-in, Google confirms your identity. These services only receive what they need to do this.',
  ]),
  _Section('How long we keep it', [
    'Your information is kept for as long as you have an account. When you delete your account, your details, transactions and analysis results are deleted permanently and straight away. '
        'Sign-in codes expire after 10 minutes.',
  ]),
  _Section('Your rights', [
    'Under the Data Protection Act, 2019 of Kenya you have the right to be told how your information is used, to see it, to correct it, to have it deleted, and to object to its use. '
        'You can see your transactions in the app, correct your details in Profile, and delete your account at any time from Profile. For anything else, email $kContactEmail.',
    'If you are not satisfied with how your information is handled, you can complain to the Office of the Data Protection Commissioner (www.odpc.go.ke).',
  ]),
  _Section('Security', [
    'Passwords and codes are stored hashed, every request to the server needs your personal login token, and you can turn on two-step sign-in in Profile. '
        'No system is perfectly secure, so please keep your password private.',
  ]),
  _Section('Children', [
    'Pesight is meant for people aged 18 and over.',
  ]),
  _Section('Changes to this policy', [
    'If this policy changes, the new version will appear here with a new date.',
  ]),
];

// ── Terms of Use ─────────────────────────────────────────────────────────────
const List<_Section> _terms = [
  _Section('About these terms', [
    'By creating an account or using Pesight you agree to these terms and to the Privacy Policy. If you do not agree, please do not use the app.',
  ]),
  _Section('What Pesight is', [
    'Pesight is a free app, built as a university project, that helps you understand your own spending from your mobile money and bank messages. '
        'It is provided as it is, may change, and may be paused or stopped at any time, for example when the project ends.',
  ]),
  _Section('Not financial advice', [
    'Spending habits, unusual-payment alerts, forecasts and tips are produced automatically by machine learning models and simple rules. They are estimates and can be wrong. '
        'They are not financial, legal or professional advice. Always check important payments with your bank or mobile money provider, and report suspected fraud to them directly.',
  ]),
  _Section('Your account', [
    'You must be at least 18 years old and give correct details. Keep your password private; you are responsible for what happens in your account. '
        'Use Pesight only for your own messages and transactions, or those you are allowed to use.',
  ]),
  _Section('Acceptable use', [
    'Do not try to access other people\'s accounts or data, disrupt or overload the service, or copy or misuse the app.',
  ]),
  _Section('Ending your use', [
    'You can stop using Pesight and delete your account at any time from Profile. We may suspend an account that breaks these terms.',
  ]),
  _Section('Liability', [
    'Pesight is offered free of charge for learning and personal use. As far as the law allows, the developer is not responsible for losses that come from relying on the app, from incorrect readings of messages, or from the service being unavailable.',
  ]),
  _Section('Law and contact', [
    'These terms are governed by the laws of Kenya. Questions: $kContactEmail.',
  ]),
];

/// One line of text with tappable "Terms of Use" and "Privacy Policy" links,
/// e.g. LegalLinks(prefix: 'By continuing with Google, you agree to our ').
class LegalLinks extends StatelessWidget {
  final String prefix;
  final TextAlign align;
  const LegalLinks({super.key, required this.prefix, this.align = TextAlign.center});

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: Colors.black45, fontSize: 12, height: 1.5);
    const link = TextStyle(
        color: Color(0xFF5B2EFF), fontSize: 12, height: 1.5, fontWeight: FontWeight.w600);
    Widget tap(String text, LegalDoc doc) => GestureDetector(
          onTap: () => LegalScreen.open(context, doc),
          child: Text(text, style: link),
        );
    return Wrap(
      alignment: align == TextAlign.center ? WrapAlignment.center : WrapAlignment.start,
      children: [
        Text(prefix, style: base),
        tap('Terms of Use', LegalDoc.terms),
        const Text(' and ', style: base),
        tap('Privacy Policy', LegalDoc.privacy),
        const Text('.', style: base),
      ],
    );
  }
}