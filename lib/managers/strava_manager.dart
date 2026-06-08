import 'package:flutter/foundation.dart';
import '../services/strava_service.dart';
import '../log_manager.dart';

class StravaManager extends ChangeNotifier {
  static final StravaManager _instance = StravaManager._internal();
  factory StravaManager() => _instance;
  StravaManager._internal();

  final _service = StravaService();
  final _logManager = LogManager();

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  String? _athleteName;
  String? get athleteName => _athleteName;

  Future<void> init() async {
    await _service.init();
    await _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (_service.isAuthenticated) {
      try {
        final athlete = await _service.getAthlete();
        if (athlete != null) {
          _athleteName = '${athlete['firstname']} ${athlete['lastname']}';
          _logManager.addLog('Strava已连接: $_athleteName');
        }
      } catch (e) {
        _logManager.addLog('Strava认证检查失败: $e', isError: true);
      }
    }
  }

  // 保存Strava凭证
  Future<bool> saveCredentials(String clientId, String clientSecret) async {
    final changed = await _service.saveCredentials(clientId, clientSecret);
    if (changed) {
      _logManager.addLog('Strava凭证已更新');
    }
    return changed;
  }

  // 获取授权URL
  Uri getAuthorizationUrl({bool mobile = true}) {
    return _service.getAuthorizationUrl(mobile: mobile);
  }

  // 处理授权回调
  Future<bool> handleAuthCallback(Uri uri) async {
    try {
      final success = await _service.handleAuthCallback(uri);
      if (success) {
        await _checkAuth();
        _logManager.addLog('Strava授权成功');
        notifyListeners();
      }
      return success;
    } catch (e) {
      _logManager.addLog('Strava授权失败: $e', isError: true);
      rethrow;
    }
  }

  // 登出
  Future<void> logout() async {
    final deauthorized = await _service.logout();
    _athleteName = null;
    _logManager.addLog(deauthorized ? 'Strava已撤销授权并登出' : 'Strava已清除本地授权');
    notifyListeners();
  }

  // 上传FIT文件
  Future<String> uploadFitFile(
    Uint8List fitBytes,
    String fileName, {
    String? sportType,
    String? activityName,
    String? description,
    String? externalId,
  }) async {
    if (!_service.isAuthenticated) {
      throw Exception('Strava未授权');
    }

    _isUploading = true;
    notifyListeners();

    try {
      _logManager.addLog('上传到Strava: $fileName');
      final result = await _service.uploadFitFile(
        fitBytes,
        fileName,
        sportType: sportType,
        activityName: activityName,
        description: description,
        externalId: externalId,
      );
      _logManager.addLog('Strava上传成功: $result');
      return result;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  // 检查是否已认证
  bool get isAuthenticated => _service.isAuthenticated;

  // 检查是否有凭证
  bool get hasCredentials => _service.hasCredentials;
}
