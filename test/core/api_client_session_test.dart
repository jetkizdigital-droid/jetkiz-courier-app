import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokenStorage extends TokenStorage {
  _MemoryTokenStorage(this.accessToken, this.refreshToken);

  String? accessToken;
  String? refreshToken;
  int clearCount = 0;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    this.refreshToken = refreshToken;
    this.accessToken = accessToken;
  }

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> clear() async {
    clearCount += 1;
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> hasSession() async =>
      (accessToken?.isNotEmpty ?? false) && (refreshToken?.isNotEmpty ?? false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'a protected 401 after successful refresh never clears new tokens',
    () async {
      final storage = _MemoryTokenStorage('access-old', 'refresh-old');
      var protectedCalls = 0;
      var refreshCalls = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls += 1;
          return http.Response(
            '{"accessToken":"access-new","refreshToken":"refresh-new"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/protected') {
          protectedCalls += 1;
          return http.Response('unauthorized', 401);
        }

        return http.Response('not found', 404);
      });

      final api = ApiClient(client: client, tokenStorage: storage);
      addTearDown(api.dispose);

      await expectLater(
        api.get('/protected'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.kind, 'kind', ApiErrorKind.unauthorized)
              .having((error) => error.statusCode, 'statusCode', 401),
        ),
      );

      expect(refreshCalls, 1);
      expect(protectedCalls, 2);
      expect(storage.accessToken, 'access-new');
      expect(storage.refreshToken, 'refresh-new');
      expect(storage.clearCount, 0);
    },
  );

  test(
    'stale refresh rejection accepts tokens rotated by another request',
    () async {
      final storage = _MemoryTokenStorage('access-old', 'refresh-old');
      var protectedCalls = 0;
      var refreshCalls = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls += 1;
          await storage.saveTokens('access-new', 'refresh-new');
          return http.Response('stale refresh token', 401);
        }

        if (request.url.path == '/protected') {
          protectedCalls += 1;
          final authorization = request.headers['Authorization'];
          if (authorization == 'Bearer access-new') {
            return http.Response('{"ok":true}', 200);
          }
          return http.Response('expired access', 401);
        }

        return http.Response('not found', 404);
      });

      final api = ApiClient(client: client, tokenStorage: storage);
      addTearDown(api.dispose);

      final response = await api.get('/protected');

      expect(response, {'ok': true});
      expect(refreshCalls, 1);
      expect(protectedCalls, 2);
      expect(storage.accessToken, 'access-new');
      expect(storage.refreshToken, 'refresh-new');
      expect(storage.clearCount, 0);
    },
  );
}
