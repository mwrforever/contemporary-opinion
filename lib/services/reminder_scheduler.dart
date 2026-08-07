import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 提醒调度抽象：隔离 flutter_local_notifications，便于单元测试替换。
abstract class ReminderScheduler {
  /// 初始化插件与通知渠道；[onPayload] 接收通知点击回调的 payload。
  Future<void> init({void Function(String payload)? onPayload});

  /// 申请通知与精确闹钟权限
  Future<void> requestPermissions();

  /// 精确调度一条通知（[when] 为本地绝对时刻）
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required DateTimeComponents? match,
    required String payload,
  });

  /// 取消单条通知
  Future<void> cancel(int id);
}

/// IO 实现：封装 flutter_local_notifications 22.x 系统级精确调度。
class ReminderSchedulerIo implements ReminderScheduler {
  ReminderSchedulerIo({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const _channelId = 'reminder_channel';

  @override
  Future<void> init({void Function(String payload)? onPayload}) async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 时区数据异常时回退设备本地时区
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: onPayload == null
          ? null
          : (resp) {
              if (resp.payload != null) onPayload(resp.payload!);
            },
    );
    final channel = AndroidNotificationChannel(
      _channelId,
      '任务提醒',
      description: '每日规划助手的任务提醒',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  @override
  Future<void> requestPermissions() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      await iosImpl.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required DateTimeComponents? match,
    required String payload,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '任务提醒',
          channelDescription: '每日规划助手的任务提醒',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: match,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
