import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String baseUrl = String.fromEnvironment(
    'JETKIZ_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );
  static const Duration _timeout = Duration(seconds: 15);

  Future<void> requestCode(String phone) async {
    final normalizedPhone = phone.trim();

    if (normalizedPhone.isEmpty) {
      throw Exception('phone is empty');
    }

    final response = await _post(
      '/auth/request-code',
      body: {'phone': normalizedPhone},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'request-code failed: ${response.statusCode} ${_safeBody(response.body)}',
      );
    }
  }

  Future<Map<String, dynamic>> verifyCode({
    required String phone,
    required String code,
  }) async {
    final normalizedPhone = phone.trim();
    final normalizedCode = code.trim();

    if (normalizedPhone.isEmpty) {
      throw Exception('phone is empty');
    }

    if (normalizedCode.isEmpty) {
      throw Exception('code is empty');
    }

    final response = await _post(
      '/auth/verify-code',
      body: {'phone': normalizedPhone, 'code': normalizedCode},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'verify-code failed: ${response.statusCode} ${_safeBody(response.body)}',
      );
    }

    final decoded = _decodeJson(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('verify-code returned invalid json');
    }

    return decoded;
  }

  Future<http.Response> _post(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');

    try {
      return await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-App': 'courier',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw Exception('request timeout: $path');
    } on http.ClientException catch (e) {
      throw Exception('network error: ${e.message}');
    } catch (e) {
      throw Exception('request failed: $e');
    }
  }

  dynamic _decodeJson(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      throw Exception('server returned invalid json: ${_safeBody(source)}');
    }
  }

  String _safeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return '<empty body>';
    }
    return trimmed;
  }

  void dispose() {
    _client.close();
  }
}
