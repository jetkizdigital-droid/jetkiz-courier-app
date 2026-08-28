import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/login_page.dart';

void main() {
  testWidgets('courier login uses phone and password without OTP', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginPage()),
    );

    expect(find.text('Вход для курьера'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Пользовательское соглашение'), findsOneWidget);

    expect(find.textContaining('Введите код'), findsNothing);
    expect(find.textContaining('Отправить код'), findsNothing);
  });
}
