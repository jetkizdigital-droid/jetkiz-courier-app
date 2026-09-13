import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../device/device_registration_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../network/apiClient.dart';

class PushRegistrationService {
  PushRegistrationService({
    ApiClient? apiClient,
    FirebaseMessaging? firebaseMessaging,
    DeviceInfoPlugin? deviceInfo,
    DeviceRegistrationService? deviceRegistrationService,
  }) : _apiClient = apiClient ?? ApiClient(),
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

  /// Registers the current authenticated courier device for push.
  ///
  /// The system permission is requested only while it is still not determined.
  /// Once the user has made a choice, login/restore/resume only read that choice
  /// and never keep prompting.
  Future<PushRegistrationResult> initializeAndRegister() async {
    final firebaseMessaging = _firebaseMessaging;
    if (firebaseMessaging == null) {
      _log('firebase unavailable; push registration skipped');
      await _registerDeviceBestEffort();
      return const PushRegistrationResult(
        success: false,
        permission: null,
        token: null,
        message: 'Firebase is not available',
        failureStage: PushRegistrationFailureStage.firebase,
        raw: null,
      );
    }

    final permission = await ensurePermission(requestIfNotDetermined: true);
    _log('permission=${permission.authorizationStatus}');

    if (!permission.isGranted) {
      await _registerDeviceBestEffort();
      return PushRegistrationResult(
        success: false,
        permission: permission,
        token: null,
        message: 'Notification permission is not granted',
        failureStage: PushRegistrationFailureStage.permission,
        raw: null,
      );
    }

    final token = await _getTokenRaw();
    if (token == null) {
      _log('FCM token unavailable');
      await _registerDeviceBestEffort();
      return PushRegistrationResult(
        success: false,
        permission: permission,
        token: null,
        message: 'FCM token is empty',
        failureStage: PushRegistrationFailureStage.token,
        raw: null,
      );
    }

    _log('FCM token received ${_maskToken(token)}');

    try {
      await _deviceRegistrationService.registerDevice(pushToken: token);
      _log('device session registered with push token');
    } catch (error) {
      _log('device session registration failed: ${_safeError(error)}');
      // Notification-device registration below is the source of truth for push.
      // Do not abort it because the auxiliary client-session write failed.
    }

    try {
      var result = await registerToken(token);
      if (!result.success) {
        final verified = await _verifyBackendRegistration();
        if (verified) {
          result = result.copyWith(
            success: true,
            message: 'Push token registration verified',
            failureStage: PushRegistrationFailureStage.none,
          );
        }
      }

      if (result.success) {
        _log('backend push token registration succeeded ${_maskToken(token)}');
        _listenTokenRefresh();
      } else {
        _log('backend push token registration returned success=false');
      }
      return result.copyWith(permission: permission);
    } catch (error) {
      _log('backend push token registration failed: ${_safeError(error)}');

      // A network response can be lost after the server committed the token.
      // Verify the current device once before reporting registration failure.
      try {
        if (await _verifyBackendRegistration()) {
          _log('backend push token registration recovered by verification');
          _listenTokenRefresh();
          return PushRegistrationResult(
            success: true,
            permission: permission,
            token: token,
            message: 'Push token registration verified',
            failureStage: PushRegistrationFailureStage.none,
            raw: null,
          );
        }
      } catch (_) {}

      return PushRegistrationResult(
        success: false,
        permission: permission,
        token: token,
        message: 'Push token registration failed',
        failureStage: PushRegistrationFailureStage.backend,
        raw: null,
      );
    }
  }

  /// Reads the current OS/Firebase notification permission without prompting.
  /// On Android the OS permission is the final authority. This avoids a stale
  /// Firebase authorization snapshot incorrectly reporting notifications as
  /// denied while Android Settings already shows them as allowed.
  Future<PushPermissionResult> checkPermission() async {
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
      final settings = await firebaseMessaging.getNotificationSettings();
      final firebaseResult = PushPermissionResult.fromSettings(settings);

      if (!Platform.isAndroid) return firebaseResult;

      final nativeStatus = await permissions.Permission.notification.status;
      if (nativeStatus.isGranted || nativeStatus.isLimited) {
        return firebaseResult.copyWith(
          authorizationStatus: 'authorized',
          nativeStatus: nativeStatus.name,
        );
      }

      if (nativeStatus.isDenied || nativeStatus.isPermanentlyDenied) {
        return firebaseResult.copyWith(
          authorizationStatus: 'denied',
          nativeStatus: nativeStatus.name,
        );
      }

      return firebaseResult.copyWith(nativeStatus: nativeStatus.name);
    } catch (error) {
      return PushPermissionResult(
        authorizationStatus: 'error',
        alert: 'unknown',
        badge: 'unknown',
        sound: 'unknown',
        error: _safeError(error),
      );
    }
  }

  Future<PushPermissionResult> ensurePermission({
    bool requestIfNotDetermined = false,
  }) async {
    final current = await checkPermission();
    if (!requestIfNotDetermined || !current.isNotDetermined) {
      return current;
    }
    return requestPermission();
  }

  /// Explicit permission request. Android uses the native notification
  /// permission first, then refreshes Firebase's view of that permission.
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
      if (Platform.isAndroid) {
        final nativeStatus = await permissions.Permission.notification
            .request();
        _log('native notification permission=${nativeStatus.name}');

        // Refresh Firebase Messaging state as well. On Android this call is
        // harmless after the native permission dialog has been resolved.
        try {
          await firebaseMessaging.requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );
        } catch (_) {}

        return await checkPermission();
      }

      final settings = await firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      return PushPermissionResult.fromSettings(settings);
    } catch (error) {
      return PushPermissionResult(
        authorizationStatus: 'error',
        alert: 'unknown',
        badge: 'unknown',
        sound: 'unknown',
        error: _safeError(error),
      );
    }
  }

  /// Used by the profile switch as well as diagnostics. It never returns a
  /// token while notification permission is denied.
  Future<String?> getToken({bool requestPermissionIfNeeded = true}) async {
    if (_firebaseMessaging == null) return null;

    final permission = await ensurePermission(
      requestIfNotDetermined: requestPermissionIfNeeded,
    );
    _log('token request permission=${permission.authorizationStatus}');
    if (!permission.isGranted) return null;

    return _getTokenRaw();
  }

  Future<String?> _getTokenRaw() async {
    final firebaseMessaging = _firebaseMessaging;
    if (firebaseMessaging == null) return null;

    try {
      if (Platform.isIOS) {
        final apnsReady = await _waitForApnsToken(firebaseMessaging);
        if (!apnsReady) {
          _log('APNs token unavailable; FCM token request deferred');
          return null;
        }
      }

      final token = await firebaseMessaging.getToken();
      final normalized = token?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } catch (error) {
      _log('FCM getToken failed: ${_safeError(error)}');
      return null;
    }
  }

  Future<bool> _waitForApnsToken(FirebaseMessaging firebaseMessaging) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final token = await firebaseMessaging.getAPNSToken();
      if (token != null && token.trim().isNotEmpty) {
        return true;
      }

      if (attempt < 19) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    return false;
  }

  /// Backend contract: POST /notification-devices/register
  Future<PushRegistrationResult> registerToken(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return const PushRegistrationResult(
        success: false,
        permission: null,
        token: null,
        message: 'FCM token is empty',
        failureStage: PushRegistrationFailureStage.token,
        raw: null,
      );
    }

    final deviceId = await _apiClient.getDeviceId();
    final deviceDetails = await _readDeviceDetails();
    final appVersion = await _readAppVersion();

    final response = await _apiClient.post('/notification-devices/register', {
      'app': 'courier',
      'token': normalizedToken,
      'platform': deviceDetails.platform,
      'deviceId': deviceId,
      'appVersion': appVersion,
      'osVersion': deviceDetails.osVersion,
      'deviceModel': deviceDetails.deviceModel,
    });

    return PushRegistrationResult.fromResponse(
      response,
      token: normalizedToken,
    );
  }

  Future<bool> _verifyBackendRegistration() async {
    final deviceId = await _apiClient.getDeviceId();
    final response = await _apiClient.get('/notification-devices');
    final envelope = _asMap(response);
    final items = envelope['items'];
    if (items is! List) return false;

    for (final item in items) {
      final mapped = _asMap(item);
      if (mapped['deviceId']?.toString() == deviceId &&
          mapped['isActive'] == true) {
        return true;
      }
    }
    return false;
  }

  /// Backend contract: POST /notification-devices/unregister
  Future<void> unregisterCurrentToken() async {
    final token = await _getTokenRaw();
    if (token == null) return;

    await _apiClient.post('/notification-devices/unregister', {'token': token});
    _log('current push token unregistered ${_maskToken(token)}');
  }

  void _listenTokenRefresh() {
    final firebaseMessaging = _firebaseMessaging;
    if (firebaseMessaging == null) return;

    unawaited(_tokenRefreshSubscription?.cancel());
    _tokenRefreshSubscription = firebaseMessaging.onTokenRefresh.listen((
      newToken,
    ) async {
      final token = newToken.trim();
      if (token.isEmpty) return;

      _log('FCM token refreshed ${_maskToken(token)}');
      try {
        final permission = await checkPermission();
        if (!permission.isGranted) {
          _log(
            'refreshed token ignored because permission=${permission.authorizationStatus}',
          );
          return;
        }
        try {
          await _deviceRegistrationService.registerDevice(pushToken: token);
        } catch (error) {
          _log('refresh device registration failed: ${_safeError(error)}');
        }
        final result = await registerToken(token);
        _log('refreshed token backend success=${result.success}');
      } catch (error) {
        _log('refreshed token registration failed: ${_safeError(error)}');
      }
    });
  }

  Future<void> _registerDeviceBestEffort() async {
    try {
      await _deviceRegistrationService.registerDevice();
    } catch (error) {
      _log('device registration without push failed: ${_safeError(error)}');
    }
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
      if (version.isEmpty && buildNumber.isEmpty) return '1.0.0';
      if (buildNumber.isEmpty) return version;
      return '$version+$buildNumber';
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _maskToken(String token) {
    if (token.length <= 12) return '***';
    return '${token.substring(0, 6)}...${token.substring(token.length - 6)}';
  }

  static String _safeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 220 ? text : '${text.substring(0, 220)}…';
  }

  static void _log(String message) {
    developer.log('[PUSH] $message', name: 'jetkiz.courier.push');
  }
}

class PushPermissionResult {
  const PushPermissionResult({
    required this.authorizationStatus,
    required this.alert,
    required this.badge,
    required this.sound,
    this.nativeStatus,
    this.error,
  });

  factory PushPermissionResult.fromSettings(NotificationSettings settings) {
    return PushPermissionResult(
      authorizationStatus: settings.authorizationStatus.name,
      alert: settings.alert.name,
      badge: settings.badge.name,
      sound: settings.sound.name,
    );
  }

  final String authorizationStatus;
  final String alert;
  final String badge;
  final String sound;
  final String? nativeStatus;
  final String? error;

  bool get isGranted =>
      authorizationStatus == 'authorized' ||
      authorizationStatus == 'provisional';

  bool get isNotDetermined => authorizationStatus == 'notDetermined';

  PushPermissionResult copyWith({
    String? authorizationStatus,
    String? alert,
    String? badge,
    String? sound,
    String? nativeStatus,
    String? error,
  }) {
    return PushPermissionResult(
      authorizationStatus: authorizationStatus ?? this.authorizationStatus,
      alert: alert ?? this.alert,
      badge: badge ?? this.badge,
      sound: sound ?? this.sound,
      nativeStatus: nativeStatus ?? this.nativeStatus,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'authorizationStatus': authorizationStatus,
      'alert': alert,
      'badge': badge,
      'sound': sound,
      if (nativeStatus != null) 'nativeStatus': nativeStatus,
      if (error != null) 'error': error,
    };
  }
}

enum PushRegistrationFailureStage { none, firebase, permission, token, backend }

class PushRegistrationResult {
  const PushRegistrationResult({
    required this.success,
    required this.permission,
    required this.token,
    required this.message,
    required this.raw,
    this.failureStage = PushRegistrationFailureStage.none,
  });

  final bool success;
  final PushPermissionResult? permission;
  final String? token;
  final String? message;
  final dynamic raw;
  final PushRegistrationFailureStage failureStage;

  PushRegistrationResult copyWith({
    bool? success,
    PushPermissionResult? permission,
    String? token,
    String? message,
    dynamic raw,
    PushRegistrationFailureStage? failureStage,
  }) {
    return PushRegistrationResult(
      success: success ?? this.success,
      permission: permission ?? this.permission,
      token: token ?? this.token,
      message: message ?? this.message,
      raw: raw ?? this.raw,
      failureStage: failureStage ?? this.failureStage,
    );
  }

  factory PushRegistrationResult.fromResponse(
    dynamic response, {
    required String token,
  }) {
    final mapped = response is Map<String, dynamic>
        ? response
        : response is Map
        ? Map<String, dynamic>.from(response)
        : null;

    if (mapped != null) {
      final success =
          mapped['success'] == true ||
          mapped['id'] != null ||
          mapped['token'] != null ||
          mapped['deviceToken'] is Map;
      return PushRegistrationResult(
        success: success,
        permission: null,
        token: mapped['token']?.toString() ?? token,
        message: mapped['message']?.toString(),
        failureStage: success
            ? PushRegistrationFailureStage.none
            : PushRegistrationFailureStage.backend,
        raw: mapped,
      );
    }

    return PushRegistrationResult(
      success: false,
      permission: null,
      token: token,
      message: null,
      failureStage: PushRegistrationFailureStage.backend,
      raw: response,
    );
  }
}
