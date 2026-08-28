import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/apiClient.dart';

class DeviceRegistrationService {
  DeviceRegistrationService({
    ApiClient? apiClient,
    DeviceInfoPlugin? deviceInfo,
  })  : _apiClient = apiClient ?? ApiClient(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final ApiClient _apiClient;
  final DeviceInfoPlugin _deviceInfo;

  /// Backend contract:
  /// POST /client-sessions/devices
  ///
  /// Body:
  /// {
  ///   deviceId,
  ///   platform,
  ///   deviceModel,
  ///   osVersion,
  ///   appVersion,
  ///   pushToken?
  /// }
  ///
  /// Этот endpoint требует Authorization Bearer token.
  Future<DeviceRegistrationResult> registerDevice({
    String? pushToken,
  }) async {
    final deviceId = await _apiClient.getDeviceId();
    final deviceDetails = await _readDeviceDetails();
    final appVersion = await _readAppVersion();

    final body = <String, dynamic>{
      'deviceId': deviceId,
      'platform': deviceDetails.platform,
      'deviceModel': deviceDetails.deviceModel,
      'osVersion': deviceDetails.osVersion,
      'appVersion': appVersion,
      if (pushToken != null && pushToken.trim().isNotEmpty)
        'pushToken': pushToken.trim(),
    };

    final response = await _apiClient.post(
      '/client-sessions/devices',
      body,
    );

    return DeviceRegistrationResult.fromResponse(
      response,
      fallbackDeviceId: deviceId,
    );
  }

  /// Для logout позже:
  /// DELETE /client-sessions/devices/:deviceId
  Future<void> deleteCurrentDevice() async {
    final deviceId = await _apiClient.getDeviceId();

    if (deviceId.trim().isEmpty) {
      return;
    }

    await _apiClient.delete('/client-sessions/devices/$deviceId');
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
}

class DeviceDetails {
  const DeviceDetails({
    required this.platform,
    required this.deviceModel,
    required this.osVersion,
  });

  final String platform;
  final String deviceModel;
  final String osVersion;
}

class DeviceRegistrationResult {
  const DeviceRegistrationResult({
    required this.success,
    required this.deviceId,
    required this.raw,
  });

  final bool success;
  final String deviceId;
  final dynamic raw;

  factory DeviceRegistrationResult.fromResponse(
    dynamic response, {
    required String fallbackDeviceId,
  }) {
    if (response is Map<String, dynamic>) {
      return DeviceRegistrationResult(
        success: response['success'] == true,
        deviceId: response['deviceId']?.toString() ?? fallbackDeviceId,
        raw: response,
      );
    }

    if (response is Map) {
      final mapped = Map<String, dynamic>.from(response);

      return DeviceRegistrationResult(
        success: mapped['success'] == true,
        deviceId: mapped['deviceId']?.toString() ?? fallbackDeviceId,
        raw: mapped,
      );
    }

    return DeviceRegistrationResult(
      success: false,
      deviceId: fallbackDeviceId,
      raw: response,
    );
  }
}