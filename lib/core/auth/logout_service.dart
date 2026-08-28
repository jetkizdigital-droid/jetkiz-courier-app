import 'dart:async';

import 'package:jetkiz_courier_app/core/device/device_registration_service.dart';
import 'package:jetkiz_courier_app/core/location/courier_location_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';

class LogoutService {
  LogoutService({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
    PushRegistrationService? pushRegistrationService,
    DeviceRegistrationService? deviceRegistrationService,
  }) : _apiClient = apiClient ?? ApiClient(),
       _tokenStorage = tokenStorage ?? TokenStorage(),
       _pushRegistrationService =
           pushRegistrationService ?? PushRegistrationService(),
       _deviceRegistrationService =
           deviceRegistrationService ?? DeviceRegistrationService();

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final PushRegistrationService _pushRegistrationService;
  final DeviceRegistrationService _deviceRegistrationService;

  Future<void> logout() async {
    // Presence must be changed while the access token is still valid.
    try {
      await _apiClient.post('/couriers/me/online-status', {'isOnline': false});
    } catch (_) {
      // Logout itself must remain possible if presence update is unavailable.
    }

    await CourierLocationService().stopTracking();

    try {
      await _pushRegistrationService.unregisterCurrentToken();
    } catch (_) {
      // Do not block logout because of FCM cleanup.
    }

    try {
      await _deviceRegistrationService.deleteCurrentDevice();
    } catch (_) {
      // Do not block logout because of device registry cleanup.
    }

    try {
      await _apiClient.post('/auth/logout');
    } catch (_) {
      // Local logout is authoritative for this device.
    }

    await _tokenStorage.clear();
  }

  Future<void> logoutLocalOnly() async {
    await CourierLocationService().stopTracking();
    await _tokenStorage.clear();
  }

  Future<void> dispose() async {
    unawaited(_pushRegistrationService.dispose());
    _apiClient.dispose();
  }
}
