import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<bool> hasSession() async {
    final access = await _storage.read(key: _accessTokenKey);
    final refresh = await _storage.read(key: _refreshTokenKey);

    return (access?.trim().isNotEmpty ?? false) &&
        (refresh?.trim().isNotEmpty ?? false);
  }
}