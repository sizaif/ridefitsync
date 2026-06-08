import 'package:flutter/material.dart';
import '../sync_hub.dart';
import '../app_storage.dart';
import '../l10n/strings.dart';
import 'sync_records_page.dart';

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
  bool _activityDesc = true;
  bool _forceSync = false;
  int _syncInterval = 120;
  String _timeRange = 'all';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final forceSync = await _storage.readBoolPrefs(key: 'force_sync', defaultValue: false);
    final activityDesc = await _storage.readBoolPrefs(key: 'activity_description', defaultValue: true);
    setState(() {
      _autoSync = _syncHub.autoSyncEnabled;
      _activityDesc = activityDesc;
      _forceSync = forceSync;
      _syncInterval = _syncHub.syncIntervalMinutes;
      _timeRange = _syncHub.activityTimeRange;
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
                _activityDesc ? Icons.analytics : Icons.analytics_outlined,
                color: _orange,
              ),
              title: const Text('数据分析描述'),
              subtitle: const Text('上传 Strava 时自动生成运动数据分析描述'),
              value: _activityDesc,
              onChanged: (value) {
                setState(() => _activityDesc = value);
                _syncHub.setEnableActivityDescription(value);
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
            child: ListTile(
              leading: const Icon(Icons.date_range_outlined, color: _orange),
              title: const Text('活动时间范围'),
              subtitle: Text(_timeRangeLabel(_timeRange)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTimeRangePicker(context),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SyncRecordsPage()),
              ),
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

  String _timeRangeLabel(String range) {
    switch (range) {
      case 'today': return '今天';
      case '3days': return '近 3 天';
      case 'week': return '近一周';
      case 'month': return '近一个月';
      default: return '全部活动';
    }
  }

  void _showTimeRangePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('活动时间范围'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            {'value': 'all', 'label': '全部活动'},
            {'value': 'today', 'label': '今天'},
            {'value': '3days', 'label': '近 3 天'},
            {'value': 'week', 'label': '近一周'},
            {'value': 'month', 'label': '近一个月'},
          ].map((item) {
            return RadioListTile<String>(
              title: Text(item['label']!),
              value: item['value']!,
              groupValue: _timeRange,
              activeColor: _orange,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _timeRange = v);
                  _syncHub.setActivityTimeRange(v);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

}
