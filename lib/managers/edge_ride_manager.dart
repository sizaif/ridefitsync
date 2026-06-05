import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../app_storage.dart';
import '../services/edge_ride_service.dart';
import '../log_manager.dart';
import '../utils.dart';

/// EdgeRide 同步管理器
class EdgeRideManager extends ChangeNotifier {
  static final EdgeRideManager _instance = EdgeRideManager._internal();
  factory EdgeRideManager() => _instance;
  EdgeRideManager._internal();

  final _storage = AppStorage();
  final _service = EdgeRideService();
  final _logManager = LogManager();

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  String? _username;
  String? get username => _username;

  String? _phone;

  Future<void> init() async {
    await _storage.init();

    // 恢复登录会话
    final sid = await _storage.read(key: 'edge_ride_sid');
    final uid = await _storage.read(key: 'edge_ride_uid');
    if (sid != null) {
      _service.restoreSession(sid, uid);
    }

    final nickname = await _storage.read(key: 'edge_ride_nickname');
    final phone = await _storage.read(key: 'edge_ride_phone');
    _phone = phone;
    _username = nickname ?? (phone != null ? maskAccount(phone) : null);

    notifyListeners();
  }

  /// 发送验证码
  Future<bool> sendSmsCode(String phone) async {
    final result = await _service.sendSmsCode(phone);
    if (result['success'] == true) {
      _logManager.addLog('EdgeRide验证码已发送到 $phone');
      return true;
    }
    _logManager.addLog('EdgeRide发送验证码失败: ${result['message']}', isError: true);
    return false;
  }

  /// 验证码登录
  Future<bool> login(String phone, String verifyCode) async {
    try {
      final result = await _service.login(phone, verifyCode);
      if (result['success'] == true) {
        await _storage.write(key: 'edge_ride_phone', value: phone);
        await _storage.write(key: 'edge_ride_sid', value: result['sid'] as String? ?? '');
        await _storage.write(key: 'edge_ride_uid', value: result['uid'] as String? ?? '');
        _phone = phone;
        _username = maskAccount(phone);

        _logManager.addLog('EdgeRide登录成功');
        notifyListeners();
        return true;
      }
      _logManager.addLog('EdgeRide登录失败: ${result['message']}', isError: true);
      return false;
    } catch (e) {
      _logManager.addLog('EdgeRide登录错误: $e', isError: true);
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'edge_ride_phone');
    await _storage.delete(key: 'edge_ride_nickname');
    await _storage.delete(key: 'edge_ride_sid');
    await _storage.delete(key: 'edge_ride_uid');
    _username = null;
    _phone = null;
    _logManager.addLog('EdgeRide已登出');
    notifyListeners();
  }

  /// 上传FIT文件
  Future<String> uploadFitFile(Uint8List fitBytes, String fileName) async {
    if (!isLoggedIn) {
      throw Exception('EdgeRide未登录');
    }

    _isUploading = true;
    notifyListeners();

    try {
      _logManager.addLog('上传到EdgeRide: $fileName');
      final result = await _service.uploadFit(fitBytes, fileName);
      _logManager.addLog('EdgeRide上传成功: $result');
      return result;
    } catch (e) {
      throw Exception('EdgeRide上传失败: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  bool get isLoggedIn => _service.isLoggedIn;
}
