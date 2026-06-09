import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'managers/onelap_manager.dart';
import 'managers/strava_manager.dart';
import 'managers/igp_manager.dart';
import 'managers/xingzhe_manager.dart';
import 'managers/giant_manager.dart';
import 'managers/garmin_manager.dart';
import 'managers/edge_ride_manager.dart';
import 'log_manager.dart';
import 'app_storage.dart';
import 'coord_fixer.dart';
import 'fit_analyzer.dart';
import 'sync_record_manager.dart';

/// 同步中心 - 协调所有平台的同步
class SyncHub extends ChangeNotifier {
  static final SyncHub _instance = SyncHub._internal();
  factory SyncHub() => _instance;
  SyncHub._internal();

  final _onelapManager = OneLapManager();
  final _stravaManager = StravaManager();
  final _igpManager = IGPManager();
  final _xingzheManager = XingzheManager();
  final _giantManager = GiantManager();
  final _garminManager = GarminManager();
  final _edgeRideManager = EdgeRideManager();
  final _logManager = LogManager();
  final _storage = AppStorage();
  final _syncRecordManager = SyncRecordManager();
  bool _managerListenersAttached = false;
  AppStorage get storage => _storage;
  SyncRecordManager get syncRecordManager => _syncRecordManager;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  int _syncedCount = 0;
  int get syncedCount => _syncedCount;

  int _failedCount = 0;
  int get failedCount => _failedCount;

  int _skippedCount = 0;
  int get skippedCount => _skippedCount;

  // 坐标系：国内平台使用 GCJ-02，海外平台使用 WGS-84
  static const _gcjPlatforms = {
    'onelap',
    'igp',
    'xingzhe',
    'giant',
    'edge_ride',
  };
  static bool _isGcjPlatform(String platform) =>
      _gcjPlatforms.contains(platform);

  /// 计算目标平台需要的坐标纠偏方向
  /// 只有在「国内源(GCJ-02) → 海外目标(WGS-84)」时才需要纠偏
  /// 海外源 → 国内目标时不转换，国内平台会自行处理坐标
  CoordDirection? _coordDirection(String target) {
    final sourceGcj = _isGcjPlatform(_dataSource);
    final targetGcj = _isGcjPlatform(target);
    if (sourceGcj && !targetGcj) return CoordDirection.gcj2wgs; // GCJ→WGS
    return null; // 其他情况不转换
  }

  /// 对指定 target 做坐标纠偏（如需要），返回纠偏后的 bytes
  Future<Uint8List> _maybeCorrect(
    Uint8List bytes,
    String fileName,
    String target,
  ) async {
    final dir = _coordDirection(target);
    if (dir == null) return bytes;
    final ext = fileName.split('.').last.toLowerCase();
    if (!['fit', 'gpx', 'tcx'].contains(ext)) return bytes;
    try {
      final corrected = await CoordFixer.processFile(bytes, ext, dir);
      final result = CoordFixer.lastDetectionResult;
      _logManager.addLog(
        '坐标纠偏: ${dir == CoordDirection.gcj2wgs ? "GCJ-02→WGS-84" : "WGS-84→GCJ-02"} '
        '(源:$_dataSource → 目标:$target, 样本:${CoordFixer.lastSampleCount}'
        '${result != null ? ", 已${result == (dir == CoordDirection.gcj2wgs ? false : true) ? "" : "无需"}纠正" : ""})',
      );
      return corrected;
    } catch (e) {
      _logManager.addLog('坐标纠偏失败: $e', isError: true);
      return bytes;
    }
  }

  // 数据源平台（默认顽鹿）
  String _dataSource = 'onelap';
  String get dataSource => _dataSource;

  // 活动时间范围: all/today/week/month
  String _activityTimeRange = 'today';
  String get activityTimeRange => _activityTimeRange;

  // 本地缓存的 FIT 文件（最新一个活动）
  Uint8List? _cachedFitBytes;
  String? _cachedFileName;
  Map<String, dynamic>? _cachedActivity;
  DateTime? _cachedTime;

  // 获取缓存的 FIT 文件信息
  Uint8List? get cachedFitBytes => _cachedFitBytes;
  String? get cachedFileName => _cachedFileName;
  bool get hasCachedFit => _cachedFitBytes != null && _cachedFileName != null;

  // 上传目标平台开关
  bool _enableOnelap = true;
  bool _enableStrava = true;
  bool _enableIgp = true;
  bool _enableXingzhe = true;
  bool _enableGiant = true;
  bool _enableGarmin = true;
  bool _enableEdgeRide = true;
  bool _enableActivityDescription = true;
  bool _forceSync = false; // 强制同步开关

  // 定时自动同步
  Timer? _autoSyncTimer;
  bool _autoSyncEnabled = false;
  int _syncIntervalMinutes = 120;
  void Function(int successCount, int failCount)? onSyncCompleted;

  // 并发同步数
  int _syncConcurrency = 3;

  bool get autoSyncEnabled => _autoSyncEnabled;
  int get syncConcurrency => _syncConcurrency;

  bool get enableOnelap => _enableOnelap;
  bool get enableStrava => _enableStrava;
  bool get enableIgp => _enableIgp;
  bool get enableXingzhe => _enableXingzhe;
  bool get enableGiant => _enableGiant;
  bool get enableGarmin => _enableGarmin;
  bool get enableEdgeRide => _enableEdgeRide;
  bool get enableActivityDescription => _enableActivityDescription;
  bool get forceSync => _forceSync;

  // 初始化所有管理器
  Future<void> init() async {
    await _storage.init();
    await _syncRecordManager.init();
    await _onelapManager.init();
    await _stravaManager.init();
    await _igpManager.init();
    await _xingzheManager.init();
    await _giantManager.init();
    await _garminManager.init();
    await _edgeRideManager.init();
    _attachManagerListeners();
    await loadSettings();

    // 异步预加载最新活动（不阻塞启动）
    _preloadLatestActivity();
  }

  void _attachManagerListeners() {
    if (_managerListenersAttached) return;
    _stravaManager.addListener(_onManagerStateChanged);
    _managerListenersAttached = true;
  }

  void _onManagerStateChanged() {
    notifyListeners();
  }

  // 预加载最新活动到缓存
  Future<void> _preloadLatestActivity() async {
    // 检查数据源是否已登录
    if (!isDataSourceLoggedIn) {
      _logManager.addLog('数据源未登录，跳过预加载');
      return;
    }

    try {
      _logManager.addLog('预加载数据源最新活动...');
      final result = await getLatestFitFile();
      if (result != null) {
        final fromCache = result['fromCache'] as bool;
        final fileName = result['fileName'] as String;
        _logManager.addLog(fromCache ? '使用缓存: $fileName' : '预加载完成: $fileName');
      } else {
        _logManager.addLog('预加载: 没有新活动');
      }
    } catch (e) {
      _logManager.addLog('预加载失败: $e', isError: true);
    }
  }

  Future<void> loadSettings() async {
    _dataSource = await _storage.readPrefs(key: 'data_source') ?? 'onelap';
    _activityTimeRange =
        await _storage.readPrefs(key: 'activity_time_range') ?? 'today';
    _enableOnelap = await _storage.readBoolPrefs(
      key: 'enable_onelap',
      defaultValue: true,
    );
    _enableStrava = await _storage.readBoolPrefs(
      key: 'enable_strava',
      defaultValue: true,
    );
    _enableIgp = await _storage.readBoolPrefs(
      key: 'enable_igp',
      defaultValue: true,
    );
    _enableXingzhe = await _storage.readBoolPrefs(
      key: 'enable_xingzhe',
      defaultValue: true,
    );
    _enableGiant = await _storage.readBoolPrefs(
      key: 'enable_giant',
      defaultValue: true,
    );
    _enableGarmin = await _storage.readBoolPrefs(
      key: 'enable_garmin',
      defaultValue: true,
    );
    _enableEdgeRide = await _storage.readBoolPrefs(
      key: 'enable_edge_ride',
      defaultValue: true,
    );
    _enableActivityDescription = await _storage.readBoolPrefs(
      key: 'activity_description',
      defaultValue: true,
    );
    _forceSync = await _storage.readBoolPrefs(
      key: 'force_sync',
      defaultValue: false,
    );
    _syncConcurrency = await _storage.readIntPrefs(
      key: 'sync_concurrency',
      defaultValue: 3,
    );
    await _loadAutoSyncSettings();
    notifyListeners();
  }

  Future<void> _loadAutoSyncSettings() async {
    _autoSyncEnabled = await _storage.readBoolPrefs(key: 'auto_sync');
    _syncIntervalMinutes = await _storage.readIntPrefs(
      key: 'sync_interval',
      defaultValue: 120,
    );
    if (_autoSyncEnabled) {
      _startAutoSyncTimer();
    }
  }

  void _startAutoSyncTimer() {
    _stopAutoSyncTimer();
    _autoSyncTimer = Timer.periodic(
      Duration(minutes: _syncIntervalMinutes),
      (_) => _autoSyncTick(),
    );
    _logManager.addLog('定时同步已启动 (每$_syncIntervalMinutes分钟)');
  }

  void _stopAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> _autoSyncTick() async {
    if (_isSyncing) {
      _logManager.addLog('上次同步尚未完成，跳过本次定时同步');
      return;
    }
    if (!canSync) {
      _logManager.addLog('定时同步: 未满足同步条件');
      return;
    }
    _logManager.addLog('定时同步: 开始检查新活动...');
    await sync();
  }

  /// 启用/禁用自动同步
  Future<void> setAutoSync(bool enabled) async {
    _autoSyncEnabled = enabled;
    await _storage.writeBoolPrefs(key: 'auto_sync', value: enabled);
    if (enabled) {
      _startAutoSyncTimer();
      _logManager.addLog('自动同步已开启');
    } else {
      _stopAutoSyncTimer();
      _logManager.addLog('自动同步已关闭');
    }
    notifyListeners();
  }

  /// 更新同步间隔
  Future<void> setSyncInterval(int minutes) async {
    _syncIntervalMinutes = minutes;
    await _storage.writeIntPrefs(key: 'sync_interval', value: minutes);
    // 如果定时器在运行，重启以使用新间隔
    if (_autoSyncEnabled) {
      _startAutoSyncTimer();
    }
    _logManager.addLog('同步间隔更新为 $minutes 分钟');
    notifyListeners();
  }

  int get syncIntervalMinutes => _syncIntervalMinutes;

  Future<void> setDataSource(String source) async {
    _dataSource = source;
    await _storage.writePrefs(key: 'data_source', value: source);
    notifyListeners();
  }

  Future<void> setActivityTimeRange(String range) async {
    _activityTimeRange = range;
    await _storage.writePrefs(key: 'activity_time_range', value: range);
    notifyListeners();
  }

  /// 根据时间范围计算 startDate
  DateTime? get activityStartDate {
    switch (_activityTimeRange) {
      case 'today':
        return DateTime.now().subtract(const Duration(days: 1));
      case '3days':
        return DateTime.now().subtract(const Duration(days: 3));
      case 'week':
        return DateTime.now().subtract(const Duration(days: 7));
      case 'month':
        return DateTime.now().subtract(const Duration(days: 30));
      case '3months':
        return DateTime.now().subtract(const Duration(days: 90));
      default:
        return null; // 'all' — 不限制
    }
  }

  Future<void> setEnableOnelap(bool value) async {
    _enableOnelap = value;
    await _storage.writeBoolPrefs(key: 'enable_onelap', value: value);
    notifyListeners();
  }

  Future<void> setEnableStrava(bool value) async {
    _enableStrava = value;
    await _storage.writeBoolPrefs(key: 'enable_strava', value: value);
    notifyListeners();
  }

  Future<void> setEnableIgp(bool value) async {
    _enableIgp = value;
    await _storage.writeBoolPrefs(key: 'enable_igp', value: value);
    notifyListeners();
  }

  Future<void> setEnableXingzhe(bool value) async {
    _enableXingzhe = value;
    await _storage.writeBoolPrefs(key: 'enable_xingzhe', value: value);
    notifyListeners();
  }

  Future<void> setEnableGiant(bool value) async {
    _enableGiant = value;
    await _storage.writeBoolPrefs(key: 'enable_giant', value: value);
    notifyListeners();
  }

  Future<void> setEnableGarmin(bool value) async {
    _enableGarmin = value;
    await _storage.writeBoolPrefs(key: 'enable_garmin', value: value);
    notifyListeners();
  }

  Future<void> setEnableEdgeRide(bool value) async {
    _enableEdgeRide = value;
    await _storage.writeBoolPrefs(key: 'enable_edge_ride', value: value);
    notifyListeners();
  }

  Future<void> setEnableActivityDescription(bool value) async {
    _enableActivityDescription = value;
    await _storage.writeBoolPrefs(key: 'activity_description', value: value);
    notifyListeners();
  }

  Future<void> setForceSync(bool value) async {
    _forceSync = value;
    await _storage.writeBoolPrefs(key: 'force_sync', value: value);
    _logManager.addLog(value ? '强制同步已开启' : '强制同步已关闭');
    notifyListeners();
  }

  Future<void> setSyncConcurrency(int value) async {
    _syncConcurrency = value.clamp(1, 10);
    await _storage.writeIntPrefs(key: 'sync_concurrency', value: _syncConcurrency);
    _logManager.addLog('同步并发数更新为 $_syncConcurrency');
    notifyListeners();
  }

  // 数据源是否已登录
  bool get isDataSourceLoggedIn {
    switch (_dataSource) {
      case 'onelap':
        return _onelapManager.isLoggedIn;
      case 'igp':
        return _igpManager.isLoggedIn;
      case 'xingzhe':
        return _xingzheManager.isLoggedIn;
      case 'garmin':
        return _garminManager.isLoggedIn;
      default:
        return false;
    }
  }

  // 数据源用户名
  String? get dataSourceUsername {
    switch (_dataSource) {
      case 'onelap':
        return _onelapManager.username;
      case 'igp':
        return _igpManager.username;
      case 'xingzhe':
        return _xingzheManager.username;
      case 'garmin':
        return _garminManager.username;
      default:
        return null;
    }
  }

  // 检查是否可以同步
  bool get canSync {
    if (!isDataSourceLoggedIn) return false;
    // 数据源不能同时作为上传目标
    bool hasTarget = false;
    if (_dataSource != 'onelap' && _enableOnelap && _onelapManager.isLoggedIn)
      hasTarget = true;
    if (_dataSource != 'strava' &&
        _enableStrava &&
        _stravaManager.isAuthenticated)
      hasTarget = true;
    if (_dataSource != 'igp' && _enableIgp && _igpManager.isLoggedIn)
      hasTarget = true;
    if (_dataSource != 'xingzhe' &&
        _enableXingzhe &&
        _xingzheManager.isLoggedIn)
      hasTarget = true;
    if (_dataSource != 'giant' && _enableGiant && _giantManager.isLoggedIn)
      hasTarget = true;
    if (_dataSource != 'garmin' && _enableGarmin && _garminManager.isLoggedIn)
      hasTarget = true;
    if (_dataSource != 'edge_ride' &&
        _enableEdgeRide &&
        _edgeRideManager.isLoggedIn)
      hasTarget = true;
    return hasTarget;
  }

  // 获取各平台登录状态
  bool get onelapLoggedIn => _onelapManager.isLoggedIn;
  bool get stravaLoggedIn => _stravaManager.isAuthenticated;
  bool get igpLoggedIn => _igpManager.isLoggedIn;
  bool get xingzheLoggedIn => _xingzheManager.isLoggedIn;
  bool get giantLoggedIn => _giantManager.isLoggedIn;
  bool get garminLoggedIn => _garminManager.isLoggedIn;
  bool get edgeRideLoggedIn => _edgeRideManager.isLoggedIn;

  // 执行同步（并发 worker pool 模式）
  Future<void> sync() async {
    if (_isSyncing) return;
    if (!canSync) {
      _logManager.addLog('无法同步：未满足同步条件', isError: true);
      return;
    }

    _isSyncing = true;
    _syncedCount = 0;
    _failedCount = 0;
    _skippedCount = 0;
    notifyListeners();

    try {
      _logManager.addLog('开始从 $_dataSourceDisplayName 同步...');
      if (_forceSync) {
        _logManager.addLog('强制同步模式：将重新同步所有活动');
      }

      // 1. 从数据源获取活动列表
      final activities = await _getSourceActivities();
      if (activities.isEmpty) {
        _logManager.addLog('没有新活动需要同步');
        return;
      }

      _logManager.addLog('找到 ${activities.length} 个活动');

      // 2. 获取当前启用的平台列表
      final enabledPlatforms = _getEnabledPlatforms();

      // 3. 并发处理活动（worker pool）
      final concurrency = _syncConcurrency.clamp(1, activities.length);
      _logManager.addLog('使用 $concurrency 个并发处理活动');

      var nextIndex = 0;

      Future<void> worker() async {
        while (true) {
          final i = nextIndex;
          if (i >= activities.length) break;
          nextIndex = i + 1;

          final activity = activities[i];
          await _processOneActivity(activity, enabledPlatforms);
        }
      }

      // 启动 worker pool
      final workers = <Future<void>>[];
      for (var i = 0; i < concurrency; i++) {
        workers.add(worker());
      }
      await Future.wait(workers);

      // 同步结束后统一保存记录
      await _syncRecordManager.flush();

      _logManager.addLog(
        '同步完成: 成功 $_syncedCount, 失败 $_failedCount, 跳过 $_skippedCount',
      );
      onSyncCompleted?.call(_syncedCount, _failedCount);
    } catch (e) {
      _logManager.addLog('同步错误: $e', isError: true);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 处理单个活动（下载 + 上传到所有平台）
  Future<void> _processOneActivity(
    Map<String, dynamic> activity,
    List<String> enabledPlatforms,
  ) async {
    try {
      final activityId = _getActivityId(activity);
      final title = activity['title'] ?? activity['name'] ?? '未命名活动';

      // 检查是否需要同步
      if (!_forceSync) {
        final platformsToSync = _syncRecordManager.getPlatformsToSync(
          activityId,
          enabledPlatforms,
        );
        if (platformsToSync.isEmpty) {
          _logManager.addLog('跳过活动（已同步）: $title');
          _skippedCount++;
          return;
        }
        _logManager.addLog(
          '处理活动: $title (待同步平台: ${platformsToSync.join(", ")})',
        );
      } else {
        _logManager.addLog('处理活动（强制模式）: $title');
      }

      // 下载 FIT 文件（并发模式下不使用单活动缓存）
      final fitBytes = await _downloadSourceFit(activity);
      final fileName = _buildFileName(activity, fitBytes: fitBytes);

      // Debug: 保存原始下载的 FIT 文件
      await _saveDebugFile(fitBytes, 'original', fileName);

      // 上传到各平台（并行上传 + 批量保存记录）
      await uploadToAllPlatforms(
        fitBytes,
        fileName,
        activityId: activityId,
      );

      // 每完成一个活动立即持久化记录，防止中途崩溃丢失
      await _syncRecordManager.flush();

      _syncedCount++;
    } catch (e) {
      _logManager.addLog('处理活动失败: $e', isError: true);
      _failedCount++;
    }
  }

  String get _dataSourceDisplayName {
    switch (_dataSource) {
      case 'onelap':
        return '顽鹿';
      case 'igp':
        return 'iGPSPORT';
      case 'xingzhe':
        return '行者';
      case 'garmin':
        return '佳明';
      default:
        return _dataSource;
    }
  }

  /// 获取当前启用的平台列表
  List<String> _getEnabledPlatforms() {
    final platforms = <String>[];
    if (_dataSource != 'onelap' && _enableOnelap && _onelapManager.isLoggedIn) {
      platforms.add('onelap');
    }
    if (_dataSource != 'strava' &&
        _enableStrava &&
        _stravaManager.isAuthenticated) {
      platforms.add('strava');
    }
    if (_dataSource != 'igp' && _enableIgp && _igpManager.isLoggedIn) {
      platforms.add('igp');
    }
    if (_dataSource != 'xingzhe' &&
        _enableXingzhe &&
        _xingzheManager.isLoggedIn) {
      platforms.add('xingzhe');
    }
    if (_dataSource != 'giant' && _enableGiant && _giantManager.isLoggedIn) {
      platforms.add('giant');
    }
    if (_dataSource != 'garmin' && _enableGarmin && _garminManager.isLoggedIn) {
      platforms.add('garmin');
    }
    if (_dataSource != 'edge_ride' &&
        _enableEdgeRide &&
        _edgeRideManager.isLoggedIn) {
      platforms.add('edge_ride');
    }
    return platforms;
  }

  /// 获取活动的唯一标识
  String _getActivityId(Map<String, dynamic> activity) {
    // 优先使用活动ID
    if (activity['id'] != null) {
      return '${_dataSource}_${activity['id']}';
    }
    // 使用开始时间作为标识
    final startTime = activity['startTime'] ?? activity['start_time'] ?? '';
    if (startTime.isNotEmpty) {
      return '${_dataSource}_$startTime';
    }
    // 使用文件名作为标识
    final fileName = _buildFileName(activity);
    return '${_dataSource}_$fileName';
  }

  Future<List<Map<String, dynamic>>> _getSourceActivities() async {
    final startDate = activityStartDate;
    switch (_dataSource) {
      case 'onelap':
        return await _onelapManager.getActivities(startDate: startDate);
      case 'igp':
        return await _igpManager.getActivities(startDate: startDate);
      case 'xingzhe':
        return await _xingzheManager.getActivities();
      case 'garmin':
        return await _garminManager.getActivities();
      default:
        throw Exception('不支持的数据源: $_dataSource');
    }
  }

  Future<Uint8List> _downloadSourceFit(Map<String, dynamic> activity) async {
    switch (_dataSource) {
      case 'onelap':
        final fileKey = activity['fileKey'];
        if (fileKey == null) throw Exception('活动无fileKey');
        return await _onelapManager.downloadFit(fileKey);
      case 'igp':
        final url = activity['downloadUrl'];
        if (url == null) throw Exception('活动无downloadUrl');
        return await _igpManager.downloadFit(url);
      case 'xingzhe':
        final fitUrl = activity['fit_url'] ?? activity['fitUrl'];
        if (fitUrl != null) return await _xingzheManager.downloadFit(fitUrl);
        throw Exception('活动无下载链接');
      case 'garmin':
        final id = activity['id'];
        if (id == null) throw Exception('活动无ID');
        return await _garminManager.downloadFit(id);
      default:
        throw Exception('不支持的数据源');
    }
  }

  String _buildFileName(Map<String, dynamic> activity, {Uint8List? fitBytes}) {
    String ts;
    final startTime = activity['startTime'] ?? activity['start_time'] ?? '';
    if (startTime.length >= 19) {
      ts = startTime
          .substring(0, 19)
          .replaceAll(':', '')
          .replaceAll('-', '')
          .replaceAll('T', '');
    } else if (startTime.length >= 10) {
      ts = startTime.substring(0, 10).replaceAll('-', '');
    } else {
      final now = DateTime.now();
      ts =
          '${now.year}${_pad2(now.month)}${_pad2(now.day)}${_pad2(now.hour)}${_pad2(now.minute)}';
    }

    if (fitBytes != null) {
      try {
        final data = FitAnalyzer.analyze(fitBytes);
        final title = FitAnalyzer.buildTitle(data);
        if (title.isNotEmpty) return '$title-$ts.fit';
      } catch (_) {}
    }
    return 'ridesync_$ts.fit';
  }

  /// 行者/EdgeRide 不支持中文文件名，转成英文
  static const _asciiPlatforms = {'xingzhe', 'edge_ride'};
  String _fileNameForPlatform(
    String fileName,
    String platform,
    Uint8List fitBytes,
  ) {
    if (!_asciiPlatforms.contains(platform)) return fileName;
    try {
      final data = FitAnalyzer.analyze(fitBytes);
      final ts = _extractTimestampForFileName(fileName);
      final title = _sanitizeAsciiFileBaseName(
        FitAnalyzer.buildTitleAscii(data),
      );
      final baseName = title.isNotEmpty ? title : 'ridesync';
      final suffix = ts.isNotEmpty ? '-$ts' : '';
      return '$baseName$suffix.fit';
    } catch (_) {}
    return _sanitizeAsciiFileName(fileName);
  }

  String _extractTimestampForFileName(String fileName) {
    final baseName = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final match = RegExp(r'(\d{8,14})').firstMatch(baseName);
    return match?.group(1) ?? '';
  }

  String _sanitizeAsciiFileName(String fileName) {
    final name = _sanitizeAsciiFileBaseName(fileName);
    return '${name.isNotEmpty ? name : "ridesync"}.fit';
  }

  String _sanitizeAsciiFileBaseName(String fileName) {
    var name = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  // 并行上传到所有已登录且已启用的平台（排除数据源）
  Future<void> uploadToAllPlatforms(
    Uint8List fitBytes,
    String fileName, {
    String? activityId,
  }) async {
    // 如果没有 activityId，直接上传所有平台（兼容旧逻辑）
    if (activityId == null) {
      await _uploadToAllPlatformsLegacy(fitBytes, fileName);
      return;
    }

    // 获取需要同步的平台列表
    final enabledPlatforms = _getEnabledPlatforms();
    final platformsToSync = _forceSync
        ? enabledPlatforms
        : _syncRecordManager.getPlatformsToSync(activityId, enabledPlatforms);

    if (platformsToSync.isEmpty) {
      _logManager.addLog('所有平台已同步，跳过上传');
      return;
    }

    // 并行上传到所有平台（每个平台独立纠偏方向）
    final futures = <Future<({String platform, bool success, String? error})>>[];
    for (var platform in platformsToSync) {
      futures.add(_uploadToOnePlatform(fitBytes, fileName, platform, activityId));
    }
    final results = await Future.wait(futures);

    // 批量记录同步状态（内存中记录，活动完成后统一保存）
    var failCount = 0;
    for (var r in results) {
      if (r.success) {
        await _syncRecordManager.recordSuccess(
          activityId,
          r.platform,
          activityName: fileName,
          saveImmediately: false,
        );
      } else {
        failCount++;
        await _syncRecordManager.recordFailure(
          activityId,
          r.platform,
          r.error ?? '上传失败',
          activityName: fileName,
          saveImmediately: false,
        );
      }
    }

    // 统计结果
    final successCount = results.length - failCount;
    if (successCount == 0 && results.isNotEmpty) {
      // 即使全部失败也先保存记录再抛异常
      await _syncRecordManager.flush();
      throw Exception('所有目标平台上传均失败');
    } else if (failCount > 0) {
      _logManager.addLog(
        '部分平台上传失败: $successCount/${results.length} 成功, $failCount 失败',
      );
    }
  }

  /// 上传到单个平台，返回结果
  Future<({String platform, bool success, String? error})> _uploadToOnePlatform(
    Uint8List fitBytes,
    String fileName,
    String platform,
    String activityId,
  ) async {
    try {
      final corrected = await _maybeCorrect(fitBytes, fileName, platform);
      bool success = false;
      switch (platform) {
        case 'strava':
          success = await _uploadToStrava(
            corrected,
            fileName,
            externalId: activityId,
          );
          break;
        case 'igp':
          success = await _uploadToIgp(corrected, fileName);
          break;
        case 'xingzhe':
          success = await _uploadToXingzhe(corrected, fileName);
          break;
        case 'giant':
          success = await _uploadToGiant(corrected, fileName);
          break;
        case 'garmin':
          success = await _uploadToGarmin(corrected, fileName);
          break;
        case 'edge_ride':
          success = await _uploadToEdgeRide(corrected, fileName);
          break;
        case 'onelap':
          success = await _uploadToOnelap(corrected, fileName);
          break;
        default:
          return (platform: platform, success: false, error: '不支持的平台: $platform');
      }
      return (platform: platform, success: success, error: null);
    } catch (e) {
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      _logManager.addLog('上传到 $platform 失败: $e', isError: true);
      return (platform: platform, success: false, error: errMsg);
    }
  }

  // 兼容旧逻辑的上传方法
  Future<void> _uploadToAllPlatformsLegacy(
    Uint8List fitBytes,
    String fileName,
  ) async {
    final futures = <Future<bool>>[];

    // 顽鹿（数据源不能是onelap）
    if (_dataSource != 'onelap' && _enableOnelap && _onelapManager.isLoggedIn) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'onelap',
        ).then((b) => _uploadToOnelap(b, fileName)),
      );
    }

    // Strava（数据源不能是strava）
    if (_dataSource != 'strava' &&
        _enableStrava &&
        _stravaManager.isAuthenticated) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'strava',
        ).then((b) => _uploadToStrava(b, fileName)),
      );
    }

    // iGPSPORT（数据源不能是igp）
    if (_dataSource != 'igp' && _enableIgp && _igpManager.isLoggedIn) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'igp',
        ).then((b) => _uploadToIgp(b, fileName)),
      );
    }

    // 行者（数据源不能是xingzhe）
    if (_dataSource != 'xingzhe' &&
        _enableXingzhe &&
        _xingzheManager.isLoggedIn) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'xingzhe',
        ).then((b) => _uploadToXingzhe(b, fileName)),
      );
    }

    // 捷安特
    if (_dataSource != 'giant' && _enableGiant && _giantManager.isLoggedIn) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'giant',
        ).then((b) => _uploadToGiant(b, fileName)),
      );
    }

    // 佳明
    if (_dataSource != 'garmin' && _enableGarmin && _garminManager.isLoggedIn) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'garmin',
        ).then((b) => _uploadToGarmin(b, fileName)),
      );
    }

    // EdgeRide
    if (_dataSource != 'edge_ride' &&
        _enableEdgeRide &&
        _edgeRideManager.isLoggedIn) {
      futures.add(
        _maybeCorrect(
          fitBytes,
          fileName,
          'edge_ride',
        ).then((b) => _uploadToEdgeRide(b, fileName)),
      );
    }

    if (futures.isEmpty) return;

    final results = await Future.wait(futures);
    final failCount = results.where((r) => !r).length;
    final successCount = results.length - failCount;
    if (successCount == 0) {
      throw Exception('所有目标平台上传均失败');
    } else if (failCount > 0) {
      _logManager.addLog(
        '部分平台上传失败: $successCount/${results.length} 成功, $failCount 失败',
      );
    }
  }

  // 公共方法：获取数据源活动列表
  Future<List<Map<String, dynamic>>> getDataSourceActivities() async {
    return await _getSourceActivities();
  }

  // 公共方法：下载数据源的 fit 文件
  Future<Uint8List> downloadSourceFit(Map<String, dynamic> activity) async {
    return await _downloadSourceFit(activity);
  }

  // 公共方法：构建文件名
  String buildFileName(Map<String, dynamic> activity) {
    return _buildFileName(activity);
  }

  // 获取最新的 FIT 文件（带缓存）
  Future<Map<String, dynamic>?> getLatestFitFile() async {
    try {
      // 如果有缓存且不超过30分钟，直接返回
      if (hasCachedFit && _cachedTime != null) {
        final diff = DateTime.now().difference(_cachedTime!);
        if (diff.inMinutes < 30) {
          _logManager.addLog('使用缓存的FIT文件: $_cachedFileName');
          return {
            'fitBytes': _cachedFitBytes,
            'fileName': _cachedFileName,
            'activity': _cachedActivity,
            'fromCache': true,
          };
        }
      }

      // 去数据源拉取最新活动
      _logManager.addLog('从数据源获取最新活动...');
      final activities = await _getSourceActivities();
      if (activities.isEmpty) {
        _logManager.addLog('没有新活动');
        return null;
      }

      // 取最新的一个活动
      final latestActivity = activities.first;

      // 下载 FIT 文件
      final fitBytes = await _downloadSourceFit(latestActivity);
      final fileName = _buildFileName(latestActivity, fitBytes: fitBytes);

      // 更新缓存
      _cachedFitBytes = fitBytes;
      _cachedFileName = fileName;
      _cachedActivity = latestActivity;
      _cachedTime = DateTime.now();

      _logManager.addLog('FIT文件下载完成，已缓存');

      return {
        'fitBytes': fitBytes,
        'fileName': fileName,
        'activity': latestActivity,
        'fromCache': false,
      };
    } catch (e) {
      _logManager.addLog('获取最新FIT文件失败: $e', isError: true);
      return null;
    }
  }

  // 清除缓存
  void clearCache() {
    _cachedFitBytes = null;
    _cachedFileName = null;
    _cachedActivity = null;
    _cachedTime = null;
  }

  // 公共方法：上传到单个平台
  Future<void> uploadToSinglePlatform(
    String platform,
    Uint8List fitBytes,
    String fileName,
  ) async {
    final corrected = await _maybeCorrect(fitBytes, fileName, platform);
    switch (platform) {
      case 'onelap':
        await _uploadToOnelap(corrected, fileName);
        break;
      case 'strava':
        await _uploadToStrava(corrected, fileName, externalId: fileName);
        break;
      case 'igp':
        await _uploadToIgp(corrected, fileName);
        break;
      case 'xingzhe':
        await _uploadToXingzhe(corrected, fileName);
        break;
      case 'giant':
        await _uploadToGiant(corrected, fileName);
        break;
      case 'garmin':
        await _uploadToGarmin(corrected, fileName);
        break;
      case 'edge_ride':
        await _uploadToEdgeRide(corrected, fileName);
        break;
      default:
        throw Exception('不支持的平台: $platform');
    }
  }

  Future<bool> _uploadToOnelap(Uint8List fitBytes, String fileName) async {
    try {
      await _onelapManager.uploadFitFile(fitBytes, fileName);
      return true;
    } catch (e) {
      _logManager.addLog('上传顽鹿失败: $e', isError: true);
      return false;
    }
  }

  Future<bool> _uploadToStrava(
    Uint8List fitBytes,
    String fileName, {
    String? externalId,
  }) async {
    try {
      // Strava name 始终使用智能标题，description 根据开关决定
      String? activityName;
      String? description;
      try {
        final data = FitAnalyzer.analyze(fitBytes);
        activityName = FitAnalyzer.buildTitle(data);
        if (_enableActivityDescription) {
          description = FitAnalyzer.buildDescription(data);
        }
      } catch (e) {
        _logManager.addLog('活动分析失败: $e', isError: true);
      }
      await _stravaManager.uploadFitFile(
        fitBytes,
        fileName,
        externalId: externalId,
        activityName: activityName,
        description: description,
      );
      return true;
    } catch (e) {
      _logManager.addLog('Strava上传失败: $e', isError: true);
      return false;
    }
  }

  Future<bool> _uploadToIgp(Uint8List fitBytes, String fileName) async {
    try {
      await _igpManager.uploadFitFile(fitBytes, fileName);
      _logManager.addLog('iGPSPORT上传成功: $fileName');
      return true;
    } catch (e) {
      _logManager.addLog('iGPSPORT上传失败: $e', isError: true);
      return false;
    }
  }

  Future<bool> _uploadToXingzhe(Uint8List fitBytes, String fileName) async {
    try {
      final name = _fileNameForPlatform(fileName, 'xingzhe', fitBytes);
      await _xingzheManager.uploadFitFile(fitBytes, name);
      _logManager.addLog('行者上传成功: $fileName');
      return true;
    } catch (e) {
      _logManager.addLog('行者上传失败: $e', isError: true);
      return false;
    }
  }

  Future<bool> _uploadToGiant(Uint8List fitBytes, String fileName) async {
    try {
      await _giantManager.uploadFitFile(fitBytes, fileName);
      _logManager.addLog('捷安特上传成功: $fileName');
      return true;
    } catch (e) {
      _logManager.addLog('捷安特上传失败: $e', isError: true);
      return false;
    }
  }

  Future<bool> _uploadToGarmin(Uint8List fitBytes, String fileName) async {
    try {
      await _garminManager.uploadFitFile(fitBytes, fileName);
      _logManager.addLog('佳明上传成功: $fileName');
      return true;
    } catch (e) {
      _logManager.addLog('佳明上传失败: $e', isError: true);
      return false;
    }
  }

  Future<bool> _uploadToEdgeRide(Uint8List fitBytes, String fileName) async {
    try {
      final name = _fileNameForPlatform(fileName, 'edge_ride', fitBytes);
      await _edgeRideManager.uploadFitFile(fitBytes, name);
      _logManager.addLog('EdgeRide上传成功: $fileName');
      return true;
    } catch (e) {
      _logManager.addLog('EdgeRide上传失败: $e', isError: true);
      return false;
    }
  }

  // Debug: 保存文件到应用文档目录
  Future<void> _saveDebugFile(
    Uint8List bytes,
    String prefix,
    String fileName,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final debugDir = Directory('${dir.path}/debug_fit');
      if (!await debugDir.exists()) {
        await debugDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final baseName = fileName
          .replaceAll('.fit', '')
          .replaceAll('.gpx', '')
          .replaceAll('.tcx', '');
      final ext = fileName.split('.').last;
      final savePath = '${debugDir.path}/${prefix}_${baseName}_$timestamp.$ext';

      final file = File(savePath);
      await file.writeAsBytes(bytes);

      _logManager.addLog('[Debug] 已保存$prefix文件: $savePath');
    } catch (e) {
      _logManager.addLog('[Debug] 保存文件失败: $e', isError: true);
    }
  }

  /// 清除所有同步记录
  Future<void> clearSyncRecords() async {
    await _syncRecordManager.clearAllRecords();
    _logManager.addLog('已清除所有同步记录');
    notifyListeners();
  }

  /// 获取同步记录数量
  int get syncRecordCount => _syncRecordManager.recordCount;

  // 获取各平台管理器
  OneLapManager get onelapManager => _onelapManager;
  StravaManager get stravaManager => _stravaManager;
  IGPManager get igpManager => _igpManager;
  XingzheManager get xingzheManager => _xingzheManager;
  GiantManager get giantManager => _giantManager;
  GarminManager get garminManager => _garminManager;
  EdgeRideManager get edgeRideManager => _edgeRideManager;
}
