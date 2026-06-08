import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../app_storage.dart';
import '../services/onelap_service.dart';
import '../log_manager.dart';
import '../utils.dart';

class OneLapManager extends ChangeNotifier {
  static final OneLapManager _instance = OneLapManager._internal();
  factory OneLapManager() => _instance;
  OneLapManager._internal();

  final _storage = AppStorage();
  final _service = OneLapService();
  final _logManager = LogManager();

  DateTime? _lastSyncDate;
  DateTime? get lastSyncDate => _lastSyncDate;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  String? _username;
  String? get username => _username;

  String? _token;
  int? _tokenExp;

  bool get isLoggedIn {
    if (_token == null) return false;
    // 如果没有过期时间或过期时间为0，只要token存在就认为已登录
    if (_tokenExp == null || _tokenExp == 0) return true;
    final nowTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return _tokenExp! > nowTime;
  }

  Future<void> init() async {
    await _storage.init();
    await _initDate();

    final nickname = await _storage.read(key: 'onelap_nickname');
    final account = await _storage.read(key: 'onelap_username');
    _username = nickname ?? (account != null ? maskAccount(account) : null);
    _token = await _storage.read(key: 'onelap_token');
    _tokenExp = int.tryParse(await _storage.read(key: 'onelap_token_exp') ?? "") ?? 0;
    notifyListeners();
  }

  Future<void> _initDate() async {
    final lastSyncTimeStr = await _storage.read(key: 'onelap_last_sync_time');
    if (lastSyncTimeStr != null) {
      final lastSyncTime = int.tryParse(lastSyncTimeStr);
      if (lastSyncTime != null && lastSyncTime > 0) {
        _lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncTime * 1000);
      }
    }
    // 无记录时 _lastSyncDate 保持 null，首次同步拉取全部活动
  }

  Future<void> setLastSyncDate(DateTime? lastSyncDate) async {
    _lastSyncDate = lastSyncDate;
    notifyListeners();
  }

  Future<void> _saveLastSyncDate(DateTime lastSyncDate) async {
    await _storage.write(
      key: 'onelap_last_sync_time',
      value: (lastSyncDate.millisecondsSinceEpoch ~/ 1000).toString(),
    );
    _lastSyncDate = lastSyncDate;
    notifyListeners();
  }

  Future<void> writeToken(String token) async {
    _token = token;
    await _storage.write(key: 'onelap_token', value: token);
    // 解析JWT获取过期时间
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        _tokenExp = payload['exp'] as int?;
        if (_tokenExp != null) {
          await _storage.write(key: 'onelap_token_exp', value: _tokenExp.toString());
        }
      }
    } catch (e) {
      _logManager.addLog('解析token过期时间失败: $e', isError: true);
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final result = await _service.login(username, password);
      if (result['success'] == true) {
        // 保存凭证
        await _storage.write(key: 'onelap_username', value: username);
        await _storage.write(key: 'onelap_password', value: password);
        final nick = result['nickname'] as String?;
        _username = (nick != null && nick.isNotEmpty) ? nick : maskAccount(username);
        if (nick != null && nick.isNotEmpty) {
          await _storage.write(key: 'onelap_nickname', value: nick);
        }
        await writeToken(result['token']);

        _logManager.addLog('顽鹿登录成功');
        notifyListeners();
        return true;
      }
      _logManager.addLog('顽鹿登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('顽鹿登录错误: $e', isError: true);
      return false;
    }
  }

  /// WebView 登录 — 用户在 WebView 内完成滑块验证后，
  /// 由 OneLapWebViewLoginPage 回调传入拦截到的凭证
  Future<bool> loginViaWebView({
    required String token,
    String? refreshToken,
    String? uid,
    String? nickname,
  }) async {
    try {
      // 保存 token 到安全存储
      await writeToken(token);

      // 自动检测认证模式：JWT 含有 '.' 分隔符，Cookie 则没有
      _service.token = token;
      _service.useCookieAuth = !token.contains('.');

      // 保存 refresh_token（如果有）
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _storage.write(key: 'onelap_refresh_token', value: refreshToken);
      }

      // 保存用户信息
      if (uid != null && uid.isNotEmpty) {
        await _storage.write(key: 'onelap_uid', value: uid);
      }
      if (nickname != null && nickname.isNotEmpty) {
        _username = nickname;
        await _storage.write(key: 'onelap_nickname', value: nickname);
      } else {
        _username = 'OneLap用户';
      }

      _logManager.addLog('顽鹿网页登录成功');
      notifyListeners();
      return true;
    } catch (e) {
      _logManager.addLog('保存顽鹿网页登录凭证失败: $e', isError: true);
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'onelap_username');
    await _storage.delete(key: 'onelap_password');
    await _storage.delete(key: 'onelap_token');
    await _storage.delete(key: 'onelap_token_exp');
    await _storage.delete(key: 'onelap_refresh_token');
    await _storage.delete(key: 'onelap_uid');
    await _storage.delete(key: 'onelap_nickname');
    _username = null;
    _token = null;
    _tokenExp = null;
    _logManager.addLog('顽鹿已登出');
    notifyListeners();
  }

  Future<bool> checkAndLogin() async {
    final nowTime = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;

    // 检查token是否有效（_tokenExp==0 表示未记录过期时间，视为有效）
    if (_token != null &&
        (_tokenExp == null || _tokenExp == 0 || _tokenExp! > nowTime)) {
      _service.token = _token!;
      // 自动检测认证模式：JWT 含有 '.' 分隔符，Cookie 则没有
      _service.useCookieAuth = !_token!.contains('.');
      return true;
    }

    // 尝试重新登录
    final username = await _storage.read(key: 'onelap_username');
    final password = await _storage.read(key: 'onelap_password');

    if (username == null || password == null) {
      _logManager.addLog('顽鹿无保存的凭证', isError: true);
      return false;
    }

    _logManager.addLog('顽鹿token过期，尝试重新登录...');
    final loginResult = await _service.login(username, password);
    if (loginResult['success'] == true) {
      final nick = loginResult['nickname'] as String?;
      if (nick != null && nick.isNotEmpty) {
        _username = nick;
        await _storage.write(key: 'onelap_nickname', value: nick);
      } else {
        _username = maskAccount(username);
      }
      await writeToken(loginResult['token']);
      return true;
    }

    _logManager.addLog('顽鹿重新登录失败', isError: true);
    return false;
  }

  // 获取活动列表
  Future<List<Map<String, dynamic>>> getActivities({DateTime? startDate}) async {
    if (!await checkAndLogin()) {
      throw Exception('顽鹿未登录');
    }

    _logManager.addLog('获取顽鹿活动列表...');
    final activities = await _service.getActivities(startDate ?? _lastSyncDate);
    _logManager.addLog('获取到 ${activities.length} 个顽鹿活动');
    return activities;
  }

  // 上传FIT文件到顽鹿（暂未实现，预留接口）
  Future<void> uploadFitFile(Uint8List fitBytes, String fileName) async {
    throw UnimplementedError('上传到顽鹿功能尚未实现');
  }

  // 下载FIT文件
  Future<Uint8List> downloadFit(String fileKey) async {
    if (!await checkAndLogin()) {
      throw Exception('顽鹿未登录');
    }

    _logManager.addLog('下载顽鹿FIT文件: $fileKey');
    final bytes = await _service.downloadFit(fileKey);
    _logManager.addLog('顽鹿FIT文件下载完成');
    return bytes;
  }

  // 同步活动到其他平台
  Future<int> syncActivities() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    notifyListeners();

    int syncedCount = 0;

    try {
      if (!await checkAndLogin()) {
        throw Exception('顽鹿未登录');
      }

      _logManager.addLog('开始顽鹿同步...');
      final activities = await _service.getActivities(_lastSyncDate);

      if (activities.isEmpty) {
        _logManager.addLog('没有新的顽鹿活动');
        await _saveLastSyncDate(DateTime.now());
        return 0;
      }

      _logManager.addLog('找到 ${activities.length} 个新活动');

      // 返回活动数量，实际下载由调用方处理
      syncedCount = activities.length;
      await _saveLastSyncDate(DateTime.now());
      return syncedCount;
    } catch (e) {
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
