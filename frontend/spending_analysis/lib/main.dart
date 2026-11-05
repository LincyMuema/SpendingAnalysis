import 'package:flutter/material.dart';
import 'register_screen.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'analysis_screen.dart';
import 'transactions_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_service.dart';

// Lets the API service return to the login screen when a session expires
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
     await dotenv.load(fileName: ".env");
     ApiService.navigatorKey = navigatorKey;
     ApiService.loginScreenBuilder = () => const LoginScreen();
     runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pesight',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}