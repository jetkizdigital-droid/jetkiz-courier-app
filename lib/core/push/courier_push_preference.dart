import 'package:shared_preferences/shared_preferences.dart';

/// Courier notification intent is app-specific and must not reuse the
/// client application's pushEnabled server setting.
class CourierPushPreference {
  static const String _key = 'jetkiz.courier.pushEnabled';

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, value);
  }
}
