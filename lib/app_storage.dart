import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static final AppStorage _instance = AppStorage._internal();
  factory AppStorage() => _instance;
  AppStorage._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  // 初始化 SharedPreferences
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // === 安全存储（凭证、token） ===

  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read({required String key}) async {
    return await _storage.read(key: key);
  }

  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
  }

  Future<bool> containsKey({required String key}) async {
    return await _storage.containsKey(key: key);
  }

  Future<Map<String, String>> readAll() async {
    return await _storage.readAll();
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  // === 偏好设置（非敏感数据：开关、配置） ===

  Future<void> writePrefs({required String key, required String value}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(key, value);
  }

  Future<String?> readPrefs({required String key}) async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getString(key);
  }

  Future<void> deletePrefs({required String key}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(key);
  }

  Future<bool> containsPrefs({required String key}) async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.containsKey(key);
  }

  // 便捷方法：读取布尔设置
  Future<bool> readBoolPrefs({required String key, bool defaultValue = false}) async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getBool(key) ?? defaultValue;
  }

  Future<void> writeBoolPrefs({required String key, required bool value}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(key, value);
  }

  // 便捷方法：读取整数设置
  Future<int> readIntPrefs({required String key, int defaultValue = 0}) async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getInt(key) ?? defaultValue;
  }

  Future<void> writeIntPrefs({required String key, required int value}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(key, value);
  }
}
