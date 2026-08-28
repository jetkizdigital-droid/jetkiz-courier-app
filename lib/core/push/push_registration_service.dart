import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../device/device_registration_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../network/apiClient.dart';

class PushRegistrationService {
  PushRegistrationService({
    ApiClient? apiClient,
    FirebaseMessaging? firebaseMessaging,
    DeviceInfoPlugin? deviceInfo,
    DeviceRegistrationService? deviceRegistrationService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _firebaseMessaging = FirebaseBootstrap.isAvailable
            ? firebaseMessaging ?? FirebaseMessaging.instance
            : null,
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _deviceRegistrationService =
            deviceRegistrationService ?? DeviceRegistrationService();

  final ApiClient _apiClient;
  final FirebaseMessaging? _firebaseMessaging;
  final DeviceInfoPlugin _deviceInfo;
  final DeviceRegistrationService _deviceRegistrationService;

  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Главный метод после успешного login / restore session.
  ///
  /// Делает:
  /// 1. Запрашивает permission.
  /// 2. Получает FCM token.
  /// 3. Регистрирует device session: POST /client-sessions/devices.
  /// 4. Регистрирует push token: POST /notification-devices/register.
  /// 5. Подписывается на onTokenRefresh.
  Future<PushRegistrationResult> initializeAndRegister() async {
    if (_firebaseMessaging == null) {
      await _deviceRegistrationService.registerDevice();

      return const PushRegistrationResult(
        success: false,
        permission: null,
        token: null,
        message: 'Firebase is not available',
        raw: null,
      );
    }

    final permission = await requestPermission();

    final token = await getToken();

    if (token == null || token.trim().isEmpty) {
      await _deviceRegistrationService.registerDevice();

      return PushRegistrationResult(
        success: false,
        permission: permission,
        token: null,
        message: 'FCM token is empty',
        raw: null,
      );
    }

    await _deviceRegistrationService.registerDevice(pushToken: token);

    final result = await registerToken(token);

    _listenTokenRefresh();

    return result.copyWith(permission: permission);
  }

  Future<PushPermissionResult> requestPermission() async {
    final firebaseMessaging = _firebaseMessaging;

    if (firebaseMessaging == null) {
      return const PushPermissionResult(
        authorizationStatus: 'unavailable',
        alert: 'unknown',
        badge: 'unknown',
        sound: 'unknown',
      );
    }

    try {
      final settings = await firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      return PushPermissionResult(
        authorizationStatus: settings.authorizationStatus.name,
        alert: settings.alert.name,
        badge: settings.badge.name,
        sound: settings.sound.name,
      );
    } catch (e) {
      return PushPermissionResult(
        authorizationStatus: 'error',
        alert: 'unknown',
        badge: 'unknown',
        sound: 'unknown',
        error: e.toString(),
      );
    }
  }

  Future<String?> getToken() async {
    final firebaseMessaging = _firebaseMessaging;

    if (firebaseMessaging == null) {
      return null;
    }

    try {
      final token = await firebaseMessaging.getToken();
      final normalized = token?.trim();

      if (normalized == null || normalized.isEmpty) {
        return null;
      }

      return normalized;
    } catch (_) {
      return null;
    }
  }

  /// Backend contract:
  /// POST /notification-devices/register
  ///
  /// Body:
  /// {
  ///   token,
  ///   platform,
  ///   deviceId?,
  ///   appVersion?,
  ///   osVersion?,
  ///   deviceModel?
  /// }
  ///
  /// Важно: app/source сюда НЕ добавляем. В текущем backend contract
  /// explicit app field нет.
  Future<PushRegistrationResult> registerToken(String token) async {
    final normalizedToken = token.trim();

    if (normalizedToken.isEmpty) {
      return const PushRegistrationResult(
        success: false,
        permission: null,
        token: null,
        message: 'FCM token is empty',
        raw: null,
      );
    }

    final deviceId = await _apiClient.getDeviceId();
    final deviceDetails = await _readDeviceDetails();
    final appVersion = await _readAppVersion();

    final body = <String, dynamic>{
      'token': normalizedToken,
      'platform': deviceDetails.platform,
      'deviceId': deviceId,
      'appVersion': appVersion,
      'osVersion': deviceDetails.osVersion,
      'deviceModel': deviceDetails.deviceModel,
    };

    final response = await _apiClient.post(
      '/notification-devices/register',
      body,
    );

    return PushRegistrationResult.fromResponse(
      response,
      token: normalizedToken,
    );
  }

  /// Backend contract:
  /// POST /notification-devices/unregister
  ///
  /// Обычно вызываем на logout.
  Future<void> unregisterCurrentToken() async {
    final token = await getToken();

    if (token == null || token.trim().isEmpty) {
      return;
    }

    await _apiClient.post('/notification-devices/unregister', {
      'token': token.trim(),
    });
  }

  void _listenTokenRefresh() {
    final firebaseMessaging = _firebaseMessaging;

    if (firebaseMessaging == null) {
      return;
    }

    _tokenRefreshSubscription?.cancel();

    _tokenRefreshSubscription = firebaseMessaging.onTokenRefresh.listen(
      (newToken) async {
        final token = newToken.trim();

        if (token.isEmpty) {
          return;
        }

        try {
          await _deviceRegistrationService.registerDevice(pushToken: token);
          await registerToken(token);
        } catch (_) {
          // Не валим приложение из-за refresh token registration.
          // Следующий запуск/restore session снова попробует регистрацию.
        }
      },
    );
  }

  Future<DeviceDetails> _readDeviceDetails() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;

        final manufacturer = info.manufacturer.trim();
        final model = info.model.trim();

        final deviceModel = [
          if (manufacturer.isNotEmpty) manufacturer,
          if (model.isNotEmpty) model,
        ].join(' ').trim();

        return DeviceDetails(
          platform: 'ANDROID',
          deviceModel: deviceModel.isEmpty ? 'Android' : deviceModel,
          osVersion: 'Android ${info.version.release}',
        );
      }

      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;

        final model = info.utsname.machine.trim().isNotEmpty
            ? info.utsname.machine.trim()
            : info.model.trim();

        return DeviceDetails(
          platform: 'IOS',
          deviceModel: model.isEmpty ? 'iOS Device' : model,
          osVersion: 'iOS ${info.systemVersion}',
        );
      }

      return DeviceDetails(
        platform: 'UNKNOWN',
        deviceModel: Platform.operatingSystem,
        osVersion: Platform.operatingSystemVersion,
      );
    } catch (_) {
      return const DeviceDetails(
        platform: 'UNKNOWN',
        deviceModel: 'Unknown device',
        osVersion: 'Unknown OS',
      );
    }
  }

  Future<String> _readAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();

      final version = info.version.trim();
      final buildNumber = info.buildNumber.trim();

      if (version.isEmpty && buildNumber.isEmpty) {
        return '1.0.0';
      }

      if (buildNumber.isEmpty) {
        return version;
      }

      return '$version+$buildNumber';
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}

class PushPermissionResult {
  const PushPermissionResult({
    required this.authorizationStatus,
    required this.alert,
    required this.badge,
    required this.sound,
    this.error,
  });

  final String authorizationStatus;
  final String alert;
  final String badge;
  final String sound;
  final String? error;

  bool get isGranted {
    return authorizationStatus == 'authorized' ||
        authorizationStatus == 'provisional';
  }

  Map<String, dynamic> toJson() {
    return {
      'authorizationStatus': authorizationStatus,
      'alert': alert,
      'badge': badge,
      'sound': sound,
      if (error != null) 'error': error,
    };
  }
}

class PushRegistrationResult {
  const PushRegistrationResult({
    required this.success,
    required this.permission,
    required this.token,
    required this.message,
    required this.raw,
  });

  final bool success;
  final PushPermissionResult? permission;
  final String? token;
  final String? message;
  final dynamic raw;

  PushRegistrationResult copyWith({
    bool? success,
    PushPermissionResult? permission,
    String? token,
    String? message,
    dynamic raw,
  }) {
    return PushRegistrationResult(
      success: success ?? this.success,
      permission: permission ?? this.permission,
      token: token ?? this.token,
      message: message ?? this.message,
      raw: raw ?? this.raw,
    );
  }

  factory PushRegistrationResult.fromResponse(
    dynamic response, {
    required String token,
  }) {
    if (response is Map<String, dynamic>) {
      return PushRegistrationResult(
        success: response['success'] == true ||
            response['id'] != null ||
            response['token'] != null,
        permission: null,
        token: response['token']?.toString() ?? token,
        message: response['message']?.toString(),
        raw: response,
      );
    }

    if (response is Map) {
      final mapped = Map<String, dynamic>.from(response);

      return PushRegistrationResult(
        success: mapped['success'] == true ||
            mapped['id'] != null ||
            mapped['token'] != null,
        permission: null,
        token: mapped['token']?.toString() ?? token,
        message: mapped['message']?.toString(),
        raw: mapped,
      );
    }

    return PushRegistrationResult(
      success: false,
      permission: null,
      token: token,
      message: null,
      raw: response,
    );
  }
}
