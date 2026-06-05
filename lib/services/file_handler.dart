import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../sync_hub.dart';
import '../log_manager.dart';

/// 文件处理器 - 处理接收到的FIT文件
class FileHandler {
  static final FileHandler _instance = FileHandler._internal();
  factory FileHandler() => _instance;
  FileHandler._internal();

  final _syncHub = SyncHub();
  final _logManager = LogManager();

  // 接收文件回调
  Function(String)? onFileReceived;
  Function(String)? onError;
  Function()? onSyncComplete;

  /// 处理接收到的文件
  Future<void> handleFile(String filePath) async {
    try {
      _logManager.addLog('收到文件: $filePath');

      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        _logManager.addLog('文件不存在: $filePath', isError: true);
        onError?.call('文件不存在');
        return;
      }

      // 检查文件扩展名
      final ext = path.extension(filePath).toLowerCase();
      if (ext != '.fit' && ext != '.gpx' && ext != '.tcx') {
        _logManager.addLog('不支持的文件格式: $ext', isError: true);
        onError?.call('不支持的文件格式: $ext');
        return;
      }

      // 读取文件
      final bytes = await file.readAsBytes();
      final fileName = path.basename(filePath);

      _logManager.addLog('开始处理文件: $fileName (${bytes.length} bytes)');

      // 上传到各平台
      await _syncHub.uploadToAllPlatforms(bytes, fileName);

      _logManager.addLog('文件处理完成: $fileName');
      onSyncComplete?.call();
    } catch (e) {
      _logManager.addLog('处理文件失败: $e', isError: true);
      onError?.call('处理文件失败: $e');
    }
  }

  /// 处理文件字节数据
  Future<void> handleFileBytes(Uint8List bytes, String fileName) async {
    try {
      _logManager.addLog('收到文件数据: $fileName (${bytes.length} bytes)');

      // 上传到各平台
      await _syncHub.uploadToAllPlatforms(bytes, fileName);

      _logManager.addLog('文件处理完成: $fileName');
      onSyncComplete?.call();
    } catch (e) {
      _logManager.addLog('处理文件失败: $e', isError: true);
      onError?.call('处理文件失败: $e');
    }
  }

  /// 从临时目录复制文件到应用目录
  Future<String> copyToAppDir(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = path.basename(sourcePath);
    final destPath = path.join(appDir.path, 'received', fileName);

    // 确保目录存在
    final destDir = Directory(path.dirname(destPath));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // 复制文件
    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);

    return destPath;
  }

  /// 清理临时文件
  Future<void> cleanupTempFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final receivedDir = Directory(path.join(appDir.path, 'received'));

      if (await receivedDir.exists()) {
        await receivedDir.delete(recursive: true);
        _logManager.addLog('已清理临时文件');
      }
    } catch (e) {
      _logManager.addLog('清理临时文件失败: $e', isError: true);
    }
  }
}
