import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../storage/token_storage.dart';

class ApiClient {
  ApiClient({http.Client? client, TokenStorage? tokenStorage})
    : _client = client ?? http.Client(),
      _tokenStorage = tokenStorage ?? TokenStorage();

  static const String productionBaseUrl = 'https://api.jetkiz.asia';
  static const String localDebugBaseUrl = 'http://127.0.0.1:3000';
  static const String _definedBaseUrl = String.fromEnvironment(
    'JETKIZ_API_BASE_URL',
    defaultValue: '',
  );
  static const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');
  static const Duration _timeout = Duration(seconds: 15);
  static const String _app = 'courier';
  static const String _locale = 'ru';
  static const String _timezone = 'Asia/Almaty';
  static const String _deviceIdKey = 'jetkiz_device_id';

  static final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();
  static Future<_RefreshResult>? _refreshInFlight;

  static Stream<void> get sessionExpired => _sessionExpiredController.stream;

  static String get baseUrl {
    final configured = _definedBaseUrl.trim();
    final resolved = configured.isNotEmpty
        ? configured
        : (_isReleaseBuild ? productionBaseUrl : localDebugBaseUrl);
    final normalized = resolved.endsWith('/')
        ? resolved.substring(0, resolved.length - 1)
        : resolved;

    if (_isReleaseBuild) {
      final uri = Uri.tryParse(normalized);
      final host = (uri?.host ?? '').trim().toLowerCase();
      final unsafeHost = host.isEmpty ||
          host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '0.0.0.0' ||
          host == '10.0.2.2' ||
          host.endsWith('.local');

      if (uri?.scheme.toLowerCase() != 'https' || unsafeHost) {
        throw StateError(
          'Unsafe JETKIZ_API_BASE_URL for release build: $normalized',
        );
      }
    }

    return normalized;
  }

  final http.Client _client;
  final TokenStorage _tokenStorage;
  final Uuid _uuid = const Uuid();

  Future<dynamic> get(String path) async {
    return _handleResponse(await _send(method: 'GET', path: path));
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    return _handleResponse(
      await _send(method: 'POST', path: path, body: body),
    );
  }

  Future<dynamic> postPublic(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    return _handleResponse(
      await _sendPublic(method: 'POST', path: path, body: body),
    );
  }

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async {
    // Compatibility bridge: older screens used this route. Never call the
    // legacy backend presence implementation because it could make stale GPS
    // coordinates appear fresh by touching lastSeenAt without a GPS fix.
    if (path == '/couriers/me/online') {
      return post('/couriers/me/online-status', {
        'isOnline': body?['isOnline'] == true,
      });
    }

    return _handleResponse(
      await _send(method: 'PATCH', path: path, body: body),
    );
  }

  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) async {
    return _handleResponse(
      await _send(method: 'DELETE', path: path, body: body),
    );
  }

  Future<dynamic> postMultipart(
    String path, {
    required String fieldName,
    required String filePath,
  }) async {
    return _handleResponse(
      await _sendMultipart(
        path: path,
        fieldName: fieldName,
        filePath: filePath,
      ),
    );
  }

  Future<String> getDeviceId() => _getDeviceId();

  Future<http.Response> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    bool retryAfterRefresh = true,
    int staleTokenRetries = 2,
  }) async {
    final accessTokenUsed = await _tokenStorage.getAccessToken();
    final response = await _performJsonRequest(
      method: method,
      path: path,
      uri: Uri.parse('$baseUrl$path'),
      headers: await _buildHeaders(
        includeAuth: true,
        accessToken: accessTokenUsed,
      ),
      body: body,
    );

    if (response.statusCode != 401) return response;

    final latestAccessToken = await _tokenStorage.getAccessToken();
    if (
      staleTokenRetries > 0 &&
      _hasAccessTokenChanged(accessTokenUsed, latestAccessToken)
    ) {
      // Another request refreshed the shared session while this request was in
      // flight. Retry with the token already stored instead of rotating the
      // refresh token a second time.
      return _send(
        method: method,
        path: path,
        body: body,
        retryAfterRefresh: false,
        staleTokenRetries: staleTokenRetries - 1,
      );
    }

    if (!retryAfterRefresh) {
      await _expireLocalSession(method: method, path: path);
    }

    final refreshResult = await _refreshTokenOnce();

    if (refreshResult.isSuccess) {
      return _send(
        method: method,
        path: path,
        body: body,
        retryAfterRefresh: false,
        staleTokenRetries: 2,
      );
    }

    if (refreshResult.isInvalidSession) {
      await _expireLocalSession(method: method, path: path);
    }

    throw refreshResult.error ??
        ApiException.server(
          method: 'POST',
          path: '/auth/refresh',
          message: 'Token refresh failed temporarily',
        );
  }

  Future<http.Response> _sendPublic({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) {
    return _performJsonRequest(
      method: method,
      path: path,
      uri: Uri.parse('$baseUrl$path'),
      headersFuture: _buildHeaders(includeAuth: false),
      body: body,
    );
  }

  Future<http.Response> _performJsonRequest({
    required String method,
    required String path,
    required Uri uri,
    Map<String, String>? headers,
    Future<Map<String, String>>? headersFuture,
    Map<String, dynamic>? body,
  }) async {
    final resolvedHeaders = headers ?? await headersFuture!;

    try {
      switch (method) {
        case 'GET':
          return await _client.get(uri, headers: resolvedHeaders).timeout(_timeout);
        case 'POST':
          return await _client
              .post(
                uri,
                headers: resolvedHeaders,
                body: jsonEncode(body ?? <String, dynamic>{}),
              )
              .timeout(_timeout);
        case 'PATCH':
          return await _client
              .patch(
                uri,
                headers: resolvedHeaders,
                body: jsonEncode(body ?? <String, dynamic>{}),
              )
              .timeout(_timeout);
        case 'DELETE':
          return await _client
              .delete(
                uri,
                headers: resolvedHeaders,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(_timeout);
        default:
          throw ApiException.request(
            method: method,
            path: path,
            message: 'Unsupported method: $method',
          );
      }
    } on TimeoutException {
      throw ApiException.timeout(method: method, path: path);
    } on SocketException catch (e) {
      throw ApiException.network(method: method, path: path, message: e.message);
    } on http.ClientException catch (e) {
      throw ApiException.network(method: method, path: path, message: e.message);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.request(
        method: method,
        path: path,
        message: e.toString(),
      );
    }
  }

  Future<http.Response> _sendMultipart({
    required String path,
    required String fieldName,
    required String filePath,
    bool retryAfterRefresh = true,
    int staleTokenRetries = 2,
  }) async {
    final accessTokenUsed = await _tokenStorage.getAccessToken();
    final headers = await _buildHeaders(
      includeAuth: true,
      accessToken: accessTokenUsed,
    );
    headers.remove('Content-Type');

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));

      final response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );

      if (response.statusCode != 401) return response;

      final latestAccessToken = await _tokenStorage.getAccessToken();
      if (
        staleTokenRetries > 0 &&
        _hasAccessTokenChanged(accessTokenUsed, latestAccessToken)
      ) {
        return _sendMultipart(
          path: path,
          fieldName: fieldName,
          filePath: filePath,
          retryAfterRefresh: false,
          staleTokenRetries: staleTokenRetries - 1,
        );
      }

      if (!retryAfterRefresh) {
        await _expireLocalSession(method: 'POST', path: path);
      }

      final refreshResult = await _refreshTokenOnce();

      if (refreshResult.isSuccess) {
        return _sendMultipart(
          path: path,
          fieldName: fieldName,
          filePath: filePath,
          retryAfterRefresh: false,
          staleTokenRetries: 2,
        );
      }

      if (refreshResult.isInvalidSession) {
        await _expireLocalSession(method: 'POST', path: path);
      }

      throw refreshResult.error ??
          ApiException.server(
            method: 'POST',
            path: '/auth/refresh',
            message: 'Token refresh failed temporarily',
          );
    } on TimeoutException {
      throw ApiException.timeout(method: 'POST', path: path);
    } on SocketException catch (e) {
      throw ApiException.network(method: 'POST', path: path, message: e.message);
    } on http.ClientException catch (e) {
      throw ApiException.network(method: 'POST', path: path, message: e.message);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException.request(
        method: 'POST',
        path: path,
        message: e.toString(),
      );
    }
  }

  Future<Never> _expireLocalSession({
    required String method,
    required String path,
  }) async {
    await _tokenStorage.clear();
    _sessionExpiredController.add(null);
    throw ApiException.sessionExpired(method: method, path: path);
  }

  bool _hasAccessTokenChanged(String? usedToken, String? latestToken) {
    final used = usedToken?.trim() ?? '';
    final latest = latestToken?.trim() ?? '';
    return latest.isNotEmpty && latest != used;
  }

  Future<Map<String, String>> _buildHeaders({
    required bool includeAuth,
    String? accessToken,
  }) async {
    final resolvedAccessToken = includeAuth
        ? accessToken ?? await _tokenStorage.getAccessToken()
        : null;
    final deviceId = await _getDeviceId();
    final appVersion = await _getAppVersion();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Request-Id': _buildRequestId(),
      'X-App': _app,
      'X-Platform': _platform(),
      'X-App-Version': appVersion,
      'X-Device-Id': deviceId,
      'X-Locale': _locale,
      'X-Timezone': _timezone,
      'User-Agent': 'JetkizCourier/$appVersion',
    };

    if (resolvedAccessToken != null && resolvedAccessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $resolvedAccessToken';
    }

    return headers;
  }

  Future<_RefreshResult> _refreshTokenOnce() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final future = _tryRefreshToken();
    _refreshInFlight = future;

    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<_RefreshResult> _tryRefreshToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return const _RefreshResult.invalidSession();
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: await _buildHeaders(includeAuth: false),
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(_timeout);

      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        return const _RefreshResult.invalidSession();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _RefreshResult.transientFailure(
          ApiException.fromResponse(
            method: 'POST',
            path: '/auth/refresh',
            response: response,
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _RefreshResult.transientFailure(
          ApiException.invalidResponse(method: 'POST', path: '/auth/refresh'),
        );
      }

      final accessToken = decoded['accessToken']?.toString().trim() ?? '';
      final newRefreshToken =
          decoded['refreshToken']?.toString().trim() ?? refreshToken;

      if (accessToken.isEmpty || newRefreshToken.isEmpty) {
        return _RefreshResult.transientFailure(
          ApiException.invalidResponse(method: 'POST', path: '/auth/refresh'),
        );
      }

      await _tokenStorage.saveTokens(accessToken, newRefreshToken);
      return const _RefreshResult.success();
    } on TimeoutException {
      return _RefreshResult.transientFailure(
        ApiException.timeout(method: 'POST', path: '/auth/refresh'),
      );
    } on SocketException catch (e) {
      return _RefreshResult.transientFailure(
        ApiException.network(
          method: 'POST',
          path: '/auth/refresh',
          message: e.message,
        ),
      );
    } on http.ClientException catch (e) {
      return _RefreshResult.transientFailure(
        ApiException.network(
          method: 'POST',
          path: '/auth/refresh',
          message: e.message,
        ),
      );
    } catch (e) {
      return _RefreshResult.transientFailure(
        ApiException.request(
          method: 'POST',
          path: '/auth/refresh',
          message: e.toString(),
        ),
      );
    }
  }

  dynamic _handleResponse(http.Response response) {
    final body = response.body.trim();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(
        method: response.request?.method ?? 'HTTP',
        path: response.request?.url.path ?? '',
        response: response,
      );
    }

    if (body.isEmpty) return null;

    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;

    final generated = 'jetkiz-courier-${_uuid.v4()}';
    await prefs.setString(_deviceIdKey, generated);
    return generated;
  }

  Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty && build.isEmpty) return '1.0.0';
      if (build.isEmpty) return version;
      return '$version+$build';
    } catch (_) {
      return '1.0.0';
    }
  }

  String _buildRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = _uuid.v4().replaceAll('-', '').substring(0, 16);
    return 'req-$now-$random';
  }

  String _platform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  void dispose() => _client.close();
}

enum ApiErrorKind {
  network,
  timeout,
  server,
  unauthorized,
  forbidden,
  sessionExpired,
  invalidResponse,
  request,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.method,
    required this.path,
    required this.message,
    this.statusCode,
  });

  final ApiErrorKind kind;
  final String method;
  final String path;
  final String message;
  final int? statusCode;

  bool get isAuthenticationFailure =>
      kind == ApiErrorKind.unauthorized ||
      kind == ApiErrorKind.forbidden ||
      kind == ApiErrorKind.sessionExpired;

  bool get isTransient =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server ||
      kind == ApiErrorKind.invalidResponse ||
      kind == ApiErrorKind.request;

  factory ApiException.fromResponse({
    required String method,
    required String path,
    required http.Response response,
  }) {
    final status = response.statusCode;
    final body = response.body.trim();
    final kind = status == 401
        ? ApiErrorKind.unauthorized
        : status == 403
        ? ApiErrorKind.forbidden
        : status >= 500
        ? ApiErrorKind.server
        : ApiErrorKind.request;

    return ApiException(
      kind: kind,
      method: method,
      path: path,
      statusCode: status,
      message: 'HTTP $status: ${body.isEmpty ? '<empty body>' : body}',
    );
  }

  factory ApiException.network({
    required String method,
    required String path,
    required String message,
  }) => ApiException(
    kind: ApiErrorKind.network,
    method: method,
    path: path,
    message: 'Network error: $message',
  );

  factory ApiException.timeout({required String method, required String path}) =>
      ApiException(
        kind: ApiErrorKind.timeout,
        method: method,
        path: path,
        message: 'Request timeout: $method $path',
      );

  factory ApiException.server({
    required String method,
    required String path,
    required String message,
  }) => ApiException(
    kind: ApiErrorKind.server,
    method: method,
    path: path,
    message: message,
  );

  factory ApiException.sessionExpired({
    required String method,
    required String path,
  }) => ApiException(
    kind: ApiErrorKind.sessionExpired,
    method: method,
    path: path,
    statusCode: 401,
    message: 'Session expired',
  );

  factory ApiException.invalidResponse({
    required String method,
    required String path,
  }) => ApiException(
    kind: ApiErrorKind.invalidResponse,
    method: method,
    path: path,
    message: 'Server returned an invalid response',
  );

  factory ApiException.request({
    required String method,
    required String path,
    required String message,
  }) => ApiException(
    kind: ApiErrorKind.request,
    method: method,
    path: path,
    message: message,
  );

  @override
  String toString() => message;
}

class _RefreshResult {
  const _RefreshResult._({
    required this.isSuccess,
    required this.isInvalidSession,
    this.error,
  });

  const _RefreshResult.success()
    : this._(isSuccess: true, isInvalidSession: false);
  const _RefreshResult.invalidSession()
    : this._(isSuccess: false, isInvalidSession: true);
  const _RefreshResult.transientFailure(ApiException error)
    : this._(isSuccess: false, isInvalidSession: false, error: error);

  final bool isSuccess;
  final bool isInvalidSession;
  final ApiException? error;
}
