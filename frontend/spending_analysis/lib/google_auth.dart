import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google sign-in on the phone. It only gets an ID token from Google; the
/// backend checks that token with Google before signing the user in.
///
/// Needs GOOGLE_SERVER_CLIENT_ID in the app's .env: the *Web* client ID from
/// Google Cloud (the same value as GOOGLE_CLIENT_ID on the backend).
class GoogleAuth {
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    final serverClientId = dotenv.env['GOOGLE_SERVER_CLIENT_ID'];
    if (serverClientId == null || serverClientId.isEmpty) {
      throw Exception('Google sign-in is not set up in the app yet');
    }
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _ready = true;
  }

  /// Shows Google's account picker. Returns the ID token, or null if the user
  /// closed the picker.
  static Future<String?> getIdToken() async {
    await _init();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw Exception('Google did not return a sign-in token');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw Exception('Google sign-in failed (${e.code.name})');
    }
  }

  /// Forget the Google account on this phone, so the picker appears next time.
  static Future<void> signOut() async {
    if (!_ready) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}