import 'package:jetkiz_courier_app/core/network/apiClient.dart';

class AuthApi {
  AuthApi({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> loginCourier({
    required String phone,
    required String password,
  }) async {
    final response = await _apiClient.postPublic(
      '/auth/courier/login-password',
      {'phone': phone.trim(), 'password': password},
    );

    return _asMap(response, path: '/auth/courier/login-password');
  }

  Future<Map<String, dynamic>> changeTemporaryPassword({
    required String phone,
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _apiClient
        .postPublic('/auth/courier/change-password', {
          'phone': phone.trim(),
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        });

    return _asMap(response, path: '/auth/courier/change-password');
  }

  Map<String, dynamic> _asMap(dynamic response, {required String path}) {
    if (response is Map<String, dynamic>) {
      return response;
    }

    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    throw ApiException.invalidResponse(method: 'POST', path: path);
  }

  void dispose() {
    _apiClient.dispose();
  }
}
