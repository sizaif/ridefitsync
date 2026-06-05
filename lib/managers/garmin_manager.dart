import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../app_storage.dart';
import '../services/garmin_service.dart';
import '../log_manager.dart';
import '../utils.dart';

class GarminManager extends ChangeNotifier {
  static final GarminManager _instance = GarminManager._internal();
  factory GarminManager() => _instance;
  GarminManager._internal();

  final _storage = AppStorage();
  final _service = GarminService();
  final _logManager = LogManager();

  String? _username;
  String? get username => _username;

  Future<void> init() async {
    await _storage.init();
    final nickname = await _storage.read(key: 'garmin_nickname');
    final account = await _storage.read(key: 'garmin_username');
    _username = nickname ?? (account != null ? maskAccount(account) : null);
    final token = await _storage.read(key: 'garmin_token');
    if (token != null) _service.token = token;
    _service.refreshToken = await _storage.read(key: 'garmin_refresh_token');
    _service.diClientId = await _storage.read(key: 'garmin_client_id');
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final result = await _service.login(email, password);
      if (result['success'] == true) {
        await _storage.write(key: 'garmin_username', value: email);
        await _storage.write(key: 'garmin_password', value: password);
        await _storage.write(key: 'garmin_token', value: result['token'] ?? '');
        if (result['refreshToken'] != null) {
          await _storage.write(key: 'garmin_refresh_token', value: result['refreshToken']);
        }
        if (result['clientId'] != null) {
          await _storage.write(key: 'garmin_client_id', value: result['clientId']);
        }

        _username = maskAccount(email);
        _logManager.addLog('佳明登录成功: $email');
        // 异步获取显示名称
        _fetchDisplayName();
        notifyListeners();
        return true;
      }
      _logManager.addLog('佳明登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('佳明登录错误: $e', isError: true);
      return false;
    }
  }

  Future<void> _fetchDisplayName() async {
    try {
      final name = await _service.getUsername();
      if (name.isNotEmpty) {
        _username = name;
        await _storage.write(key: 'garmin_nickname', value: name);
        notifyListeners();
      }
    } catch (_) {
      // 获取显示名称失败，使用邮箱
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'garmin_username');
    await _storage.delete(key: 'garmin_password');
    await _storage.delete(key: 'garmin_token');
    await _storage.delete(key: 'garmin_refresh_token');
    await _storage.delete(key: 'garmin_client_id');
    await _storage.delete(key: 'garmin_nickname');
    _username = null;
    _service.token = '';
    _service.refreshToken = null;
    _service.diClientId = null;
    _logManager.addLog('佳明已登出');
    notifyListeners();
  }

  Future<bool> checkAndLogin() async {
    if (_service.isLoggedIn) return true;

    // 尝试刷新token
    if (_service.refreshToken != null) {
      final refreshResult = await _service.refresh();
      if (refreshResult['success'] == true) {
        await _storage.write(key: 'garmin_token', value: refreshResult['token'] ?? '');
        _logManager.addLog('佳明token刷新成功');
        _fetchDisplayName();
        return true;
      }
    }

    // 尝试重新登录
    final email = await _storage.read(key: 'garmin_username');
    final password = await _storage.read(key: 'garmin_password');
    if (email == null || password == null) {
      _logManager.addLog('佳明无保存的凭证', isError: true);
      return false;
    }

    _logManager.addLog('佳明尝试重新登录...');
    final loginResult = await _service.login(email, password);
    if (loginResult['success'] == true) {
      await _storage.write(key: 'garmin_token', value: loginResult['token'] ?? '');
      _fetchDisplayName();
      return true;
    }

    _logManager.addLog('佳明重新登录失败', isError: true);
    return false;
  }

  Future<List<Map<String, dynamic>>> getActivities() async {
    if (!await checkAndLogin()) {
      throw Exception('佳明未登录');
    }

    _logManager.addLog('获取佳明活动列表...');
    final activities = await _service.getActivities('cycling', null);
    _logManager.addLog('获取到 ${activities.length} 个佳明活动');
    return activities;
  }

  Future<Uint8List> downloadFit(String activityId) async {
    if (!await checkAndLogin()) {
      throw Exception('佳明未登录');
    }

    _logManager.addLog('下载佳明FIT文件: $activityId');
    final bytes = await _service.downloadFit(activityId);
    _logManager.addLog('佳明FIT文件下载完成');
    return bytes;
  }

  Future<String> uploadFitFile(Uint8List fitBytes, String fileName) async {
    if (!await checkAndLogin()) {
      throw Exception('佳明未登录');
    }

    _logManager.addLog('上传到佳明: $fileName');
    final result = await _service.uploadFit(fitBytes, fileName);
    _logManager.addLog('佳明上传成功: $result');
    return result;
  }

  bool get isLoggedIn => _service.isLoggedIn;
}
