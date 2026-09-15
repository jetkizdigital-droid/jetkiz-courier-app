import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:jetkiz_courier_app/main.dart' as app;

const String _phone = String.fromEnvironment('E2E_COURIER_PHONE');
const String _password = String.fromEnvironment('E2E_COURIER_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('courier can sign in and open all primary tabs', (tester) async {
    expect(
      _phone.trim(),
      isNotEmpty,
      reason: 'E2E_COURIER_PHONE must be supplied with --dart-define',
    );
    expect(
      _password,
      isNotEmpty,
      reason: 'E2E_COURIER_PASSWORD must be supplied with --dart-define',
    );

    await app.main();
    await tester.pump();

    final navigation = find.byKey(const Key('e2e.shell.navigation'));
    final phoneField = find.byKey(const Key('e2e.login.phone'));

    await _waitForEither(
      tester,
      first: navigation,
      second: phoneField,
      timeout: const Duration(seconds: 30),
    );

    if (navigation.evaluate().isEmpty) {
      expect(phoneField, findsOneWidget);

      await tester.enterText(phoneField, _localPhoneDigits(_phone));
      await tester.enterText(
        find.byKey(const Key('e2e.login.password')),
        _password,
      );
      await tester.tap(find.byKey(const Key('e2e.login.accept')));
      await tester.pump();

      final submit = find.byKey(const Key('e2e.login.submit'));
      expect(submit, findsOneWidget);
      await tester.tap(submit);
      await tester.pump();

      await _waitFor(
        tester,
        navigation,
        timeout: const Duration(seconds: 45),
        failureMessage:
            'Authenticated courier shell did not appear after submitting credentials.',
      );
    }

    await _verifySelectedTab(
      tester,
      navigation: navigation,
      destinationKey: 'e2e.nav.home',
      expectedIndex: 0,
    );
    await _assertCurrentTabHasNoRetryError(tester);

    await _verifySelectedTab(
      tester,
      navigation: navigation,
      destinationKey: 'e2e.nav.orders',
      expectedIndex: 1,
    );
    await _assertCurrentTabHasNoRetryError(tester);

    await _verifySelectedTab(
      tester,
      navigation: navigation,
      destinationKey: 'e2e.nav.finance',
      expectedIndex: 2,
    );
    await _assertCurrentTabHasNoRetryError(tester);

    await _verifySelectedTab(
      tester,
      navigation: navigation,
      destinationKey: 'e2e.nav.profile',
      expectedIndex: 3,
    );
    await _assertCurrentTabHasNoRetryError(tester);

    // Re-enter the auth bootstrap without clearing storage. Reaching the shell
    // again proves that the successful login persisted its session and that the
    // stored tokens are accepted by production /auth/me and /couriers/me.
    app.appNavigatorKey.currentState!.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
    await tester.pump();

    await _waitFor(
      tester,
      navigation,
      timeout: const Duration(seconds: 30),
      failureMessage:
          'Stored courier session was not restored by AuthGate after login.',
    );

    expect(
      tester.widget<NavigationBar>(navigation).selectedIndex,
      0,
      reason: 'Restored courier session should return to the main tab.',
    );
  });
}

Future<void> _verifySelectedTab(
  WidgetTester tester, {
  required Finder navigation,
  required String destinationKey,
  required int expectedIndex,
}) async {
  final destination = find.byKey(Key(destinationKey));
  expect(destination, findsOneWidget);

  await tester.tap(destination);
  await tester.pump(const Duration(milliseconds: 350));

  final bar = tester.widget<NavigationBar>(navigation);
  expect(
    bar.selectedIndex,
    expectedIndex,
    reason: 'Navigation did not switch to index $expectedIndex.',
  );

  // Give the selected screen enough time to complete its first production API
  // load without relying on pumpAndSettle, because several screens poll.
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _assertCurrentTabHasNoRetryError(WidgetTester tester) async {
  expect(
    find.text('Повторить'),
    findsNothing,
    reason: 'The selected screen displayed a production API error state.',
  );
  expect(
    find.text('Қайталау'),
    findsNothing,
    reason: 'The selected screen displayed a production API error state.',
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  required String failureMessage,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }

  expect(finder, findsOneWidget, reason: failureMessage);
}

Future<void> _waitForEither(
  WidgetTester tester, {
  required Finder first,
  required Finder second,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (first.evaluate().isEmpty &&
      second.evaluate().isEmpty &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }

  expect(
    first.evaluate().isNotEmpty || second.evaluate().isNotEmpty,
    isTrue,
    reason: 'Neither authenticated shell nor courier login screen appeared.',
  );
}

String _localPhoneDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
    digits = digits.substring(1);
  }

  if (digits.length != 10) {
    throw StateError('E2E courier phone must contain 10 local digits after +7.');
  }
  return digits;
}
