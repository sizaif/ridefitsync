import 'dart:convert';
import 'app_storage.dart';
import 'log_manager.dart';

/// 同步记录管理器 - 记录每个活动在每个平台的同步状态
class SyncRecordManager {
  static final SyncRecordManager _instance = SyncRecordManager._internal();
  factory SyncRecordManager() => _instance;
  SyncRecordManager._internal();

  final _storage = AppStorage();
  final _logManager = LogManager();

  // 同步记录缓存: {activityId: {platform: SyncStatus}}
  Map<String, Map<String, SyncStatus>> _syncRecords = {};

  /// 初始化，从存储加载同步记录
  Future<void> init() async {
    await _loadRecords();
  }

  /// 从存储加载同步记录
  Future<void> _loadRecords() async {
    try {
      final recordsJson = await _storage.readPrefs(key: 'sync_records');
      if (recordsJson != null && recordsJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(recordsJson);
        _syncRecords = decoded.map((activityId, platforms) {
          final platformMap = (platforms as Map<String, dynamic>).map(
            (platform, status) => MapEntry(
              platform,
              SyncStatus.fromJson(status as Map<String, dynamic>),
            ),
          );
          return MapEntry(activityId, platformMap);
        });
        _logManager.addLog('已加载 ${_syncRecords.length} 条同步记录');
      }
    } catch (e) {
      _logManager.addLog('加载同步记录失败: $e', isError: true);
      _syncRecords = {};
    }
  }

  /// 保存同步记录到存储
  Future<void> _saveRecords() async {
    try {
      final recordsJson = jsonEncode(_syncRecords);
      await _storage.writePrefs(key: 'sync_records', value: recordsJson);
    } catch (e) {
      _logManager.addLog('保存同步记录失败: $e', isError: true);
    }
  }

  /// 检查活动是否已经成功同步到指定平台
  bool isSynced(String activityId, String platform) {
    final activityRecords = _syncRecords[activityId];
    if (activityRecords == null) return false;
    final status = activityRecords[platform];
    return status != null && status.isSuccess;
  }

  /// 检查活动是否已经同步到所有启用的平台
  bool isSyncedToAllPlatforms(String activityId, List<String> enabledPlatforms) {
    for (var platform in enabledPlatforms) {
      if (!isSynced(activityId, platform)) {
        return false;
      }
    }
    return true;
  }

  /// 记录同步成功
  Future<void> recordSuccess(String activityId, String platform, {String? activityName}) async {
    _syncRecords[activityId] ??= {};
    _syncRecords[activityId]![platform] = SyncStatus(
      isSuccess: true,
      timestamp: DateTime.now(),
      errorMessage: null,
      activityName: activityName,
    );
    await _saveRecords();
  }

  /// 记录同步失败
  Future<void> recordFailure(String activityId, String platform, String errorMessage, {String? activityName}) async {
    _syncRecords[activityId] ??= {};
    _syncRecords[activityId]![platform] = SyncStatus(
      isSuccess: false,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
      activityName: activityName,
    );
    await _saveRecords();
  }

  /// 获取活动的同步状态
  Map<String, SyncStatus>? getActivityStatus(String activityId) {
    return _syncRecords[activityId];
  }

  /// 获取需要同步的平台列表（未成功同步的平台）
  List<String> getPlatformsToSync(String activityId, List<String> enabledPlatforms) {
    final platformsToSync = <String>[];
    for (var platform in enabledPlatforms) {
      if (!isSynced(activityId, platform)) {
        platformsToSync.add(platform);
      }
    }
    return platformsToSync;
  }

  /// 清除所有同步记录
  Future<void> clearAllRecords() async {
    _syncRecords.clear();
    await _saveRecords();
    _logManager.addLog('已清除所有同步记录');
  }

  /// 清除指定活动的同步记录
  Future<void> clearActivityRecord(String activityId) async {
    _syncRecords.remove(activityId);
    await _saveRecords();
  }

  /// 获取同步记录数量
  int get recordCount => _syncRecords.length;

  /// 获取所有同步记录（用于调试）
  Map<String, Map<String, SyncStatus>> get allRecords => _syncRecords;
}

/// 同步状态类
class SyncStatus {
  final bool isSuccess;
  final DateTime timestamp;
  final String? errorMessage;
  final String? activityName; // 活动名称（智能标题）

  SyncStatus({
    required this.isSuccess,
    required this.timestamp,
    this.errorMessage,
    this.activityName,
  });

  Map<String, dynamic> toJson() {
    return {
      'isSuccess': isSuccess,
      'timestamp': timestamp.toIso8601String(),
      'errorMessage': errorMessage,
      'activityName': activityName,
    };
  }

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    return SyncStatus(
      isSuccess: json['isSuccess'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorMessage: json['errorMessage'] as String?,
      activityName: json['activityName'] as String?,
    );
  }

  @override
  String toString() {
    return 'SyncStatus(success: $isSuccess, time: $timestamp, error: $errorMessage)';
  }
}
