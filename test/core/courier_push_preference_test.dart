import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/core/push/courier_push_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('courier push is enabled by default', () async {
    expect(await CourierPushPreference.isEnabled(), isTrue);
  });

  test('courier push preference persists independently', () async {
    await CourierPushPreference.setEnabled(false);
    expect(await CourierPushPreference.isEnabled(), isFalse);
    await CourierPushPreference.setEnabled(true);
    expect(await CourierPushPreference.isEnabled(), isTrue);
  });

  test(
    'courier push flow no longer depends on client settings pushEnabled',
    () {
      final auth = File(
        'lib/features/auth/presentation/auth_gate.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/features/navigation/presentation/courier_shell.dart',
      ).readAsStringSync();
      final profile = File(
        'lib/features/profile/presentation/courier_profile_page.dart',
      ).readAsStringSync();

      expect(auth, isNot(contains("get('/client-settings/me')")));
      expect(shell, isNot(contains("get('/client-settings/me')")));
      expect(
        profile,
        isNot(contains("patch('/client-settings/me', {'pushEnabled'")),
      );
    },
  );
}
