import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static String get _baseUrl => dotenv.env['API_BASE_URL'] ?? 'http://192.168.100.3:8000';

  // ── Register ────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data; // has: message, user_id, full_name, token
    } else {
      throw Exception(data['detail'] ?? 'Registration failed');
    }
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/authentication/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data; // has: message, user_id, full_name, token
    } else {
      throw Exception(data['detail'] ?? 'Login failed');
    }
  }

  // ── Get Transactions ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTransactions({
    required int userId,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/transactions/$userId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['transactions']);
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to load transactions');
    }
  }

  // ── Get Analysis ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getAnalysis({
    required int userId,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/analysis/$userId'),
      headers: {'Content-Type': 'application/json'},
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['detail'] ?? 'Failed to load analysis');
    }
  }

  // ── Create Transaction ──────────────────────────────────────────────────────
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
      headers: {'Content-Type': 'application/json'},
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

    final data = jsonDecode(response.body);

    // 201 = saved, 200 = duplicate SMS ignored by the backend
    if (response.statusCode == 201 || response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['detail'] ?? 'Failed to save transaction');
    }
  }

  // ── Update Category ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> updateCategory({
    required int transactionId,
    required String categoryName,
    bool applyToAll = false,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/transactions/$transactionId/category'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'category_name': categoryName,
        'apply_to_all': applyToAll,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['detail'] ?? 'Failed to update category');
    }
  }

  // ── Mark an anomaly as normal ───────────────────────────────────────────────
  static Future<void> dismissAnomaly({required int transactionId}) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/transactions/$transactionId/dismiss-anomaly'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['detail'] ?? 'Failed to update transaction');
    }
  }
}