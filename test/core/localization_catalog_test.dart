import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every literal localization key used by lib has RU and KK values', () async {
    final keys = <String>{};
    final keyPattern = RegExp(
      r'''(?:\.t|\.format)\(\s*['"]([a-zA-Z0-9_.-]+)['"]''',
      multiLine: true,
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in keyPattern.allMatches(source)) {
        final key = match.group(1);
        if (key != null && key.contains('.')) keys.add(key);
      }
    }

    expect(keys, isNotEmpty, reason: 'No localization keys were discovered');

    final locale = CourierLocaleController.instance;
    final missingRu = <String>[];
    final missingKk = <String>[];

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await locale.selectBeforeLogin('ru');
    for (final key in keys) {
      if (locale.t(key) == key) missingRu.add(key);
    }

    await locale.selectBeforeLogin('kk');
    for (final key in keys) {
      if (locale.t(key) == key) missingKk.add(key);
    }

    missingRu.sort();
    missingKk.sort();

    expect(
      missingRu,
      isEmpty,
      reason: 'Missing Russian localization keys: ${missingRu.join(', ')}',
    );
    expect(
      missingKk,
      isEmpty,
      reason: 'Missing Kazakh localization keys: ${missingKk.join(', ')}',
    );
  });
}
