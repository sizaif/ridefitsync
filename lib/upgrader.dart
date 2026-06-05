import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'log_manager.dart';
import 'l10n/strings.dart';

class AppUpgrader {
  static const String currentVersion = "1.0.1";
  static const String repoUrl =
      "https://api.github.com/repos/sizaif/ridefitsync/releases/latest";

  static bool get isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static int compareVersion(String newVersion) {
    final v2 =
        newVersion.startsWith('v') ? newVersion.substring(1) : newVersion;
    List<int> v1Parts = currentVersion.split('.').map(int.parse).toList();
    List<int> v2Parts = v2.split('.').map(int.parse).toList();
    int maxLength =
        v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;

    for (int i = 0; i < maxLength; i++) {
      int v1Value = i < v1Parts.length ? v1Parts[i] : 0;
      int v2Value = i < v2Parts.length ? v2Parts[i] : 0;
      if (v1Value > v2Value) return -1;
      if (v1Value < v2Value) return 1;
    }
    return 0;
  }

  static Future<void> checkUpgrade(BuildContext context) async {
    if (kIsWeb || !isMobilePlatform) return;
    try {
      final response = await http.get(Uri.parse(repoUrl));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data is! Map || !data.containsKey('tag_name')) return;

      final latestVersion = data['tag_name'] as String;
      if (compareVersion(latestVersion) != 1) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.current.alreadyLatestVersion)),
          );
        }
        return;
      }

      final note = data['body'] ?? '';
      String downloadUrl = '';
      if (data.containsKey('assets') &&
          (data['assets'] as List).isNotEmpty) {
        downloadUrl =
            data['assets'][0]['browser_download_url'] as String;
      }

      if (downloadUrl.isEmpty) {
        LogManager().addLog('No APK download URL found in release');
        return;
      }

      if (context.mounted) {
        _showUpgradeDialog(context, latestVersion, note, downloadUrl);
      }
    } catch (e) {
      LogManager().addLog("Check update failed: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.checkUpdateFailed)),
        );
      }
    }
  }

  static void _showUpgradeDialog(
    BuildContext context,
    String version,
    String note,
    String downloadUrl,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(S.current.findNewVersion),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: Text(S.current.versionNo),
                  subtitle: Text(version),
                  contentPadding: EdgeInsets.zero,
                ),
                if (note.isNotEmpty)
                  ListTile(
                    title: Text(S.current.changelog),
                    subtitle: Text(note),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(S.current.cancel),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              child: Text(S.current.updateNow),
              onPressed: () {
                Navigator.pop(ctx);
                _downloadAndInstall(context, downloadUrl);
              },
            ),
          ],
        );
      },
    );
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    String url,
  ) async {
    final progressNotifier = ValueNotifier<double>(0);
    final errorNotifier = ValueNotifier<String?>(null);
    bool downloadDone = false;

    // 显示下载进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<String?>(
          valueListenable: errorNotifier,
          builder: (ctx, error, _) {
            if (error != null) {
              return AlertDialog(
                title: Text(S.current.downloadFailed),
                content: Text(error),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(S.current.close),
                  ),
                ],
              );
            }
            return ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (ctx, progress, _) {
                return AlertDialog(
                  title: Text(S.current.downloading),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 16),
                      Text('${(progress * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/update.apk');

      final request = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse response =
          await http.Client().send(request);

      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final sink = file.openWrite();
      final stream = response.stream;

      await for (final chunk in stream) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) {
          progressNotifier.value = downloadedBytes / totalBytes;
        }
      }
      await sink.close();

      downloadDone = true;

      // 关闭下载对话框
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (Platform.isAndroid) {
        const channel = MethodChannel('com.example.ridefitsync/installer');
        await channel.invokeMethod('installApk', {'path': file.path});
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.installPrompt)),
        );
      }
    } catch (e) {
      errorNotifier.value = e.toString();
      LogManager().addLog("Download failed: $e");
      // 延迟一小段时间让错误对话框显示
      await Future.delayed(const Duration(seconds: 3));
      if (context.mounted && !downloadDone) {
        Navigator.of(context).pop();
      }
    } finally {
      progressNotifier.dispose();
      errorNotifier.dispose();
    }
  }
}
