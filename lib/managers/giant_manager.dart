import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../app_storage.dart';
import '../services/giant_service.dart';
import '../log_manager.dart';
import '../utils.dart';

/// 捷安特RideLife同步管理器
class GiantManager extends ChangeNotifier {
  static final GiantManager _instance = GiantManager._internal();
  factory GiantManager() => _instance;
  GiantManager._internal();

  final _storage = AppStorage();
  final _service = GiantService();
  final _logManager = LogManager();

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  String? _username;
  String? get username => _username;

  String? _token;

  Future<void> init() async {
    await _storage.init();

    final nickname = await _storage.read(key: 'giant_nickname');
    final account = await _storage.read(key: 'giant_username');
    _username = nickname ?? (account != null ? maskAccount(account) : null);
    _token = await _storage.read(key: 'giant_token');

    if (_token != null) {
      _service.token = _token!;
    }

    notifyListeners();
  }

  Future<void> _saveToken(String token, {String? username, String? nickname}) async {
    _token = token;
    if (username != null) {
      await _storage.write(key: 'giant_username', value: username);
    }
    if (nickname != null && nickname.isNotEmpty) {
      _username = nickname;
      await _storage.write(key: 'giant_nickname', value: nickname);
    } else if (username != null) {
      _username = maskAccount(username);
    }
    await _storage.write(key: 'giant_token', value: token);
    _service.token = token;
  }

  Future<bool> login(String username, String password) async {
    try {
      final result = await _service.login(username, password);
      if (result['success'] == true) {
        await _storage.write(key: 'giant_username', value: username);
        await _storage.write(key: 'giant_password', value: password);
        await _saveToken(result['token'], username: username, nickname: result['nickname']);

        _logManager.addLog('捷安特登录成功');
        notifyListeners();
        return true;
      }
      _logManager.addLog('捷安特登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('捷安特登录错误: $e', isError: true);
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'giant_username');
    await _storage.delete(key: 'giant_password');
    await _storage.delete(key: 'giant_token');
    await _storage.delete(key: 'giant_nickname');
    _username = null;
    _token = null;
    _service.token = null;
    _logManager.addLog('捷安特已登出');
    notifyListeners();
  }

  Future<bool> checkAndLogin() async {
    // 先检查是否有保存的凭证可以尝试登录
    final username = await _storage.read(key: 'giant_username');
    final password = await _storage.read(key: 'giant_password');

    if (username == null || password == null) {
      _logManager.addLog('捷安特无保存的凭证', isError: true);
      return false;
    }

    // 每次都重新登录以确保 token 有效
    _logManager.addLog('捷安特自动登录中...');
    final loginResult = await _service.login(username, password);
    if (loginResult['success'] == true) {
      await _saveToken(loginResult['token'], username: username, nickname: loginResult['nickname']);
      return true;
    }

    _logManager.addLog('捷安特自动登录失败: ${loginResult['message']}', isError: true);
    return false;
  }

  // 上传FIT文件
  Future<String> uploadFitFile(Uint8List fitBytes, String fileName) async {
    if (!await checkAndLogin()) {
      throw Exception('捷安特未登录');
    }

    _isUploading = true;
    notifyListeners();

    try {
      _logManager.addLog('上传到捷安特: $fileName');
      final result = await _service.uploadFit(fitBytes, fileName);
      _logManager.addLog('捷安特上传成功: $result');
      return result;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  bool get isLoggedIn => _service.isLoggedIn;
}
