import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';

class CourierLocationService {
  CourierLocationService({
    ApiClient? apiClient,
  }) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Timer? _heartbeatTimer;
  bool _isSending = false;
  bool _isTracking = false;

  static const Duration heartbeatInterval = Duration(seconds: 20);

  bool get isTracking => _isTracking;

  /// Проверяет GPS + permission.
  /// Возвращает result, чтобы экран мог показать нормальное сообщение.
  Future<CourierLocationPermissionResult> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return const CourierLocationPermissionResult(
        allowed: false,
        reason: CourierLocationPermissionDeniedReason.serviceDisabled,
        message: 'Геолокация выключена. Включите GPS на устройстве.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const CourierLocationPermissionResult(
        allowed: false,
        reason: CourierLocationPermissionDeniedReason.permissionDenied,
        message: 'Разрешите доступ к геолокации, чтобы выходить на линию.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      return const CourierLocationPermissionResult(
        allowed: false,
        reason: CourierLocationPermissionDeniedReason.permissionDeniedForever,
        message:
            'Геолокация запрещена навсегда. Откройте настройки приложения и разрешите доступ.',
      );
    }

    return CourierLocationPermissionResult(
      allowed: true,
      reason: null,
      message: 'Геолокация разрешена',
      permission: permission.name,
    );
  }

  /// Получает текущую позицию.
  Future<Position> getCurrentPosition() async {
    final permission = await ensurePermission();

    if (!permission.allowed) {
      throw CourierLocationException(permission.message);
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      return Geolocator.getLastKnownPosition().then((lastKnown) {
        if (lastKnown != null) {
          return lastKnown;
        }

        throw CourierLocationException(
          'Не удалось получить геолокацию. Попробуйте ещё раз.',
        );
      });
    } catch (e) {
      throw CourierLocationException(
        'Не удалось получить геолокацию: $e',
      );
    }
  }

  /// Одноразово отправляет координаты на backend.
  Future<CourierLocationSendResult> sendCurrentLocation({
    String source = 'manual',
  }) async {
    if (_isSending) {
      return const CourierLocationSendResult(
        success: false,
        skipped: true,
        message: 'Отправка координат уже выполняется',
      );
    }

    _isSending = true;

    try {
      final position = await getCurrentPosition();

      final body = <String, dynamic>{
        'lat': position.latitude,
        'lng': position.longitude,
      };

      final response = await _apiClient.post(
        '/couriers/me/location',
        body,
      );

      return CourierLocationSendResult(
        success: true,
        skipped: false,
        message: 'Координаты отправлены',
        lat: position.latitude,
        lng: position.longitude,
        raw: response,
      );
    } catch (e) {
      return CourierLocationSendResult(
        success: false,
        skipped: false,
        message: e.toString(),
      );
    } finally {
      _isSending = false;
    }
  }

  /// Запускает периодическую отправку координат.
  /// Используем, когда курьер online.
  Future<CourierLocationStartResult> startTracking({
    Duration interval = heartbeatInterval,
  }) async {
    final permission = await ensurePermission();

    if (!permission.allowed) {
      return CourierLocationStartResult(
        started: false,
        message: permission.message,
        permission: permission,
      );
    }

    await stopTracking();

    _isTracking = true;

    final firstSend = await sendCurrentLocation(source: 'online_start');

    _heartbeatTimer = Timer.periodic(interval, (_) {
      unawaited(sendCurrentLocation(source: 'heartbeat'));
    });

    return CourierLocationStartResult(
      started: true,
      message: firstSend.success
          ? 'Отправка геолокации запущена'
          : firstSend.message,
      permission: permission,
      firstSend: firstSend,
    );
  }

  /// Останавливает периодическую отправку координат.
  Future<void> stopTracking() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isTracking = false;
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> dispose() async {
    await stopTracking();
    _apiClient.dispose();
  }
}

class CourierLocationPermissionResult {
  const CourierLocationPermissionResult({
    required this.allowed,
    required this.reason,
    required this.message,
    this.permission,
  });

  final bool allowed;
  final CourierLocationPermissionDeniedReason? reason;
  final String message;
  final String? permission;
}

enum CourierLocationPermissionDeniedReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class CourierLocationStartResult {
  const CourierLocationStartResult({
    required this.started,
    required this.message,
    required this.permission,
    this.firstSend,
  });

  final bool started;
  final String message;
  final CourierLocationPermissionResult permission;
  final CourierLocationSendResult? firstSend;
}

class CourierLocationSendResult {
  const CourierLocationSendResult({
    required this.success,
    required this.skipped,
    required this.message,
    this.lat,
    this.lng,
    this.raw,
  });

  final bool success;
  final bool skipped;
  final String message;
  final double? lat;
  final double? lng;
  final dynamic raw;
}

class CourierLocationException implements Exception {
  CourierLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}