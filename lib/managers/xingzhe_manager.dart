import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_storage.dart';
import '../services/xingzhe_service.dart';
import '../log_manager.dart';
import '../utils.dart';

/// 行者同步管理器
class XingzheManager extends ChangeNotifier {
  static final XingzheManager _instance = XingzheManager._internal();
  factory XingzheManager() => _instance;
  XingzheManager._internal();

  final _storage = AppStorage();
  final _service = XingzheService();
  final _logManager = LogManager();

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  String? _username;
  String? get username => _username;

  String? _sessionId;
  int? _userId;

  Future<void> init() async {
    await _storage.init();

    final nickname = await _storage.read(key: 'xingzhe_nickname');
    final account = await _storage.read(key: 'xingzhe_username');
    _username = nickname ?? (account != null ? maskAccount(account) : null);
    _sessionId = await _storage.read(key: 'xingzhe_session_id');
    _userId = int.tryParse(await _storage.read(key: 'xingzhe_user_id') ?? "") ?? 0;

    if (_sessionId != null) {
      _service.token = _sessionId!;
    }

    notifyListeners();
  }

  Future<void> _saveSession(String sessionId, {int? userId, String? username, String? nickname}) async {
    _sessionId = sessionId;
    _userId = userId;
    if (username != null) {
      await _storage.write(key: 'xingzhe_username', value: username);
    }
    if (nickname != null && nickname.isNotEmpty) {
      _username = nickname;
      await _storage.write(key: 'xingzhe_nickname', value: nickname);
    } else if (username != null) {
      _username = maskAccount(username);
    }
    await _storage.write(key: 'xingzhe_session_id', value: sessionId);
    if (userId != null) {
      await _storage.write(key: 'xingzhe_user_id', value: userId.toString());
    }
    _service.token = sessionId;
  }

  Future<bool> login(String username, String password) async {
    try {
      final result = await _service.login(username, password);
      if (result['success'] == true) {
        // 保存凭证
        await _storage.write(key: 'xingzhe_username', value: username);
        await _storage.write(key: 'xingzhe_password', value: password);

        await _saveSession(
          result['token'],
          userId: result['userid'],
          username: username,
          nickname: result['username'],
        );

        _logManager.addLog('行者登录成功: ${result['username'] ?? username}');
        notifyListeners();
        return true;
      }
      _logManager.addLog('行者登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('行者登录错误: $e', isError: true);
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'xingzhe_username');
    await _storage.delete(key: 'xingzhe_password');
    await _storage.delete(key: 'xingzhe_session_id');
    await _storage.delete(key: 'xingzhe_user_id');
    await _storage.delete(key: 'xingzhe_nickname');
    _username = null;
    _sessionId = null;
    _userId = null;
    _logManager.addLog('行者已登出');
    notifyListeners();
  }

  Future<bool> checkAndLogin() async {
    // 检查session是否存在
    if (_sessionId != null) {
      _service.token = _sessionId!;
      return true;
    }

    // 尝试重新登录
    final username = await _storage.read(key: 'xingzhe_username');
    final password = await _storage.read(key: 'xingzhe_password');

    if (username == null || password == null) {
      _logManager.addLog('行者无保存的凭证', isError: true);
      return false;
    }

    _logManager.addLog('行者尝试登录...');
    final loginResult = await _service.login(username, password);
    if (loginResult['success'] == true) {
      await _saveSession(
        loginResult['token'],
        userId: loginResult['userid'],
        username: username,
        nickname: loginResult['username'],
      );
      return true;
    }

    _logManager.addLog('行者登录失败', isError: true);
    return false;
  }

  // 上传FIT文件
  Future<String> uploadFitFile(Uint8List fitBytes, String fileName) async {
    if (!await checkAndLogin()) {
      throw Exception('行者未登录');
    }

    _isUploading = true;
    notifyListeners();

    try {
      _logManager.addLog('上传到行者: $fileName');
      final result = await _service.uploadFit(fitBytes, fileName);
      _logManager.addLog('行者上传成功: $result');
      return result;
    } catch (e) {
      throw Exception('行者上传失败: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  // 获取活动列表（用于数据源）
  Future<List<Map<String, dynamic>>> getActivities() async {
    if (!await checkAndLogin()) {
      throw Exception('行者未登录');
    }

    _logManager.addLog('获取行者活动列表...');
    final activities = await _service.getActivities();
    _logManager.addLog('获取到 ${activities.length} 个行者活动');
    return activities;
  }

  // 下载FIT文件（行者活动列表中包含fit_url字段）
  Future<Uint8List> downloadFit(String url) async {
    if (!await checkAndLogin()) {
      throw Exception('行者未登录');
    }

    _logManager.addLog('下载行者FIT文件');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      _logManager.addLog('行者FIT文件下载完成');
      return response.bodyBytes;
    }
    throw Exception('下载失败: ${response.statusCode}');
  }

  bool get isLoggedIn => _service.isLoggedIn;
}
