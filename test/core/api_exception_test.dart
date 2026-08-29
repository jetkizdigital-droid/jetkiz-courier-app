import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';

void main() {
  test('403 forbidden does not invalidate authenticated courier session', () {
    const error = ApiException(
      kind: ApiErrorKind.forbidden,
      method: 'GET',
      path: '/protected-action',
      message: 'Forbidden',
      statusCode: 403,
    );

    expect(error.isAuthenticationFailure, isFalse);
  });

  test('401 unauthorized still invalidates authenticated courier session', () {
    const error = ApiException(
      kind: ApiErrorKind.unauthorized,
      method: 'GET',
      path: '/auth/me',
      message: 'Unauthorized',
      statusCode: 401,
    );

    expect(error.isAuthenticationFailure, isTrue);
  });
}
