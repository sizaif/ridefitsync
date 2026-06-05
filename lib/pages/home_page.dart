import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_handler/share_handler.dart';
import 'package:app_links/app_links.dart';
import '../sync_hub.dart';
import '../log_manager.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'shared_file_page.dart';
import 'settings_page.dart';
import 'login_pages/onelap_login.dart';
import 'login_pages/strava_login.dart';
import 'login_pages/igp_login.dart';
import 'login_pages/xingzhe_login.dart';
import 'login_pages/giant_login.dart';
import 'login_pages/garmin_login.dart';
import 'login_pages/edge_ride_login.dart';

const _orange = Color(0xFFFC4C02);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _syncHub = SyncHub();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription? _intentSub;
  StreamSubscription? _linkSub;

  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _syncHub.addListener(_onSyncStateChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initSharingIntent();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _syncHub.removeListener(_onSyncStateChanged);
    _pulseController.dispose();
    _intentSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  void _onSyncStateChanged() {
    if (mounted) setState(() {});
  }

  // === 分享接收 ===

  void _initSharingIntent() {
    final handler = ShareHandler.instance;
    _intentSub = handler.sharedMediaStream.listen(
      (media) => _handleSharedMedia(media),
      onError: (e) => LogManager().addLog('分享接收错误: $e', isError: true),
    );
    handler.getInitialSharedMedia().then((media) {
      if (media != null) _handleSharedMedia(media);
    });
  }

  void _handleSharedMedia(SharedMedia media) {
    final attachments = media.attachments;
    if (attachments == null || attachments.isEmpty) {
      LogManager().addLog('没有收到文件', isError: true);
      return;
    }
    for (final attachment in attachments) {
      if (attachment == null) continue;
      final path = attachment.path;
      final ext = path.split('.').last.toLowerCase();
      if (['fit', 'gpx', 'tcx'].contains(ext)) {
        _navigateToUpload(filePath: path);
        return;
      }
    }
    LogManager().addLog('收到的文件格式不支持', isError: true);
  }

  // === Deep Links ===

  void _initDeepLinks() {
    try {
      final appLinks = AppLinks();
      _linkSub = appLinks.uriLinkStream.listen((uri) {
        if (uri.scheme == 'stravaauto') {
          _handleStravaCallback(uri);
        } else if (uri.scheme == 'file') {
          final ext = uri.path.split('.').last.toLowerCase();
          if (['fit', 'gpx', 'tcx'].contains(ext)) {
            _navigateToUpload(filePath: uri.path);
          }
        }
      });
    } catch (e) {
      LogManager().addLog('Deep link 初始化失败: $e', isError: true);
    }
  }

  Future<void> _handleStravaCallback(Uri uri) async {
    try {
      final success = await _syncHub.stravaManager.handleAuthCallback(uri);
      if (success && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.current.stravaAuthSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      LogManager().addLog('Strava 授权回调失败: $e', isError: true);
    }
  }

  // === 文件选择 ===

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        // 检查文件扩展名
        final ext = file.name.split('.').last.toLowerCase();
        if (!['fit', 'gpx', 'tcx'].contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.current.onlyFitGpxTcx)),
            );
          }
          return;
        }
        if (file.bytes != null) {
          _navigateToUpload(fileBytes: file.bytes!, fileName: file.name);
        } else if (file.path != null) {
          _navigateToUpload(filePath: file.path!);
        }
      }
    } catch (e) {
      LogManager().addLog('文件选择失败: $e', isError: true);
    }
  }

  void _navigateToUpload({String? filePath, Uint8List? fileBytes, String? fileName}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SharedFilePage(
          filePath: filePath,
          fileBytes: fileBytes,
          fileName: fileName,
        ),
      ),
    );
  }

  // === 同步 ===

  Future<void> _startSync() async {
    await _syncHub.sync();
    if (mounted) {
      final success = _syncHub.syncedCount;
      final failed = _syncHub.failedCount;
      if (success > 0 || failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.syncComplete(success, failed))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.noNewActivities)),
        );
      }
    }
  }

  // === 日志 ===

  void _showLogSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const LogBottomSheet(),
    );
  }

  // === 登录 ===

  Future<void> _openLogin(String platform) async {
    Widget page;
    switch (platform) {
      case 'onelap':
        page = const OneLapLoginPage();
        break;
      case 'strava':
        page = const StravaLoginPage();
        break;
      case 'igp':
        page = const IGPLoginPage();
        break;
      case 'xingzhe':
        page = const XingzheLoginPage();
        break;
      case 'giant':
        page = const GiantLoginPage();
        break;
      case 'garmin':
        page = const GarminLoginPage();
        break;
      case 'edge_ride':
        page = const EdgeRideLoginPage();
        break;
      default:
        return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (result == true && mounted) setState(() {});
  }

  // === 登出 ===

  Future<void> _logoutPlatform(String platform, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.current.logoutTitle(name)),
        content: Text(S.current.logoutConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.current.logout, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    switch (platform) {
      case 'strava':
        await _syncHub.stravaManager.logout();
        break;
      case 'igp':
        await _syncHub.igpManager.logout();
        break;
      case 'xingzhe':
        await _syncHub.xingzheManager.logout();
        break;
      case 'giant':
        await _syncHub.giantManager.logout();
        break;
      case 'garmin':
        await _syncHub.garminManager.logout();
        break;
      case 'edge_ride':
        await _syncHub.edgeRideManager.logout();
        break;
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.loggedOut(name))),
      );
    }
  }

  // === UI ===

  int get _connectedCount {
    int count = 0;
    if (_syncHub.onelapLoggedIn) count++;
    if (_syncHub.stravaLoggedIn) count++;
    if (_syncHub.igpLoggedIn) count++;
    if (_syncHub.xingzheLoggedIn) count++;
    if (_syncHub.giantLoggedIn) count++;
    if (_syncHub.edgeRideLoggedIn) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 50,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(theme),
                      const SizedBox(height: 24),
                      _buildThirdPartyActionList(theme),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 180),
                          child: _isUploading
                              ? _buildUploadProgressOverlay(theme)
                              : _buildUploadDropTarget(theme),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- 状态卡 ---

  Widget _buildStatusCard(ThemeData theme) {
    final canSync = _syncHub.canSync;
    final isSyncing = _syncHub.isSyncing;
    final connected = _connectedCount;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: canSync
              ? [const Color(0xFFFC4C02), const Color(0xFFFF8243)]
              : [theme.cardColor, theme.cardColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: canSync
                ? const Color(0xFFFC4C02).withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSyncing
                  ? Icons.sync_rounded
                  : (canSync ? Icons.sync_rounded : Icons.sync_disabled_rounded),
              color: canSync ? Colors.white : theme.iconTheme.color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSyncing
                      ? S.current.syncing
                      : (canSync ? S.current.ready : S.current.notReady),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: canSync ? Colors.white : theme.textTheme.titleMedium?.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isSyncing
                      ? S.current.syncingActivities(_syncHub.syncedCount)
                      : S.current.platformsConnected(connected),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: canSync
                        ? Colors.white.withOpacity(0.9)
                        : theme.hintColor,
                  ),
                ),
              ],
            ),
          ),
          // 同步按钮（始终显示）
          IconButton(
            icon: isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.play_arrow_rounded,
                    color: canSync ? Colors.white : Colors.white.withOpacity(0.3),
                  ),
            tooltip: isSyncing ? S.current.syncing : (canSync ? S.current.startSync : S.current.syncHint),
            onPressed: (isSyncing || !canSync) ? null : _startSync,
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            color: canSync ? Colors.white : theme.iconTheme.color,
            tooltip: S.current.runningLog,
            onPressed: _showLogSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            color: canSync ? Colors.white : theme.iconTheme.color,
            tooltip: S.current.settings,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0);
  }

  // --- 平台列表 ---

  Widget _buildThirdPartyActionList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 数据源平台
        _buildSectionLabel(theme, S.current.dataSourcePlatform),
        _buildDataSourceTile(theme),
        const SizedBox(height: 20),

        // 上传目标平台
        _buildSectionLabel(theme, S.current.uploadTargetPlatform),
        if (_syncHub.dataSource != 'strava' && _syncHub.enableStrava)
          _buildThirdPartyActionTile(
            theme,
            _PlatformInfo(
              letter: 'S',
              name: S.current.strava,
              subtitle: S.current.platformSubtitle('strava'),
              color: AppTheme.stravaColor,
              isLoggedIn: _syncHub.stravaLoggedIn,
              username: _syncHub.stravaManager.athleteName,
              platform: 'strava',
            ),
          ),
        if (_syncHub.dataSource != 'strava' && _syncHub.enableStrava) const SizedBox(height: 10),
        if (_syncHub.dataSource != 'igp' && _syncHub.enableIgp)
          _buildThirdPartyActionTile(
            theme,
            _PlatformInfo(
              letter: 'I',
              name: S.current.igpsport,
              subtitle: S.current.platformSubtitle('igp'),
              color: AppTheme.igpColor,
            isLoggedIn: _syncHub.igpLoggedIn,
            username: _syncHub.igpManager.username,
            platform: 'igp',
          ),
        ),
        if (_syncHub.dataSource != 'igp' && _syncHub.enableIgp) const SizedBox(height: 10),
        if (_syncHub.dataSource != 'xingzhe' && _syncHub.enableXingzhe)
          _buildThirdPartyActionTile(
            theme,
            _PlatformInfo(
              letter: 'X',
              name: S.current.xingzhe,
              subtitle: S.current.platformSubtitle('xingzhe'),
              color: AppTheme.xingzheColor,
              isLoggedIn: _syncHub.xingzheLoggedIn,
              username: _syncHub.xingzheManager.username,
              platform: 'xingzhe',
            ),
          ),
        if (_syncHub.dataSource != 'xingzhe' && _syncHub.enableXingzhe) const SizedBox(height: 10),
        if (_syncHub.enableGiant)
          _buildThirdPartyActionTile(
            theme,
            _PlatformInfo(
              letter: 'G',
              name: S.current.giant,
              subtitle: S.current.platformSubtitle('giant'),
              color: AppTheme.giantColor,
              isLoggedIn: _syncHub.giantLoggedIn,
              username: _syncHub.giantManager.username,
              platform: 'giant',
            ),
          ),
        if (_syncHub.enableGiant) const SizedBox(height: 10),
        if (_syncHub.dataSource != 'garmin' && _syncHub.enableGarmin) ...[
          const SizedBox(height: 10),
          _buildThirdPartyActionTile(
            theme,
            _PlatformInfo(
              letter: 'G',
              name: S.current.garmin,
              subtitle: S.current.platformSubtitle('garmin'),
              color: const Color(0xFF11AEED),
              isLoggedIn: _syncHub.garminLoggedIn,
              username: _syncHub.garminManager.username,
              platform: 'garmin',
            ),
          ),
        ],
        if (_syncHub.enableEdgeRide) ...[
          const SizedBox(height: 10),
          _buildThirdPartyActionTile(
            theme,
            _PlatformInfo(
              letter: 'E',
              name: S.current.edgeRide,
              subtitle: S.current.platformSubtitle('edge_ride'),
              color: const Color(0xFF00C853),
              isLoggedIn: _syncHub.edgeRideLoggedIn,
              username: _syncHub.edgeRideManager.username,
              platform: 'edge_ride',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDataSourceTile(ThemeData theme) {
    final source = _syncHub.dataSource;
    String letter, name, subtitle;
    Color color;
    bool isLoggedIn;
    String? username;

    switch (source) {
      case 'igp':
        letter = 'I';
        name = S.current.igpsport;
        subtitle = S.current.sourceCyclingLabel;
        color = const Color(0xFFFF3C1F);
        isLoggedIn = _syncHub.igpLoggedIn;
        username = _syncHub.igpManager.username;
        break;
      case 'xingzhe':
        letter = 'X';
        name = S.current.xingzhe;
        subtitle = S.current.sourceCyclingLabel;
        color = const Color(0xFF0155FF);
        isLoggedIn = _syncHub.xingzheLoggedIn;
        username = _syncHub.xingzheManager.username;
        break;
      case 'garmin':
        letter = 'G';
        name = S.current.garmin;
        subtitle = S.current.sourceCyclingRunLabel;
        color = const Color(0xFF11AEED);
        isLoggedIn = _syncHub.garminLoggedIn;
        username = _syncHub.garminManager.username;
        break;
      default:
        letter = 'W';
        name = S.current.onelap;
        subtitle = S.current.sourceCyclingLabel;
        color = AppTheme.onelapColor;
        isLoggedIn = _syncHub.onelapLoggedIn;
        username = _syncHub.onelapManager.username;
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _buildLetterIcon(letter: letter, color: color),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          isLoggedIn
              ? (username ?? S.current.connected)
              : '$subtitle · ${S.current.clickToLogin}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoggedIn)
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
            if (isLoggedIn) const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                S.current.dataSource,
                style: const TextStyle(
                  color: _orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        onTap: () {
          if (isLoggedIn) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          } else {
            _openLogin(source);
          }
        },
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05, end: 0);
  }

  Widget _buildSectionLabel(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildThirdPartyActionTile(ThemeData theme, _PlatformInfo info) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _buildLetterIcon(letter: info.letter, color: info.color),
        title: Text(info.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          info.isLoggedIn ? (info.username ?? S.current.connected) : info.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (info.isLoggedIn)
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
            if (info.isLoggedIn) const SizedBox(width: 8),
            // 单平台同步按钮
            if (info.isLoggedIn && _syncHub.isDataSourceLoggedIn)
              IconButton(
                icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                color: theme.colorScheme.primary,
                tooltip: '${S.current.syncToPlatform} ${info.name}',
                onPressed: () => _syncToSinglePlatform(info.platform),
              ),
            // 登出按钮
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              color: info.isLoggedIn
                  ? theme.colorScheme.error.withOpacity(0.6)
                  : theme.disabledColor,
              tooltip: info.isLoggedIn ? S.current.logoutTitle(info.name) : S.current.notLoggedIn,
              onPressed: info.isLoggedIn
                  ? () => _logoutPlatform(info.platform, info.name)
                  : null,
            ),
            if (!info.isLoggedIn)
              Icon(
                Icons.chevron_right,
                color: theme.iconTheme.color,
              ),
          ],
        ),
        onTap: info.isLoggedIn ? null : () => _openLogin(info.platform),
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05, end: 0);
  }

  String _platformDisplayName(String platform) {
    switch (platform) {
      case 'strava': return S.current.strava;
      case 'igp': return S.current.igpsport;
      case 'xingzhe': return S.current.xingzhe;
      case 'giant': return S.current.giant;
      case 'garmin': return S.current.garmin;
      case 'edge_ride': return S.current.edgeRide;
      default: return platform;
    }
  }

  // 同步到单个平台
  Future<void> _syncToSinglePlatform(String platform) async {
    if (_isUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.uploadingPleaseWait)),
      );
      return;
    }
    if (_syncHub.isSyncing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.syncingPleaseWait)),
      );
      return;
    }

    if (!_syncHub.isDataSourceLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.dataSourceNotLoggedIn)),
      );
      return;
    }

    setState(() => _isUploading = true);

    final displayName = _platformDisplayName(platform);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.current.syncingTo} $displayName...')),
      );

      // 获取最新 FIT 文件（带缓存）
      final result = await _syncHub.getLatestFitFile();
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.noNewActivities)),
        );
        return;
      }

      final fitBytes = result['fitBytes'] as Uint8List;
      final fileName = result['fileName'] as String;
      final fromCache = result['fromCache'] as bool;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fromCache ? '${S.current.usingCache} $fileName' : '${S.current.downloadComplete} $fileName')),
      );

      // 只上传到指定平台
      await _syncHub.uploadToSinglePlatform(platform, fitBytes, fileName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.syncSuccess(displayName, fileName)), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.current.syncFailed} $e')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Widget _buildLetterIcon({required String letter, required Color color}) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // --- 上传区域 ---

  Widget _buildUploadDropTarget(ThemeData theme) {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CustomPaint(
          painter: DashedBorderPainter(
            color: theme.dividerColor.withOpacity(0.5),
            strokeWidth: 2,
            gap: 10,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                S.current.selectFile,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                S.current.orShare,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Widget _buildUploadProgressOverlay(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFC4C02).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  size: 48,
                  color: Color(0xFFFC4C02),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              S.current.uploading,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformInfo {
  final String letter;
  final String name;
  final String subtitle;
  final Color color;
  final bool isLoggedIn;
  final String? username;
  final String platform;

  _PlatformInfo({
    required this.letter,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.isLoggedIn,
    this.username,
    required this.platform,
  });
}

/// 虚线边框画笔
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.gap = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(24),
        ),
      );

    final Path dashedPath = _dashPath(
      path,
      dashArray: CircularIntervalList<double>([10, gap]),
    );
    canvas.drawPath(dashedPath, paint);
  }

  Path _dashPath(Path source, {required CircularIntervalList<double> dashArray}) {
    final Path dest = Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = dashArray.next;
        if (draw) {
          dest.addPath(
            metric.extractPath(distance, distance + len),
            Offset.zero,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap;
  }
}

class CircularIntervalList<T> {
  final List<T> _values;
  int _index = 0;

  CircularIntervalList(this._values);

  T get next {
    if (_index >= _values.length) _index = 0;
    return _values[_index++];
  }
}

/// 日志底部弹出 Sheet
class LogBottomSheet extends StatefulWidget {
  const LogBottomSheet({super.key});

  @override
  State<LogBottomSheet> createState() => _LogBottomSheetState();
}

class _LogBottomSheetState extends State<LogBottomSheet> {
  final _logManager = LogManager();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _logManager.addListener(_onLogUpdate);
  }

  @override
  void dispose() {
    _logManager.removeListener(_onLogUpdate);
    super.dispose();
  }

  void _onLogUpdate() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);

    return Container(
      height: screenHeight * 0.6,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.article_outlined,
                        color: theme.iconTheme.color, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      S.current.runningLog,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _logManager.clearLogs(),
                  child: Text(S.current.clear),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: _logManager.logs.isEmpty
                ? Center(
                    child: Text(
                      S.current.noLogs,
                      style: TextStyle(color: theme.hintColor),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    itemCount: _logManager.logs.length,
                    itemBuilder: (context, index) {
                      final log = _logManager.logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              log.isError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              size: 14,
                              color: log.isError
                                  ? theme.colorScheme.error
                                  : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                log.toString(),
                                style: TextStyle(
                                  color: log.isError
                                      ? theme.colorScheme.error
                                      : theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.8),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
