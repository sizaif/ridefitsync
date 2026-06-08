import 'package:flutter/material.dart';
import '../sync_hub.dart';
import '../sync_record_manager.dart';
import '../l10n/strings.dart';

class SyncRecordsPage extends StatefulWidget {
  const SyncRecordsPage({super.key});

  @override
  State<SyncRecordsPage> createState() => _SyncRecordsPageState();
}

class _SyncRecordsPageState extends State<SyncRecordsPage> {
  final _syncHub = SyncHub();
  final _manager = SyncHub().syncRecordManager;

  Map<String, Map<String, SyncStatus>> get _records => _manager.allRecords;
  final _selected = <String>{};

  bool get _isAllSelected =>
      _records.isNotEmpty && _selected.length == _records.length;

  @override
  void initState() {
    super.initState();
    _syncHub.addListener(_onChanged);
  }

  @override
  void dispose() {
    _syncHub.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 $count 条同步记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.current.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (var id in _selected.toList()) {
      await _manager.clearActivityRecord(id);
    }
    _selected.clear();
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $count 条记录')),
      );
    }
  }

  Future<void> _deleteAll() async {
    if (_records.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部'),
        content: Text('确定要清除所有 ${_records.length} 条同步记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.current.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除全部', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _manager.clearAllRecords();
    _selected.clear();
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除所有同步记录')),
      );
    }
  }

  void _toggleAll() {
    setState(() {
      if (_isAllSelected) {
        _selected.clear();
      } else {
        _selected.addAll(_records.keys);
      }
    });
  }

  void _toggleOne(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  String _platformName(String platform) {
    switch (platform) {
      case 'onelap': return S.current.onelap;
      case 'strava': return S.current.strava;
      case 'igp': return S.current.igpsport;
      case 'xingzhe': return S.current.xingzhe;
      case 'giant': return S.current.giant;
      case 'garmin': return S.current.garmin;
      case 'edge_ride': return S.current.edgeRide;
      default: return platform;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = _records;

    return Scaffold(
      appBar: AppBar(
        title: Text('同步记录 (${records.length})'),
        actions: [
          if (records.isNotEmpty) ...[
            TextButton(
              onPressed: _toggleAll,
              child: Text(_isAllSelected ? '取消全选' : '全选'),
            ),
            if (_selected.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除选中',
                onPressed: _deleteSelected,
              ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清除全部',
              onPressed: _deleteAll,
            ),
          ],
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: theme.hintColor),
                  const SizedBox(height: 16),
                  Text('暂无同步记录', style: TextStyle(color: theme.hintColor, fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final entry = records.entries.elementAt(index);
                final activityId = entry.key;
                final platforms = entry.value;
                final isSelected = _selected.contains(activityId);

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _toggleOne(activityId),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Activity header: 数据源 + 活动名称
                          () {
                            final source = activityId.contains('_')
                                ? activityId.split('_').first
                                : '';
                            final name = platforms.values
                                .where((s) => s.activityName != null)
                                .map((s) => s.activityName!)
                                .firstOrNull ??
                                activityId;
                            return Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleOne(activityId),
                                visualDensity: VisualDensity.compact,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (source.isNotEmpty)
                                      Text(
                                        _platformName(source),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Text(
                                      name,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                tooltip: '删除此记录',
                                onPressed: () async {
                                  await _manager.clearActivityRecord(activityId);
                                  _selected.remove(activityId);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          );
                        }(),
                          Divider(height: 1, color: theme.dividerColor),
                          const SizedBox(height: 8),
                          // Platform status list
                          ...platforms.entries.map((pe) {
                            final platform = pe.key;
                            final status = pe.value;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        status.isSuccess ? Icons.check_circle : Icons.error_outline,
                                        size: 16,
                                        color: status.isSuccess ? Colors.green : Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_platformName(platform),
                                          style: const TextStyle(fontSize: 13)),
                                      const Spacer(),
                                      Text(
                                        _formatTime(status.timestamp),
                                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                                      ),
                                    ],
                                  ),
                                  if (!status.isSuccess && status.errorMessage != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 24, top: 2),
                                      child: Text(
                                        status.errorMessage!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.withOpacity(0.8),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
