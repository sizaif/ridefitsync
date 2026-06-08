import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../sync_hub.dart';
import '../app_storage.dart';
import '../theme/app_theme.dart';
import '../l10n/strings.dart';

const _orange = Color(0xFFFC4C02);

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _syncHub = SyncHub();
  final _storage = AppStorage();

  bool _autoSync = false;
  bool _fixCoordinates = true;
  bool _forceSync = false;
  int _syncInterval = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final fixCoords = await _storage.readBoolPrefs(key: 'fix_coordinates', defaultValue: true);
    final forceSync = await _storage.readBoolPrefs(key: 'force_sync', defaultValue: false);
    setState(() {
      _autoSync = _syncHub.autoSyncEnabled;
      _fixCoordinates = fixCoords;
      _forceSync = forceSync;
      _syncInterval = _syncHub.syncIntervalMinutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.current.detailedSyncSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === 同步选项 ===
          _buildSectionHeader(theme, '同步选项'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: const Icon(Icons.sync_rounded, color: _orange),
              title: const Text('自动同步'),
              subtitle: const Text('启动时自动同步新活动'),
              value: _autoSync,
              onChanged: (value) {
                setState(() => _autoSync = value);
                _syncHub.setAutoSync(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(
                _fixCoordinates ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: _orange,
              ),
              title: const Text('坐标纠偏'),
              subtitle: const Text('GCJ-02 → WGS-84 (中国坐标修正)'),
              value: _fixCoordinates,
              onChanged: (value) {
                setState(() => _fixCoordinates = value);
                _syncHub.setFixCoordinates(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.timer_outlined, color: _orange),
              title: const Text('同步间隔'),
              subtitle: Text('每 $_syncInterval 分钟'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showIntervalPicker(context),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(
                _forceSync ? Icons.sync_disabled : Icons.sync,
                color: _forceSync ? Colors.red : _orange,
              ),
              title: const Text('强制同步'),
              subtitle: const Text('忽略同步记录，强制重新同步所有活动'),
              value: _forceSync,
              onChanged: (value) {
                setState(() => _forceSync = value);
                _syncHub.setForceSync(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.orange),
              title: const Text('清除同步记录'),
              subtitle: Text('已记录 ${_syncHub.syncRecordCount} 条同步状态'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showClearRecordsDialog(context),
            ),
          ),
          const SizedBox(height: 24),

          // === 使用说明 ===
          _buildSectionHeader(theme, '使用说明'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline_rounded,
                          color: theme.hintColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '各平台登录说明',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildInstructionItem('顽鹿 OTM', '使用顽鹿App的账号密码'),
                  _buildInstructionItem('Strava', '需要创建应用获取 Client ID 和 Secret'),
                  _buildInstructionItem('iGPSPORT', '使用iGPSPORT账号密码'),
                  _buildInstructionItem('行者', '使用行者App的账号密码（自动RSA加密）'),
                  _buildInstructionItem('捷安特', '使用捷安特RideLife账号密码'),
                  _buildInstructionItem('佳明', '使用佳明中国账号（邮箱）登录'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildInstructionItem(String platform, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$platform: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: instruction,
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showIntervalPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('同步间隔'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [15, 30, 60, 120].map((value) {
            return RadioListTile<int>(
              title: Text('$value 分钟'),
              value: value,
              groupValue: _syncInterval,
              activeColor: _orange,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _syncInterval = v);
                  _syncHub.setSyncInterval(v);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showClearRecordsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除同步记录'),
        content: Text('确定要清除所有同步记录吗？\n\n'
            '当前共有 ${_syncHub.syncRecordCount} 条记录。\n'
            '清除后，所有活动将被重新同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _syncHub.clearSyncRecords();
              Navigator.pop(ctx);
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('同步记录已清除')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}
