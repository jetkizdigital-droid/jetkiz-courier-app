import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class TwoGisLauncher {
  const TwoGisLauncher._();

  static Future<void> openRoute({
    required String destinationAddress,
    String? originAddress,
  }) async {
    final destination = destinationAddress.trim();

    if (destination.isEmpty) {
      throw TwoGisLauncherException('destinationAddress is empty');
    }

    final origin = (originAddress ?? '').trim();

    final candidates = <Uri>[
      if (Platform.isAndroid || Platform.isIOS) _buildGeoUri(destination),
      _buildTwoGisSearchUri(destination),
      _buildGoogleMapsSearchUri(destination),
      if (origin.isNotEmpty) _buildGoogleMapsDirectionsUri(origin, destination),
    ];

    for (final uri in candidates) {
      final opened = await _tryLaunch(uri);

      if (opened) {
        return;
      }
    }

    throw TwoGisLauncherException('Could not open maps app');
  }

  static Future<void> openSearch({
    required String query,
  }) async {
    final normalized = query.trim();

    if (normalized.isEmpty) {
      throw TwoGisLauncherException('query is empty');
    }

    final candidates = <Uri>[
      if (Platform.isAndroid || Platform.isIOS) _buildGeoUri(normalized),
      _buildTwoGisSearchUri(normalized),
      _buildGoogleMapsSearchUri(normalized),
    ];

    for (final uri in candidates) {
      final opened = await _tryLaunch(uri);

      if (opened) {
        return;
      }
    }

    throw TwoGisLauncherException('Could not open maps app');
  }

  static Future<void> openByCoordinates({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final normalizedLabel = (label ?? 'Пункт назначения').trim();

    final candidates = <Uri>[
      Uri.parse(
        'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(normalizedLabel)})',
      ),
      Uri.parse(
        'https://2gis.kz/geo/$lng,$lat',
      ),
      Uri.https(
        'www.google.com',
        '/maps/search/',
        {
          'api': '1',
          'query': '$lat,$lng',
        },
      ),
    ];

    for (final uri in candidates) {
      final opened = await _tryLaunch(uri);

      if (opened) {
        return;
      }
    }

    throw TwoGisLauncherException('Could not open maps app');
  }

  static Uri _buildGeoUri(String query) {
    return Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}');
  }

  static Uri _buildTwoGisSearchUri(String query) {
    return Uri.parse(
      'https://2gis.kz/search/${Uri.encodeComponent(query)}',
    );
  }

  static Uri _buildGoogleMapsSearchUri(String query) {
    return Uri.https(
      'www.google.com',
      '/maps/search/',
      {
        'api': '1',
        'query': query,
      },
    );
  }

  static Uri _buildGoogleMapsDirectionsUri(
    String origin,
    String destination,
  ) {
    return Uri.https(
      'www.google.com',
      '/maps/dir/',
      {
        'api': '1',
        'origin': origin,
        'destination': destination,
        'travelmode': 'driving',
      },
    );
  }

  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

class TwoGisLauncherException implements Exception {
  const TwoGisLauncherException(this.message);

  final String message;

  @override
  String toString() => message;
}
