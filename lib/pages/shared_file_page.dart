import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_animate/flutter_animate.dart';
import '../sync_hub.dart';
import '../log_manager.dart';
import '../coord_fixer.dart';
import '../theme/app_theme.dart';
import '../theme/glass_card.dart';

class SharedFilePage extends StatefulWidget {
  final String? filePath;
  final Uint8List? fileBytes;
  final String? fileName;

  const SharedFilePage({
    super.key,
    this.filePath,
    this.fileBytes,
    this.fileName,
  });

  @override
  State<SharedFilePage> createState() => _SharedFilePageState();
}

class _SharedFilePageState extends State<SharedFilePage> {
  final _syncHub = SyncHub();
  final _logManager = LogManager();

  bool _isProcessing = false;
  bool _isCompleted = false;
  String _status = '准备处理...';
  int _uploadedCount = 0;
  int _failedCount = 0;
  final List<String> _platformResults = [];

  @override
  void initState() {
    super.initState();
    _processFile();
  }

  Future<void> _processFile() async {
    setState(() {
      _isProcessing = true;
      _status = '正在读取文件...';
    });

    try {
      Uint8List bytes;
      String fileName;

      if (widget.fileBytes != null) {
        bytes = widget.fileBytes!;
        fileName = widget.fileName ?? 'shared_file.fit';
      } else if (widget.filePath != null) {
        final file = File(widget.filePath!);
        if (!await file.exists()) {
          setState(() {
            _status = '错误：文件不存在';
            _isProcessing = false;
          });
          return;
        }
        bytes = await file.readAsBytes();
        fileName = path.basename(widget.filePath!);
      } else {
        setState(() {
          _status = '错误：未提供文件';
          _isProcessing = false;
        });
        return;
      }

      // 坐标纠偏：直接上传的文件默认按 GCJ→WGS 处理
      final ext = fileName.split('.').last.toLowerCase();
      if (['fit', 'gpx', 'tcx'].contains(ext)) {
        setState(() => _status = '正在坐标纠偏...');
        try {
          bytes = await CoordFixer.processFile(bytes, ext, CoordDirection.gcj2wgs);
          final detectionResult = CoordFixer.lastDetectionResult;
          final sampleCount = CoordFixer.lastSampleCount;
          if (detectionResult == true) {
            _logManager.addLog('坐标检测: WGS-84 (无需纠正, 样本数: $sampleCount)');
          } else if (detectionResult == false) {
            _logManager.addLog('坐标检测: GCJ-02 (已纠正为 WGS-84, 样本数: $sampleCount)');
          } else {
            _logManager.addLog('坐标检测: 无坐标数据');
          }
        } catch (e) {
          _logManager.addLog('坐标纠偏失败: $e', isError: true);
        }
      }

      setState(() => _status = '正在上传到各平台...');

      final loggedInPlatforms = <String>[];
      if (_syncHub.stravaLoggedIn) loggedInPlatforms.add('Strava');
      if (_syncHub.igpLoggedIn) loggedInPlatforms.add('iGPSPORT');
      if (_syncHub.xingzheLoggedIn) loggedInPlatforms.add('行者');
      if (_syncHub.giantLoggedIn) loggedInPlatforms.add('捷安特');

      if (loggedInPlatforms.isEmpty) {
        setState(() {
          _status = '错误：未登录任何上传平台';
          _isProcessing = false;
        });
        return;
      }

      _logManager.addLog('开始上传到: ${loggedInPlatforms.join(", ")}');

      final futures = <Future<void>>[];
      if (_syncHub.stravaLoggedIn) futures.add(_uploadToStrava(bytes, fileName));
      if (_syncHub.igpLoggedIn) futures.add(_uploadToIgp(bytes, fileName));
      if (_syncHub.xingzheLoggedIn) futures.add(_uploadToXingzhe(bytes, fileName));
      if (_syncHub.giantLoggedIn) futures.add(_uploadToGiant(bytes, fileName));

      await Future.wait(futures, eagerError: false);

      setState(() {
        _isProcessing = false;
        _isCompleted = true;
        _status = '处理完成';
      });
    } catch (e) {
      setState(() {
        _status = '处理失败: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _uploadToStrava(Uint8List bytes, String fileName) async {
    try {
      await _syncHub.stravaManager.uploadFitFile(bytes, fileName);
      setState(() {
        _uploadedCount++;
        _platformResults.add('✓ Strava: 上传成功');
      });
    } catch (e) {
      setState(() {
        _failedCount++;
        _platformResults.add('✗ Strava: 上传失败 - $e');
      });
    }
  }

  Future<void> _uploadToIgp(Uint8List bytes, String fileName) async {
    try {
      await _syncHub.igpManager.uploadFitFile(bytes, fileName);
      setState(() {
        _uploadedCount++;
        _platformResults.add('✓ iGPSPORT: 上传成功');
      });
    } catch (e) {
      setState(() {
        _failedCount++;
        _platformResults.add('✗ iGPSPORT: 上传失败 - $e');
      });
    }
  }

  Future<void> _uploadToXingzhe(Uint8List bytes, String fileName) async {
    try {
      await _syncHub.xingzheManager.uploadFitFile(bytes, fileName);
      setState(() {
        _uploadedCount++;
        _platformResults.add('✓ 行者: 上传成功');
      });
    } catch (e) {
      setState(() {
        _failedCount++;
        _platformResults.add('✗ 行者: 上传失败 - $e');
      });
    }
  }

  Future<void> _uploadToGiant(Uint8List bytes, String fileName) async {
    try {
      await _syncHub.giantManager.uploadFitFile(bytes, fileName);
      setState(() {
        _uploadedCount++;
        _platformResults.add('✓ 捷安特: 上传成功');
      });
    } catch (e) {
      setState(() {
        _failedCount++;
        _platformResults.add('✗ 捷安特: 上传失败 - $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('处理分享文件'),
      ),
      body: Container(
        decoration: isDark ? AppTheme.backgroundGradient : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 文件信息卡片
              _buildFileInfoCard(theme)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),
              // 状态卡片
              _buildStatusCard(theme)
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              const SizedBox(height: 16),
              // 上传结果
              if (_platformResults.isNotEmpty) ...[
                Text(
                  '上传结果',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ).animate().fadeIn(duration: 300.ms, delay: 300.ms),
                const SizedBox(height: 8),
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(8),
                    child: ListView.builder(
                      itemCount: _platformResults.length,
                      itemBuilder: (context, index) {
                        final result = _platformResults[index];
                        final isSuccess = result.startsWith('✓');
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: (isSuccess
                                          ? AppTheme.success
                                          : AppTheme.error)
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  isSuccess
                                      ? Icons.check_circle_rounded
                                      : Icons.error_rounded,
                                  color: isSuccess
                                      ? AppTheme.success
                                      : AppTheme.error,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  result.substring(2),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(
                                duration: 300.ms,
                                delay: Duration(
                                    milliseconds: 400 + index * 100))
                            .slideX(begin: 0.1, end: 0);
                      },
                    ),
                  ),
                ),
              ],
              // 操作按钮
              if (_isCompleted) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: GradientButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('完成'),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileInfoCard(ThemeData theme) {
    final fileName =
        widget.fileName ?? path.basename(widget.filePath ?? '未知文件');

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppTheme.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.filePath != null)
                  Text(
                    widget.filePath!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final Color borderColor;
    final Color bgColor;
    if (_isCompleted) {
      borderColor = AppTheme.success;
      bgColor = AppTheme.success;
    } else if (_isProcessing) {
      borderColor = AppTheme.accent;
      bgColor = AppTheme.accent;
    } else {
      borderColor = AppTheme.error;
      bgColor = AppTheme.error;
    }

    return GlassCard(
      padding: const EdgeInsets.all(24),
      opacity: 0.1,
      child: Column(
        children: [
          if (_isProcessing)
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.accent,
              ),
            )
          else if (_isCompleted)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.success,
                size: 40,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_rounded,
                color: AppTheme.error,
                size: 40,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (_isCompleted) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCountBadge('成功', _uploadedCount, AppTheme.success),
                const SizedBox(width: 16),
                _buildCountBadge('失败', _failedCount, AppTheme.error),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
