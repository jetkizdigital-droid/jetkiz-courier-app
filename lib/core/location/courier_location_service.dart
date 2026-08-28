import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';

class CourierLocationService {
  factory CourierLocationService() => _instance;

  CourierLocationService._(this._apiClient);

  static final CourierLocationService _instance =
      CourierLocationService._(ApiClient());

  final ApiClient _apiClient;

  StreamSubscription<Position>? _positionSubscription;
  bool _isSending = false;
  bool _isTracking = false;
  Position? _queuedPosition;

  static const Duration heartbeatInterval = Duration(seconds: 20);

  bool get isTracking => _isTracking;

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
      final lastKnown = await Geolocator.getLastKnownPosition();

      if (lastKnown != null) return lastKnown;

      throw CourierLocationException(
        'Не удалось получить геолокацию. Попробуйте ещё раз.',
      );
    } catch (e) {
      if (e is CourierLocationException) rethrow;
      throw CourierLocationException('Не удалось получить геолокацию: $e');
    }
  }

  Future<CourierLocationSendResult> sendCurrentLocation({
    String source = 'manual',
  }) async {
    try {
      return _sendPosition(
        await getCurrentPosition(),
        source: source,
      );
    } catch (e) {
      return CourierLocationSendResult(
        success: false,
        skipped: false,
        message: e.toString(),
      );
    }
  }

  Future<CourierLocationSendResult> _sendPosition(
    Position position, {
    required String source,
  }) async {
    if (_isSending) {
      _queuedPosition = position;
      return const CourierLocationSendResult(
        success: false,
        skipped: true,
        message: 'Предыдущая отправка координат ещё выполняется',
      );
    }

    _isSending = true;

    try {
      final response = await _apiClient.post(
        '/couriers/me/location',
        <String, dynamic>{
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          if (position.heading.isFinite && position.heading >= 0)
            'heading': position.heading,
          if (position.speed.isFinite && position.speed >= 0)
            'speed': position.speed,
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
        },
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

      final queued = _queuedPosition;
      _queuedPosition = null;

      if (queued != null && _isTracking) {
        unawaited(_sendPosition(queued, source: 'queued'));
      }
    }
  }

  Future<CourierLocationStartResult> startTracking({
    Duration interval = heartbeatInterval,
  }) async {
    if (_isTracking && _positionSubscription != null) {
      final permission = await ensurePermission();
      return CourierLocationStartResult(
        started: permission.allowed,
        message: permission.allowed
            ? 'Геолокация уже активна'
            : permission.message,
        permission: permission,
      );
    }

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

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _buildTrackingSettings(interval),
    ).listen(
      (position) {
        if (!_isTracking) return;
        unawaited(_sendPosition(position, source: 'stream'));
      },
      onError: (_) {
        // A transient GPS error must not tear down the courier shift.
      },
      cancelOnError: false,
    );

    return CourierLocationStartResult(
      started: true,
      message: firstSend.success
          ? 'Отправка геолокации запущена'
          : 'Трекинг запущен, ожидаем следующую GPS-точку',
      permission: permission,
      firstSend: firstSend,
    );
  }

  LocationSettings _buildTrackingSettings(Duration interval) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'JETKIZ — вы на линии',
          notificationText:
              'Геопозиция используется для назначения и выполнения доставки.',
          enableWakeLock: true,
        ),
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    _queuedPosition = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  /// Screen lifecycle must never stop courier tracking. The service is scoped
  /// to the authenticated application session. Use [stopTracking] only when
  /// the courier explicitly goes offline or logs out.
  Future<void> dispose() async {}

  Future<void> shutdown() async {
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
