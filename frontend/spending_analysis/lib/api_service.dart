import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app_events.dart';

class ApiService {
  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://192.168.100.3:8000';

  // ── Login token ─────────────────────────────────────────────────────────────
  // Kept in memory while the app is open. If "Remember device" was ticked,
  // it is also saved in the phone's encrypted storage so the user stays
  // logged in after closing the app.
  static String? _token;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kToken = 'pesight_token';
  static const _kUserId = 'pesight_user_id';
  static const _kName = 'pesight_full_name';
  static const _kEmail = 'pesight_email';

  /// Set in main.dart so the app can return to the login screen
  /// when the session expires.
  static GlobalKey<NavigatorState>? navigatorKey;
  static Widget Function()? loginScreenBuilder;

  static bool get isLoggedIn => _token != null;

  /// Clears the token from memory and from the phone.
  static Future<void> logout() async {
    _token = null;
    AppEvents.fullName.value = null; // forget the previous user's name
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }

  static Future<void> _saveSession(Map<String, dynamic> data, String email) async {
    await _storage.write(key: _kToken, value: data['token'] as String);
    await _storage.write(key: _kUserId, value: '${data['user_id']}');
    await _storage.write(key: _kName, value: data['full_name'] as String);
    await _storage.write(key: _kEmail, value: email);
  }

  /// Called when the app opens. Returns the saved user (user_id, full_name,
  /// email) if this device was remembered and the session is still valid,
  /// otherwise null.
  static Future<Map<String, dynamic>?> restoreSession() async {
    String? token;
    try {
      token = await _storage.read(key: _kToken);
    } catch (_) {
      return null;
    }
    if (token == null) return null;

    final saved = {
      'user_id': int.tryParse(await _storage.read(key: _kUserId) ?? ''),
      'full_name': await _storage.read(key: _kName) ?? '',
      'email': await _storage.read(key: _kEmail),
    };
    if (saved['user_id'] == null) return null;

    try {
      // The free server can take up to a minute to wake up
      final response = await http
          .get(Uri.parse('$_baseUrl/authentication/me'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 75));
      if (response.statusCode == 200) {
        _token = token;
        return Map<String, dynamic>.from(_decode(response));
      }
      if (response.statusCode == 401) {
        await logout(); // expired: ask the user to log in again
        return null;
      }
    } catch (_) {
      // No internet or server asleep: open with the saved details; the
      // screens will load data once the server responds.
    }
    _token = token;
    return saved;
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> ? body : {'data': body};
    } catch (_) {
      return {'detail': 'Unexpected response from the server (${response.statusCode})'};
    }
  }

  /// Checks a response from a protected endpoint. On 401 the token is
  /// cleared and the user is sent back to the login screen.
  static Map<String, dynamic> _check(http.Response response, String fallback,
      {List<int> ok = const [200]}) {
    final data = _decode(response);
    if (ok.contains(response.statusCode)) return data;

    if (response.statusCode == 401) {
      logout();
      final nav = navigatorKey?.currentState;
      if (nav != null && loginScreenBuilder != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => loginScreenBuilder!()),
          (route) => false,
        );
      }
      throw Exception('Your session has expired. Please log in again.');
    }
    throw Exception(data['detail'] ?? fallback);
  }

  // ── Register ────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/register'),
      headers: _headers,
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
      }),
    );
    final data = _decode(response);
    if (response.statusCode == 200) {
      await logout(); // clear any previously remembered account
      _token = data['token'];
      return data; // has: message, user_id, full_name, token
    }
    throw Exception(data['detail'] ?? 'Registration failed');
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  /// Returns the user (user_id, full_name, token). If two-step sign-in is on,
  /// returns {'two_factor_required': true, 'email_hint': ...} instead and a
  /// code is emailed; finish with [verifyLogin].
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/login'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'remember_me': rememberMe,
      }),
    );
    final data = _decode(response);
    if (response.statusCode == 200) {
      if (data['two_factor_required'] == true) return data;
      await _completeLogin(data, email, rememberMe);
      return data; // has: message, user_id, full_name, token
    }
    throw Exception(data['detail'] ?? 'Login failed');
  }

  /// Second step of two-step sign-in: the 6-digit code from the email.
  static Future<Map<String, dynamic>> verifyLogin({
    required String email,
    required String code,
    bool rememberMe = false,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/verify-login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'code': code, 'remember_me': rememberMe}),
    );
    final data = _decode(response);
    if (response.statusCode == 200) {
      await _completeLogin(data, email, rememberMe);
      return data;
    }
    throw Exception(data['detail'] ?? 'Verification failed');
  }

  static Future<void> _completeLogin(
      Map<String, dynamic> data, String email, bool rememberMe) async {
    AppEvents.fullName.value = null;
    if (rememberMe) {
      _token = data['token'];
      try {
        await _saveSession(data, email);
      } catch (_) {} // still logged in for this session
    } else {
      await logout(); // forget any previously remembered account
      _token = data['token'];
    }
  }

  // ── Password reset ─────────────────────────────────────────────────────────
  /// Emails a 6-digit reset code (the reply is the same whether or not the
  /// email has an account).
  static Future<String> forgotPassword({required String email}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/forgot-password'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    final data = _decode(response);
    if (response.statusCode == 200) {
      return data['message'] as String? ?? 'Check your email for a code';
    }
    throw Exception(data['detail'] ?? 'Could not send the code');
  }

  static Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/reset-password'),
      headers: _headers,
      body: jsonEncode({'email': email, 'code': code, 'new_password': newPassword}),
    );
    final data = _decode(response);
    if (response.statusCode == 200) {
      return data['message'] as String? ?? 'Password reset';
    }
    throw Exception(data['detail'] ?? 'Could not reset the password');
  }

  // ── Get Transactions ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTransactions({
    required int userId,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/transactions/$userId'),
      headers: _headers,
    );
    final data = _check(response, 'Failed to load transactions');
    return List<Map<String, dynamic>>.from(data['transactions']);
  }

  // ── Get Analysis ───────────────────────────────────────────────────────────
  /// [days] is the period described (habits, categories, insights).
  static Future<Map<String, dynamic>> getAnalysis({
    required int userId,
    int days = 90,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/analysis/$userId?days=$days'),
      headers: _headers,
    );
    return Map<String, dynamic>.from(
        _check(response, 'Failed to load analysis'));
  }

  // ── Create Transaction ──────────────────────────────────────────────────────
  // userId is kept for compatibility; the backend takes the user from the token.
  static Future<Map<String, dynamic>> createTransaction({
    required int userId,
    required double amount,
    required String date,
    String? transactionType,
    String? source,
    String? counterparty,
    String categoryName = 'Other',
    bool isManual = true,
    String? reference,
    DateTime? occurredAt, // date and time of the payment, if known
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/transactions/'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'amount': amount,
        'date': date,
        'transaction_type': transactionType,
        'source': source,
        'counterparty': counterparty,
        'category_name': categoryName,
        'is_manual': isManual,
        'reference': reference,
        // Local phone time, e.g. 2026-11-06T14:22:00.000 (no time zone)
        'occurred_at': occurredAt?.toIso8601String(),
      }),
    );
    // 201 = saved, 200 = duplicate SMS ignored by the backend
    return _check(response, 'Failed to save transaction', ok: const [200, 201]);
  }

  // ── Update Category ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> updateCategory({
    required int transactionId,
    required String categoryName,
    bool applyToAll = false,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/transactions/$transactionId/category'),
      headers: _headers,
      body: jsonEncode({
        'category_name': categoryName,
        'apply_to_all': applyToAll,
      }),
    );
    return Map<String, dynamic>.from(
        _check(response, 'Failed to update category'));
  }

  // ── Mark an anomaly as normal ───────────────────────────────────────────────
  static Future<void> dismissAnomaly({required int transactionId}) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/transactions/$transactionId/dismiss-anomaly'),
      headers: _headers,
    );
    _check(response, 'Failed to update transaction');
  }

  // ── Categories ──────────────────────────────────────────────────────────────
  /// Standard categories plus the user's own. Each item has
  /// category_id, name, icon and is_custom.
  static Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/categories/'),
      headers: _headers,
    );
    final data = _check(response, 'Failed to load categories');
    return List<Map<String, dynamic>>.from(data['categories']);
  }

  static Future<Map<String, dynamic>> createCategory({required String name}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/categories/'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    final data = _check(response, 'Failed to create category', ok: const [201]);
    return Map<String, dynamic>.from(data['category']);
  }

  static Future<String> deleteCategory({required int categoryId}) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/categories/$categoryId'),
      headers: _headers,
    );
    final data = _check(response, 'Failed to delete category');
    return (data['message'] as String?) ?? 'Category deleted';
  }

  // ── Profile ────────────────────────────────────────────────────────────────
  /// user_id, full_name, email, phone, member_since
  static Future<Map<String, dynamic>> getProfile() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/authentication/me'),
      headers: _headers,
    );
    return Map<String, dynamic>.from(_check(response, 'Failed to load profile'));
  }

  /// Only the fields given are changed. Returns the updated profile.
  static Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? email,
    String? phone,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/authentication/me'),
      headers: _headers,
      body: jsonEncode({
        if (fullName != null) 'full_name': fullName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      }),
    );
    final data = _check(response, 'Failed to update profile');
    final profile = Map<String, dynamic>.from(data['profile']);

    // Keep the remembered details in step with the new name/email
    try {
      if (await _storage.read(key: _kToken) != null) {
        await _storage.write(key: _kName, value: profile['full_name'] as String);
        await _storage.write(key: _kEmail, value: profile['email'] as String);
      }
    } catch (_) {}
    return profile;
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/change-password'),
      headers: _headers,
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    _check(response, 'Failed to change password');
  }

  /// Turns two-step sign-in on or off (needs the current password).
  static Future<bool> setTwoFactor({
    required bool enabled,
    required String password,
  }) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/authentication/two-factor'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled, 'password': password}),
    );
    final data = _check(response, 'Failed to update two-step sign-in');
    return data['two_factor_enabled'] == true;
  }
}