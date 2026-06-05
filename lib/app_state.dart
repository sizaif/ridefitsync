import 'package:flutter/material.dart';
import 'log_manager.dart';

class AppState extends ChangeNotifier {
  // 同步状态
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  // 同步统计
  int _totalSynced = 0;
  int _lastSyncCount = 0;
  DateTime? _lastSyncTime;

  int get totalSynced => _totalSynced;
  int get lastSyncCount => _lastSyncCount;
  DateTime? get lastSyncTime => _lastSyncTime;

  // 日志管理器
  final LogManager _logManager = LogManager();
  LogManager get logManager => _logManager;

  // 开始同步
  void startSync() {
    _isSyncing = true;
    _logManager.addLog('开始同步...');
    notifyListeners();
  }

  // 完成同步
  void completeSync(int count) {
    _isSyncing = false;
    _lastSyncCount = count;
    _totalSynced += count;
    _lastSyncTime = DateTime.now();
    _logManager.addLog('同步完成: $count 个活动');
    notifyListeners();
  }

  // 同步失败
  void syncFailed(String error) {
    _isSyncing = false;
    _logManager.addLog('同步失败: $error', isError: true);
    notifyListeners();
  }
}
