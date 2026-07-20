import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';

/// 移动端通知实现：封装 flutter_local_notifications，支持精准调度
/// （即使 App 被杀，系统仍会弹出通知）。
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'reminder_channel';

  void Function(String? payload)? _onTap;

  /// 设置「点击通知」回调（由 ReminderService 用来触发响铃 + 播报）。
  void setOnTapCallback(void Function(String? payload) cb) => _onTap = cb;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 失败则使用设备本地时区
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        _onTap?.call(resp.payload);
      },
    );

    final channel = AndroidNotificationChannel(
      channelId,
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

  /// 申请通知与精确闹钟权限（Android 12+）。
  Future<void> ensurePermissions() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
      await androidImpl.requestExactAlarmsPermission();
    }
  }

  /// 是否支持系统级（未来时间）调度。移动端为 true，Web 为 false。
  bool get supportsScheduledNotifications => true;

  /// 调度一条未来时间的通知（系统级，App 不在也能弹）。
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required RepeatType? repeat,
    String? payload,
  }) async {
    final match = _matchComponents(repeat);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          '任务提醒',
          channelDescription: '每日规划助手的任务提醒',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match,
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// 立即弹出一条通知（用于 Web 端点提醒 / 兜底）。
  Future<void> showImmediate({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 2147483647,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          '任务提醒',
          channelDescription: '每日规划助手的任务提醒',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  DateTimeComponents? _matchComponents(RepeatType? repeat) {
    switch (repeat) {
      case RepeatType.daily:
        return DateTimeComponents.time;
      case RepeatType.weekly:
      case RepeatType.weekdays:
      case RepeatType.custom:
        return DateTimeComponents.dayOfWeekAndTime;
      case RepeatType.none:
      case null:
        return null;
    }
  }
}
