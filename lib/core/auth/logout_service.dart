import 'dart:async';

import 'package:jetkiz_courier_app/core/device/device_registration_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';

class LogoutService {
  LogoutService({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
    PushRegistrationService? pushRegistrationService,
    DeviceRegistrationService? deviceRegistrationService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _tokenStorage = tokenStorage ?? TokenStorage(),
        _pushRegistrationService =
            pushRegistrationService ?? PushRegistrationService(),
        _deviceRegistrationService =
            deviceRegistrationService ?? DeviceRegistrationService();

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final PushRegistrationService _pushRegistrationService;
  final DeviceRegistrationService _deviceRegistrationService;

  /// Полный logout:
  /// 1. POST /notification-devices/unregister
  /// 2. DELETE /client-sessions/devices/:deviceId
  /// 3. POST /auth/logout
  /// 4. clear secure tokens
  ///
  /// Важно: даже если backend/unregister упал, локальные токены всё равно чистим.
  Future<void> logout() async {
    try {
      await _pushRegistrationService.unregisterCurrentToken();
    } catch (_) {
      // Не блокируем выход из-за FCM unregister.
    }

    try {
      await _deviceRegistrationService.deleteCurrentDevice();
    } catch (_) {
      // Не блокируем выход из-за device session delete.
    }

    try {
      await _apiClient.post('/auth/logout');
    } catch (_) {
      // Не блокируем локальный logout из-за backend logout.
    }

    await _tokenStorage.clear();
  }

  /// Аварийный локальный logout без backend-запросов.
  /// Использовать, если токены битые или надо принудительно выкинуть пользователя.
  Future<void> logoutLocalOnly() async {
    await _tokenStorage.clear();
  }

  Future<void> dispose() async {
    unawaited(_pushRegistrationService.dispose());
    _apiClient.dispose();
  }
}