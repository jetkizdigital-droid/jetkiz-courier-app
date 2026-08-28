import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/core/formatters/kazakhstan_phone.dart';

void main() {
  group('normalizeKazakhstanPhone', () {
    test('accepts local 10 digit number', () {
      expect(normalizeKazakhstanPhone('7001234567'), '+77001234567');
    });

    test('accepts pasted +7 number', () {
      expect(
        normalizeKazakhstanPhone('+7 (700) 123-45-67'),
        '+77001234567',
      );
    });

    test('converts legacy 8 prefix', () {
      expect(normalizeKazakhstanPhone('8 700 123 45 67'), '+77001234567');
    });

    test('rejects invalid length', () {
      expect(normalizeKazakhstanPhone('700123'), isNull);
    });
  });

  test('formatKazakhstanPhoneInput handles pasted country prefix', () {
    expect(
      formatKazakhstanPhoneInput('+7 700 123 45 67'),
      '(700) 123-45-67',
    );
  });
}
