import 'package:flutter/material.dart';
import 'sync_hub.dart';
import 'log_manager.dart';
import 'managers/locale_manager.dart';
import 'managers/theme_manager.dart';
import 'l10n/strings.dart';
import 'pages/home_page.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RideFitSync());
}

class RideFitSync extends StatefulWidget {
  const RideFitSync({super.key});

  @override
  State<RideFitSync> createState() => _RideFitSyncState();
}

class _RideFitSyncState extends State<RideFitSync> {
  final _syncHub = SyncHub();
  final _localeManager = LocaleManager();
  final _themeManager = ThemeManager();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _localeManager.init();
      await _syncHub.init();

      // 初始化通知服务
      await NotificationService().init();

      // 同步完成时发送通知
      _syncHub.onSyncCompleted = (successCount, failCount) {
        NotificationService().cancelNotifications();
        NotificationService().showSyncComplete(successCount, failCount);
      };

      setState(() {
        _isInitialized = true;
      });
      LogManager().addLog('应用初始化完成');

      // 检查是否开启自动同步（启动时立即同步一次）
      final autoSync = await _syncHub.storage.readBoolPrefs(key: 'auto_sync');
      if (autoSync && _syncHub.canSync) {
        LogManager().addLog('自动同步已开启，开始同步...');
        await NotificationService().showSyncStarted();
        // 延迟一下再同步，让 UI 先渲染完成
        await Future.delayed(const Duration(seconds: 2));
        await _syncHub.sync();
      }
    } catch (e) {
      LogManager().addLog('应用初始化失败: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_localeManager, _themeManager]),
      builder: (context, _) {
        S.setLocale(_localeManager.isZh);
        return _LocaleScope(
          isZh: _localeManager.isZh,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            title: 'RideFitSync',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _themeManager.themeMode,
            home: _isInitialized ? const HomePage() : const LoadingPage(),
          ),
        );
      },
    );
  }
}

/// 语言环境 InheritedWidget
class _LocaleScope extends InheritedWidget {
  final bool isZh;

  const _LocaleScope({required this.isZh, required super.child});

  @override
  bool updateShouldNotify(covariant _LocaleScope oldWidget) =>
      isZh != oldWidget.isZh;
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withOpacity(0.15),
                ),
                child: const Icon(Icons.sync, size: 64, color: AppTheme.accent),
              ),
              const SizedBox(height: 24),
              const Text(
                'RideFitSync',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '骑行数据同步助手',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '正在初始化...',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
