import 'package:flutter/material.dart';
import '../sync_hub.dart';
import 'login_pages/onelap_login.dart';
import 'login_pages/strava_login.dart';
import 'login_pages/igp_login.dart';
import 'login_pages/xingzhe_login.dart';
import 'login_pages/giant_login.dart';
import 'login_pages/garmin_login.dart';
import 'login_pages/edge_ride_login.dart';
import 'sync_settings_page.dart';
import 'donate_page.dart';
import '../managers/locale_manager.dart';
import '../l10n/strings.dart';
import '../upgrader.dart';

const _orange = Color(0xFFFC4C02);

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _syncHub = SyncHub();
  final _localeManager = LocaleManager();

  @override
  void initState() {
    super.initState();
    _syncHub.addListener(_onSyncHubChanged);
    _localeManager.addListener(_onSyncHubChanged);
  }

  @override
  void dispose() {
    _syncHub.removeListener(_onSyncHubChanged);
    _localeManager.removeListener(_onSyncHubChanged);
    super.dispose();
  }

  void _onSyncHubChanged() {
    setState(() {});
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.current.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === 数据源平台 ===
          _buildSectionHeader(theme, S.current.dataSourcePlatform),
          _buildDataSourceTile(
            theme,
            letter: 'W',
            color: const Color(0xFF0155FF),
            title: S.current.onelap,
            subtitle: S.current.cyclingActivities,
            platform: 'onelap',
            isLoggedIn: _syncHub.onelapLoggedIn,
            username: _syncHub.onelapManager.username,
          ),
          const SizedBox(height: 10),
          _buildDataSourceTile(
            theme,
            letter: 'I',
            color: const Color(0xFFFF3C1F),
            title: S.current.igpsport,
            subtitle: S.current.cyclingActivities,
            platform: 'igp',
            isLoggedIn: _syncHub.igpLoggedIn,
            username: _syncHub.igpManager.username,
          ),
          const SizedBox(height: 10),
          _buildDataSourceTile(
            theme,
            letter: 'X',
            color: const Color(0xFF0155FF),
            title: S.current.xingzhe,
            subtitle: S.current.cyclingActivities,
            platform: 'xingzhe',
            isLoggedIn: _syncHub.xingzheLoggedIn,
            username: _syncHub.xingzheManager.username,
          ),
          const SizedBox(height: 10),
          _buildDataSourceTile(
            theme,
            letter: 'G',
            color: const Color(0xFF11AEED),
            title: S.current.garmin,
            subtitle: S.current.cyclingRunActivities,
            platform: 'garmin',
            isLoggedIn: _syncHub.garminLoggedIn,
            username: _syncHub.garminManager.username,
          ),
          const SizedBox(height: 24),

          // === 上传目标平台 ===
          _buildSectionHeader(theme, S.current.uploadTargetPlatform),
          _buildUploadTargetTile(
            theme,
            letter: 'S',
            color: _orange,
            title: S.current.strava,
            subtitle: S.current.platformSubtitle('strava'),
            platform: 'strava',
            isLoggedIn: _syncHub.stravaLoggedIn,
            username: _syncHub.stravaManager.athleteName,
            isEnabled: _syncHub.enableStrava,
            onToggle: (v) => _syncHub.setEnableStrava(v),
            isSource: _syncHub.dataSource == 'strava',
          ),
          const SizedBox(height: 10),
          _buildUploadTargetTile(
            theme,
            letter: 'I',
            color: const Color(0xFFFF3C1F),
            title: S.current.igpsport,
            subtitle: S.current.platformSubtitle('igp'),
            platform: 'igp',
            isLoggedIn: _syncHub.igpLoggedIn,
            username: _syncHub.igpManager.username,
            isEnabled: _syncHub.enableIgp,
            onToggle: (v) => _syncHub.setEnableIgp(v),
            isSource: _syncHub.dataSource == 'igp',
          ),
          const SizedBox(height: 10),
          _buildUploadTargetTile(
            theme,
            letter: 'X',
            color: const Color(0xFF0155FF),
            title: S.current.xingzhe,
            subtitle: S.current.platformSubtitle('xingzhe'),
            platform: 'xingzhe',
            isLoggedIn: _syncHub.xingzheLoggedIn,
            username: _syncHub.xingzheManager.username,
            isEnabled: _syncHub.enableXingzhe,
            onToggle: (v) => _syncHub.setEnableXingzhe(v),
            isSource: _syncHub.dataSource == 'xingzhe',
          ),
          const SizedBox(height: 10),
          _buildUploadTargetTile(
            theme,
            letter: 'G',
            color: const Color(0xFFFF9800),
            title: S.current.giant,
            subtitle: S.current.platformSubtitle('giant'),
            platform: 'giant',
            isLoggedIn: _syncHub.giantLoggedIn,
            username: _syncHub.giantManager.username,
            isEnabled: _syncHub.enableGiant,
            onToggle: (v) => _syncHub.setEnableGiant(v),
            isSource: _syncHub.dataSource == 'giant',
          ),
          const SizedBox(height: 10),
          _buildUploadTargetTile(
            theme,
            letter: 'G',
            color: const Color(0xFF11AEED),
            title: S.current.garmin,
            subtitle: S.current.platformSubtitle('garmin'),
            platform: 'garmin',
            isLoggedIn: _syncHub.garminLoggedIn,
            username: _syncHub.garminManager.username,
            isEnabled: _syncHub.enableGarmin,
            onToggle: (v) => _syncHub.setEnableGarmin(v),
            isSource: _syncHub.dataSource == 'garmin',
          ),
          const SizedBox(height: 10),
          _buildUploadTargetTile(
            theme,
            letter: 'E',
            color: const Color(0xFF00C853),
            title: S.current.edgeRide,
            subtitle: S.current.edgeRideSubtitle,
            platform: 'edge_ride',
            isLoggedIn: _syncHub.edgeRideLoggedIn,
            username: _syncHub.edgeRideManager.username,
            isEnabled: _syncHub.enableEdgeRide,
            onToggle: (v) => _syncHub.setEnableEdgeRide(v),
            isSource: _syncHub.dataSource == 'edge_ride',
          ),
          const SizedBox(height: 24),

          // === 同步设置 ===
          _buildSectionHeader(theme, S.current.syncSettings),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.tune_rounded, color: _orange),
              title: Text(S.current.detailedSyncSettings),
              subtitle: Text(S.current.coordFixDesc),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SyncSettingsPage()),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // === 语言 ===
          _buildSectionHeader(theme, S.current.language),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: _orange),
                  title: Text(S.current.chinese),
                  trailing: _localeManager.isZh
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                      : null,
                  onTap: () => _localeManager.setLocale(true),
                ),
                Divider(height: 1, color: theme.dividerColor),
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: _orange),
                  title: Text(S.current.english),
                  trailing: !_localeManager.isZh
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                      : null,
                  onTap: () => _localeManager.setLocale(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // === 关于 ===
          _buildSectionHeader(theme, S.current.about),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: _orange),
                  title: Text(S.current.version),
                  trailing: Text(AppUpgrader.currentVersion),
                  onTap: () => AppUpgrader.checkUpgrade(context),
                ),
                Divider(height: 1, color: theme.dividerColor),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: _orange),
                  title: Text(S.current.clearCache),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _syncHub.clearCache();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(S.current.cacheCleared)),
                    );
                  },
                ),
                Divider(height: 1, color: theme.dividerColor),
                ListTile(
                  leading: const Icon(Icons.favorite_rounded, color: Colors.red),
                  title: Text(S.current.donate),
                  subtitle: Text(S.current.supportDev),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DonatePage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 分栏标题 ---

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
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

  // --- 数据源选择（Switch，同时只能选一个） ---

  Widget _buildDataSourceTile(
    ThemeData theme, {
    required String letter,
    required Color color,
    required String title,
    required String subtitle,
    required String platform,
    required bool isLoggedIn,
    String? username,
  }) {
    final isSelected = _syncHub.dataSource == platform;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: _buildLetterIcon(letter: letter, color: color),
        title: Text(title),
        subtitle: Text(
          isSelected
              ? (isLoggedIn ? (username ?? S.current.currentDataSource) : '${S.current.currentDataSource} · ${S.current.clickToLogin}')
              : (isLoggedIn ? (username ?? S.current.connected) : '$subtitle · ${S.current.needLoginFirst}'),
        ),
        trailing: Switch(
          value: isSelected,
          onChanged: (value) async {
            if (value) {
              _setDataSourceWithLogin(platform);
            }
          },
        ),
        onTap: () {
          if (isLoggedIn) {
            // 已登录，切换数据源
            _syncHub.setDataSource(platform);
          } else {
            // 未登录，跳转登录
            _openLogin(platform);
          }
        },
      ),
    );
  }

  Future<void> _setDataSourceWithLogin(String platform) async {
    bool isLoggedIn = false;
    switch (platform) {
      case 'onelap':
        isLoggedIn = _syncHub.onelapLoggedIn;
        break;
      case 'igp':
        isLoggedIn = _syncHub.igpLoggedIn;
        break;
      case 'xingzhe':
        isLoggedIn = _syncHub.xingzheLoggedIn;
        break;
      case 'garmin':
        isLoggedIn = _syncHub.garminLoggedIn;
        break;
    }
    if (!isLoggedIn) {
      await _openLogin(platform);
      if (!mounted) return;
      // 重新检查登录状态
      switch (platform) {
        case 'onelap':
          isLoggedIn = _syncHub.onelapLoggedIn;
          break;
        case 'igp':
          isLoggedIn = _syncHub.igpLoggedIn;
          break;
        case 'xingzhe':
          isLoggedIn = _syncHub.xingzheLoggedIn;
          break;
        case 'garmin':
          isLoggedIn = _syncHub.garminLoggedIn;
          break;
      }
    }
    if (isLoggedIn) {
      _syncHub.setDataSource(platform);
    }
  }

  // --- 上传目标（带开关） ---

  Widget _buildUploadTargetTile(
    ThemeData theme, {
    required String letter,
    required Color color,
    required String title,
    required String subtitle,
    required String platform,
    required bool isLoggedIn,
    String? username,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
    required bool isSource,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: _buildLetterIcon(letter: letter, color: color),
        title: Text(title),
        subtitle: Text(
          isSource
              ? S.current.cannotBeTarget
              : (isLoggedIn ? (username ?? S.current.connected) : '$subtitle · ${S.current.clickToLogin}'),
        ),
        trailing: isSource
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  S.current.dataSource,
                  style: TextStyle(
                    color: theme.hintColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : Switch(
                value: isEnabled,
                onChanged: onToggle,
              ),
        onTap: (isSource || isLoggedIn)
            ? null
            : () => _openLogin(platform),
      ),
    );
  }

  // --- 字母图标 ---

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
}
