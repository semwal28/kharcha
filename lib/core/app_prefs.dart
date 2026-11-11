import 'package:shared_preferences/shared_preferences.dart';

/// Small on/off settings saved on this device. Safe to use before [init]
/// (and in tests): reads fall back to the default, writes are skipped.
abstract final class AppPrefs {
  static SharedPreferences? _p;

  static const guest = 'spendwell.guest';
  static const appLock = 'spendwell.app_lock';
  static const recurringAdded = 'spendwell.recurring_added';

  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null;
    }
  }

  static bool getBool(String key) => _p?.getBool(key) ?? false;
  static Future<void> setBool(String key, bool value) async => _p?.setBool(key, value);

  static List<String> getList(String key) => _p?.getStringList(key) ?? const [];
  static Future<void> setList(String key, List<String> value) async => _p?.setStringList(key, value);
}
