import '../domain/auth_entity.dart';
import 'auth_api.dart';

class AuthRepository {
  AuthRepository(this._api);

  final AuthApi _api;

  Future<CourierLoginResult> loginCourier(
    String phone,
    String password,
  ) async {
    final result = await _api.loginCourier(
      phone: phone,
      password: password,
    );

    final passwordChangeRequired = result['passwordChangeRequired'] == true;

    if (passwordChangeRequired) {
      final normalizedPhone = (result['phone'] ?? phone).toString().trim();
      final expiresAtRaw = result['temporaryPasswordExpiresAt']?.toString();

      return CourierLoginResult.passwordChangeRequired(
        phone: normalizedPhone,
        temporaryPasswordExpiresAt:
            expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw),
      );
    }

    return CourierLoginResult.authenticated(
      session: _parseSession(result),
    );
  }

  Future<AuthSession> changeTemporaryPassword({
    required String phone,
    required String currentPassword,
    required String newPassword,
  }) async {
    final result = await _api.changeTemporaryPassword(
      phone: phone,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    return _parseSession(result);
  }

  AuthSession _parseSession(Map<String, dynamic> result) {
    final accessToken = (result['accessToken'] ?? '').toString().trim();
    final refreshToken = (result['refreshToken'] ?? '').toString().trim();

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const FormatException('Auth tokens are missing in server response');
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  void dispose() {
    _api.dispose();
  }
}
