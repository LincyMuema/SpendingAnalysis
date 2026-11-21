import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small settings kept on this phone (not on the server). They survive
/// logging out, but not uninstalling the app.
class AppPrefs {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kWelcomeSeen = 'pesight_welcome_seen';
  static const _kSourcesOff = 'pesight_sms_sources_off';
  static String _smsAsked(int userId) => 'pesight_sms_setup_done_$userId';

  static Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  /// The welcome slides are shown once per phone.
  static Future<bool> welcomeSeen() async => await _read(_kWelcomeSeen) == '1';
  static Future<void> setWelcomeSeen() => _write(_kWelcomeSeen, '1');

  /// The "Allow SMS access" screen is shown once per user on each phone
  /// (as long as SMS access has not been given).
  static Future<bool> smsSetupDone(int userId) async =>
      await _read(_smsAsked(userId)) == '1';
  static Future<void> setSmsSetupDone(int userId) => _write(_smsAsked(userId), '1');

  /// Sender keys (see SmsSyncService.sources) the user chose NOT to read,
  /// e.g. a business bank account.
  static Future<Set<String>> sourcesOff() async {
    final v = await _read(_kSourcesOff);
    if (v == null || v.isEmpty) return {};
    return v.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Future<void> setSourcesOff(Set<String> keys) =>
      _write(_kSourcesOff, (keys.toList()..sort()).join(','));
}