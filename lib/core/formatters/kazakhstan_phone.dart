String? normalizeKazakhstanPhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');

  if (digits.length == 11 && digits.startsWith('8')) {
    digits = '7${digits.substring(1)}';
  }

  if (digits.length == 10) {
    digits = '7$digits';
  }

  if (digits.length != 11 || !digits.startsWith('7')) {
    return null;
  }

  return '+$digits';
}

String formatKazakhstanPhoneInput(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');

  if (digits.length == 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
    digits = digits.substring(1);
  }

  if (digits.length > 10) {
    digits = digits.substring(0, 10);
  }

  if (digits.isEmpty) return '';

  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i == 0) buffer.write('(');
    if (i == 3) buffer.write(') ');
    if (i == 6 || i == 8) buffer.write('-');
    buffer.write(digits[i]);
  }

  return buffer.toString();
}
