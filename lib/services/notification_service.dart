import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showSyncComplete(int successCount, int failCount) async {
    if (!_initialized) return;

    final title = '同步完成';
    final body = failCount == 0
        ? '成功同步 $successCount 个活动'
        : '成功 $successCount, 失败 $failCount';

    const androidDetails = AndroidNotificationDetails(
      'sync_channel',
      '同步通知',
      channelDescription: '显示同步结果通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(0, title, body, details);
  }

  Future<void> showSyncStarted() async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'sync_channel',
      '同步通知',
      channelDescription: '显示同步结果通知',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showProgress: true,
      indeterminate: true,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(0, '正在同步...', '从数据源下载并上传活动中', details);
  }

  Future<void> cancelNotifications() async {
    await _plugin.cancelAll();
  }
}
