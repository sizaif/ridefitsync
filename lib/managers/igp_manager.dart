import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../app_storage.dart';
import '../services/igp_service.dart';
import '../log_manager.dart';
import '../utils.dart';

class IGPManager extends ChangeNotifier {
  static final IGPManager _instance = IGPManager._internal();
  factory IGPManager() => _instance;
  IGPManager._internal();

  final _storage = AppStorage();
  final _service = IGPService();
  final _logManager = LogManager();

  DateTime? _lastSyncDate;
  DateTime? get lastSyncDate => _lastSyncDate;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  String? _username;
  String? get username => _username;

  String? _token;
  String? _refreshToken;
  int? _tokenExp;

  Future<void> init() async {
    await _storage.init();
    await _initDate();

    final nickname = await _storage.read(key: 'igp_nickname');
    final account = await _storage.read(key: 'igp_username');
    _username = nickname ?? (account != null ? maskAccount(account) : null);
    _token = await _storage.read(key: 'igp_token');
    _refreshToken = await _storage.read(key: 'igp_refresh_token');
    _tokenExp = int.tryParse(await _storage.read(key: 'igp_token_exp') ?? "") ?? 0;

    // 设置 token 到 service
    if (_token != null) {
      _service.token = _token!;
    }

    notifyListeners();
  }

  Future<void> _initDate() async {
    final lastSyncTimeStr = await _storage.read(key: 'igp_last_sync_time');
    if (lastSyncTimeStr != null) {
      final lastSyncTime = int.tryParse(lastSyncTimeStr);
      if (lastSyncTime != null && lastSyncTime > 0) {
        _lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncTime * 1000);
      }
    }
  }

  Future<void> setLastSyncDate(DateTime? lastSyncDate) async {
    _lastSyncDate = lastSyncDate;
    notifyListeners();
  }

  Future<void> _saveLastSyncDate(DateTime lastSyncDate) async {
    await _storage.write(
      key: 'igp_last_sync_time',
      value: (lastSyncDate.millisecondsSinceEpoch ~/ 1000).toString(),
    );
    _lastSyncDate = lastSyncDate;
    notifyListeners();
  }

  Future<void> writeToken(String token, {String? refreshToken, int? expiresIn}) async {
    _token = token;
    _refreshToken = refreshToken;
    await _storage.write(key: 'igp_token', value: token);

    if (refreshToken != null) {
      await _storage.write(key: 'igp_refresh_token', value: refreshToken);
    }

    // 解析JWT获取过期时间
    _tokenExp = _service.getTokenExp();
    if (_tokenExp != null) {
      await _storage.write(key: 'igp_token_exp', value: _tokenExp.toString());
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final result = await _service.login(username, password);
      if (result['success'] == true) {
        // 保存凭证
        await _storage.write(key: 'igp_username', value: username);
        await _storage.write(key: 'igp_password', value: password);
        final nick = result['nickname'] as String?;
        _username = (nick != null && nick.isNotEmpty) ? nick : maskAccount(username);
        if (nick != null && nick.isNotEmpty) {
          await _storage.write(key: 'igp_nickname', value: nick);
        }
        await writeToken(
          result['token'],
          refreshToken: result['refresh_token'],
          expiresIn: result['expires_in'],
        );

        _logManager.addLog('iGPSPORT登录成功');
        notifyListeners();
        return true;
      }
      _logManager.addLog('iGPSPORT登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('iGPSPORT登录错误: $e', isError: true);
      return false;
    }
  }

  /// 发送短信验证码
  Future<bool> sendSmsCode(String phone) async {
    final result = await _service.sendSmsCode(phone);
    if (result['success'] == true) {
      _logManager.addLog('iGPSPORT验证码已发送到 $phone');
      return true;
    }
    _logManager.addLog('iGPSPORT发送验证码失败: ${result['message']}', isError: true);
    return false;
  }

  /// 短信验证码登录
  Future<bool> loginBySmsCode(String phone, String smsCode) async {
    try {
      final result = await _service.loginBySmsCode(phone, smsCode);
      if (result['success'] == true) {
        // 保存凭证（不保存密码，因为是验证码登录）
        await _storage.write(key: 'igp_username', value: phone);
        final nick = result['nickname'] as String?;
        _username = (nick != null && nick.isNotEmpty) ? nick : maskAccount(phone);
        if (nick != null && nick.isNotEmpty) {
          await _storage.write(key: 'igp_nickname', value: nick);
        }
        await writeToken(
          result['token'],
          refreshToken: result['refresh_token'],
          expiresIn: result['expires_in'],
        );

        _logManager.addLog('iGPSPORT验证码登录成功');
        notifyListeners();
        return true;
      }
      _logManager.addLog('iGPSPORT验证码登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('iGPSPORT验证码登录错误: $e', isError: true);
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'igp_username');
    await _storage.delete(key: 'igp_password');
    await _storage.delete(key: 'igp_token');
    await _storage.delete(key: 'igp_refresh_token');
    await _storage.delete(key: 'igp_token_exp');
    await _storage.delete(key: 'igp_nickname');
    _username = null;
    _token = null;
    _refreshToken = null;
    _tokenExp = null;
    _service.token = null;
    _logManager.addLog('iGPSPORT已登出');
    notifyListeners();
  }

  Future<bool> checkAndLogin() async {
    final nowTime = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;

    // 检查token是否有效（_tokenExp==0 表示未记录过期时间，视为有效）
    if (_token != null &&
        (_tokenExp == null || _tokenExp == 0 || _tokenExp! > nowTime)) {
      _service.token = _token!;
      return true;
    }

    // 尝试重新登录
    final username = await _storage.read(key: 'igp_username');
    final password = await _storage.read(key: 'igp_password');

    if (username == null || password == null) {
      _logManager.addLog('iGPSPORT无保存的凭证', isError: true);
      return false;
    }

    _logManager.addLog('iGPSPORT token过期，尝试重新登录...');
    final loginResult = await _service.login(username, password);
    if (loginResult['success'] == true) {
      final nick = loginResult['nickname'] as String?;
      if (nick != null && nick.isNotEmpty) {
        _username = nick;
        await _storage.write(key: 'igp_nickname', value: nick);
      } else {
        _username = maskAccount(username);
      }
      await writeToken(
        loginResult['token'],
        refreshToken: loginResult['refresh_token'],
        expiresIn: loginResult['expires_in'],
      );
      return true;
    }

    _logManager.addLog('iGPSPORT重新登录失败', isError: true);
    return false;
  }

  // 上传FIT文件
  Future<String> uploadFitFile(Uint8List fitBytes, String fileName) async {
    if (!await checkAndLogin()) {
      throw Exception('iGPSPORT未登录');
    }

    _logManager.addLog('上传到iGPSPORT: $fileName');
    try {
      final result = await _service.uploadFit(fitBytes, fileName);
      _logManager.addLog('iGPSPORT上传成功: $result');
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // 获取活动列表（用于下载）
  Future<List<Map<String, dynamic>>> getActivities({DateTime? startDate}) async {
    if (!await checkAndLogin()) {
      throw Exception('iGPSPORT未登录');
    }

    _logManager.addLog('获取iGPSPORT活动列表...');
    final activities = await _service.getActivities(startDate ?? _lastSyncDate);
    _logManager.addLog('获取到 ${activities.length} 个iGPSPORT活动');
    return activities;
  }

  // 下载FIT文件
  Future<Uint8List> downloadFit(String url) async {
    if (!await checkAndLogin()) {
      throw Exception('iGPSPORT未登录');
    }

    _logManager.addLog('下载iGPSPORT FIT文件');
    final bytes = await _service.downloadFit(url);
    _logManager.addLog('iGPSPORT FIT文件下载完成');
    return bytes;
  }

  bool get isLoggedIn => _service.isLoggedIn;
}
