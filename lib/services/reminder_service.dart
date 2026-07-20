import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';
import 'audio_service.dart';
import 'notification_service.dart';
import 'task_store.dart';
import 'tts_service.dart';
import 'settings_service.dart';

/// 提醒编排服务：
///  - 通过本地通知做精确调度（即使应用被杀，系统也会弹出通知）
///  - 应用存活时，用 Timer 在到点触发"响铃 + 语音播报"
///  - 通知被点击时同样触发响铃 + 播报
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioService audio = AudioService();
  final TtsService tts = TtsService();
  // 平台通知抽象：移动端走 flutter_local_notifications，Web 走 W3C Notification。
  final NotificationService _notifier = NotificationService();

  final Map<String, Timer> _timers = {};
  /// 正在播报中的语音提醒任务 id 集合；加入即表示要求立即停止该任务的响铃与播报。
  final Set<String> _alertStopFlags = {};
  TaskStore? _store;

  final SettingsService? settings;

  ReminderService({this.settings});

  static const String _channelId = 'reminder_channel';

  /// 语音提醒循环总时长：到点后语音播报循环播放，直至该时长结束。
  static const Duration _voiceLoopTotal = Duration(seconds: 10);
  /// 每条语音播报之间的间隔。
  static const Duration _voiceGap = Duration(seconds: 2);

  Future<void> init(TaskStore store) async {
    _store = store;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 失败则使用设备本地时区
    }
    await audio.init();
    await tts.init();
    await _notifier.init();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload != null) _fireAlertById(resp.payload!);
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

  /// 启动时重新调度所有未完成任务。
  Future<void> scheduleAll() async {
    if (_store == null) return;
    for (final t in _store!.all) {
      if (t.status != TaskStatus.done) await _scheduleTask(t);
    }
  }

  /// 任务增改后调用：完成则取消，否则重新调度。
  Future<void> notifyTaskChanged(Task task) async {
    if (task.status == TaskStatus.done) {
      await cancelTask(task);
    } else {
      await _scheduleTask(task);
    }
  }

  Future<void> scheduleTask(Task task) => _scheduleTask(task);

  Future<void> _scheduleTask(Task task) async {
    await cancelTask(task); // 先清理旧的，避免重复
    if (task.scheduledTime == null) return; // backlog 不调度

    final ids = _notificationIdsFor(task);
    for (final entry in ids.entries) {
      final id = entry.key;
      final when = entry.value;
      final match = _matchComponents(task);
      await _plugin.zonedSchedule(
        id,
        '规划提醒',
        task.title,
        tz.TZDateTime.from(when, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
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
        payload: task.id,
      );
    }
    _scheduleInAppTimer(task);
  }

  Map<int, DateTime> _notificationIdsFor(Task task) {
    final base = task.notificationId;
    if (task.scheduledTime == null) return {};
    switch (task.repeat) {
      case RepeatType.daily:
        return {base: task.scheduledTime!};
      case RepeatType.weekly:
        return {base: _nextWeekdayOccurrence(task.scheduledTime!)};
      case RepeatType.weekdays:
        final map = <int, DateTime>{};
        for (final w in const [1, 2, 3, 4, 5]) {
          map[base * 10 + w] =
              _nextWeekdayOccurrence(task.scheduledTime!, weekday: w);
        }
        return map;
      case RepeatType.custom:
        final map = <int, DateTime>{};
        final wds = task.customWeekdays.isEmpty
            ? [task.scheduledTime!.weekday]
            : task.customWeekdays;
        for (final w in wds) {
          map[base * 10 + w] =
              _nextWeekdayOccurrence(task.scheduledTime!, weekday: w);
        }
        return map;
      case RepeatType.none:
        return {base: task.scheduledTime!};
    }
  }

  DateTime _nextWeekdayOccurrence(DateTime time, {int? weekday}) {
    final wd = weekday ?? time.weekday;
    var candidate =
        DateTime(time.year, time.month, time.day, time.hour, time.minute);
    var diff = (wd - candidate.weekday) % 7;
    if (diff == 0 && candidate.isBefore(DateTime.now())) diff = 7;
    candidate = candidate.add(Duration(days: diff));
    if (candidate.isBefore(DateTime.now())) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  DateTimeComponents? _matchComponents(Task task) {
    switch (task.repeat) {
      case RepeatType.daily:
        return DateTimeComponents.time;
      case RepeatType.weekly:
      case RepeatType.weekdays:
      case RepeatType.custom:
        return DateTimeComponents.dayOfWeekAndTime;
      case RepeatType.none:
        return null;
    }
  }

  Future<void> cancelTask(Task task) async {
    _stopAlert(task.id);
    final base = task.notificationId;
    await _plugin.cancel(base);
    for (final w in const [1, 2, 3, 4, 5, 6, 7]) {
      await _plugin.cancel(base * 10 + w);
    }
    _timers[task.id]?.cancel();
    _timers.remove(task.id);
  }

  /// 应用存活时用 Timer 触发响铃 + 播报，重复任务到点后续约。
  void _scheduleInAppTimer(Task task) {
    _timers[task.id]?.cancel();
    final when = _nextFire(task);
    if (when == null) return;
    final delay = when.difference(DateTime.now());
    if (delay.isNegative) return;
    _timers[task.id] = Timer(delay, () {
      _fireAlert(task);
      if (task.isRepeating) _scheduleInAppTimer(task);
    });
  }

  DateTime? _nextFire(Task task) {
    if (task.scheduledTime == null) return null;
    if (task.repeat == RepeatType.none) return task.scheduledTime;
    var when = task.scheduledTime!;
    final now = DateTime.now();
    while (when.isBefore(now)) {
      when = when.add(task.repeat == RepeatType.daily
          ? const Duration(days: 1)
          : const Duration(days: 7));
    }
    return when;
  }

  void _fireAlertById(String id) {
    final task = _store?.getById(id);
    if (task != null && task.status != TaskStatus.done) _fireAlert(task);
  }

  /// 到点触发：弹出 Web 通知，并并发启动「响铃 + 语音循环播报」。
  /// 语音播报循环规则：每条播完后间隔 [_voiceGap]，循环直至 [_voiceLoopTotal] 总时长结束。
  void _fireAlert(Task task) {
    // Web 无系统级未来调度，由 in-app Timer 触发后用浏览器通知做即时提醒
    if (kIsWeb) {
      try {
        _notifier.ensurePermissions();
        _notifier.showImmediate(title: '规划提醒', body: task.title);
      } catch (_) {
        // 通知不可用忽略
      }
    }
    unawaited(_runAlert(task));
  }

  /// 实际执行响铃 + 语音循环播报（异步）。可被 [_stopAlert] 立即中断。
  Future<void> _runAlert(Task task) async {
    _alertStopFlags.remove(task.id); // 清除上一轮（重复任务）残留，避免误杀本轮
    final text = _speakText(task);
    final start = DateTime.now();

    // 响铃：在整段循环窗口内持续（audio.playRing 内部每 2 秒重播一次），fire-and-forget。
    unawaited(audio.playRing(duration: _voiceLoopTotal));

    while (DateTime.now().difference(start) < _voiceLoopTotal) {
      if (_alertStopFlags.contains(task.id)) break;
      try {
        await tts.speakAndAwait(text);
      } catch (_) {
        // 播报不可用（如部分 Web 环境）忽略，继续走完窗口
      }
      if (_alertStopFlags.contains(task.id)) break;
      // 已到窗口末尾则不再空等间隔
      if (DateTime.now().difference(start) >= _voiceLoopTotal) break;
      await Future.delayed(_voiceGap);
    }
    _alertStopFlags.remove(task.id);
  }

  /// 立即中断某任务的响铃与语音播报（由取消任务 / 全局停止调用）。
  void _stopAlert(String taskId) {
    _alertStopFlags.add(taskId);
    try {
      audio.stopRing();
    } catch (_) {}
    try {
      tts.interrupt();
    } catch (_) {}
  }

  String _speakText(Task task) {
    final hint = switch (task.repeat) {
      RepeatType.daily => '，每天',
      RepeatType.weekly => '，每周',
      RepeatType.weekdays => '，工作日',
      _ => '',
    };
    return '提醒您：${task.title}$hint';
  }

  Future<void> stopAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _alertStopFlags.clear();
    await audio.stopRing();
    await tts.stop();
  }
}
