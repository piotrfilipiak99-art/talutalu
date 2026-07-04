import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown for any failed API call; [message] is safe to show in a SnackBar.
class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin HTTP layer over the Talutalu backend (auth + sync).
/// Token lives in SharedPreferences under 'authToken' so logout's
/// prefs.clear() also drops the session.
class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  late SharedPreferences _p;

  void init(SharedPreferences prefs) => _p = prefs;

  /// Compile-time override: flutter run --dart-define=API_URL=https://...
  static const _envUrl = String.fromEnvironment('API_URL');

  String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;
    // The Android emulator reaches the host machine via 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  String? get token => _p.getString('authToken');
  bool get hasSession => token != null;

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _decode(http.Response res) async {
    final body = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiException(
        detail is String ? detail : 'Request failed (${res.statusCode})',
        res.statusCode,
      );
    }
    return Map<String, dynamic>.from(body as Map);
  }

  Future<Map<String, dynamic>> _post(String path, Object payload) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl$path'),
              headers: _jsonHeaders, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      return _decode(res);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  Future<void> _storeSession(Map<String, dynamic> auth) async {
    await _p.setString('authToken', auth['token'] as String);
    await _p.setString('accountEmail', auth['email'] as String);
  }

  Future<void> register(String email, String password) async =>
      _storeSession(await _post('/auth/register', {
        'email': email,
        'password': password,
      }));

  Future<void> login(String email, String password) async =>
      _storeSession(await _post('/auth/login', {
        'email': email,
        'password': password,
      }));

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Pushes [items] ({key: {value, updatedAt}}) and returns the server's
  /// full merged state in the same shape. Pass empty items for a pure pull.
  Future<Map<String, dynamic>> sync(Map<String, dynamic> items) async {
    try {
      final res = await http
          .put(Uri.parse('$baseUrl/sync'),
              headers: _jsonHeaders, body: jsonEncode({'items': items}))
          .timeout(const Duration(seconds: 20));
      final data = await _decode(res);
      return Map<String, dynamic>.from(data['items'] as Map);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Sync failed: server unreachable.');
    }
  }
}
