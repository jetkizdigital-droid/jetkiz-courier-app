import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';

void main() {
  test('notification-device register envelope is treated as success', () {
    final result = PushRegistrationResult.fromResponse({
      'success': true,
      'deviceToken': {'id': 'push-device-1', 'isActive': true},
    }, token: 'test-token-value');

    expect(result.success, isTrue);
    expect(result.token, 'test-token-value');
    expect(result.failureStage, PushRegistrationFailureStage.none);
  });

  test('deviceToken envelope alone is treated as success', () {
    final result = PushRegistrationResult.fromResponse({
      'deviceToken': {'id': 'push-device-1', 'isActive': true},
    }, token: 'test-token-value');

    expect(result.success, isTrue);
    expect(result.failureStage, PushRegistrationFailureStage.none);
  });
}
