import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://192.168.100.3:8000';

  // ── Login token ─────────────────────────────────────────────────────────────
  // Kept in memory only: it is cleared when the app closes or the user logs out.
  static String? _token;

  /// Set in main.dart so the app can return to the login screen
  /// when the session expires.
  static GlobalKey<NavigatorState>? navigatorKey;
  static Widget Function()? loginScreenBuilder;

  static bool get isLoggedIn => _token != null;

  static void logout() => _token = null;

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
      _token = null;
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
      _token = data['token'];
      return data; // has: message, user_id, full_name, token
    }
    throw Exception(data['detail'] ?? 'Registration failed');
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decode(response);
    if (response.statusCode == 200) {
      _token = data['token'];
      return data; // has: message, user_id, full_name, token
    }
    throw Exception(data['detail'] ?? 'Login failed');
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
  static Future<Map<String, dynamic>> getAnalysis({
    required int userId,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/analysis/$userId'),
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
}
