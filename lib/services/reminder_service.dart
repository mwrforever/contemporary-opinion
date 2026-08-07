import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;

import '../data/daos/settings_dao.dart';
import '../data/models/reminder_settings.dart';
import '../models/task.dart';
import 'audio_service.dart';
import 'reminder_scheduler.dart';
import 'task_store.dart';
import 'tts_service.dart';

/// 提醒编排服务：
///  - 通过本地通知精确调度（应用被杀仍弹），重复任务派生多通知 id
///  - 应用存活时用 Timer 到点触发「响铃 + 中文语音循环播报」
///  - 通知被点击时同样触发响铃 + 播报
///
/// 依赖 [ReminderScheduler]/[AudioService]/[TtsService] 均可注入，便于单元测试。
class ReminderService {
  ReminderService({
    ReminderScheduler? scheduler,
    AudioService? audio,
    TtsService? tts,
    this.enableInAppTimers = true,
    this.voiceLoopTotal = const Duration(seconds: 10),
    this.voiceGap = const Duration(seconds: 2),
  })  : _scheduler = scheduler ?? ReminderSchedulerIo(),
        audio = audio ?? AudioService(),
        tts = tts ?? TtsService();

  final ReminderScheduler _scheduler;
  final AudioService audio;
  final TtsService tts;

  /// 应用存活期 Timer 响铃开关；无头/测试环境可关闭
  final bool enableInAppTimers;

  final Map<String, Timer> _timers = {};
  final Set<String> _alertStopFlags = {};
  TaskStore? _store;
  ReminderSettings _settings = const ReminderSettings();

  /// 语音提醒循环总时长：到点后语音播报循环播放，直至该时长结束。
  /// 可注入以便测试（生产默认 10 秒）。
  final Duration voiceLoopTotal;

  /// 语音播报之间的间隔（可注入以便测试，生产默认 2 秒）。
  final Duration voiceGap;

  Future<void> init(TaskStore store) async {
    _store = store;
    await audio.init();
    await tts.init();
    await _scheduler.init(onPayload: _fireAlertById);
  }

  /// 申请通知与精确闹钟权限
  Future<void> ensurePermissions() => _scheduler.requestPermissions();

  /// 读取当前用户的提醒设置（静音/震动/语音 + 音量），供到点播报分支使用。
  Future<void> reloadSettings(int userId) async {
    try {
      _settings = await SettingsDao().get(userId);
    } catch (_) {
      // 设置读取失败时保持默认（语音播报 + 震动）
      _settings = const ReminderSettings();
    }
  }

  /// 启动时重新调度所有未完成任务
  Future<void> scheduleAll() async {
    if (_store == null) return;
    for (final t in _store!.all) {
      if (t.status != TaskStatus.done) await _scheduleTask(t);
    }
  }

  /// 任务增改后调用：完成则取消，否则重新调度
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
      await _scheduler.zonedSchedule(
        id: entry.key,
        title: '规划提醒',
        body: task.title,
        when: entry.value,
        match: _matchComponents(task),
        payload: task.id,
      );
    }
    _scheduleInAppTimer(task);
  }

  /// 按重复类型派生通知 id（工作日/自定义星期以 base*10+w 派生子 id）
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
    await _scheduler.cancel(base);
    for (final w in const [1, 2, 3, 4, 5, 6, 7]) {
      await _scheduler.cancel(base * 10 + w);
    }
    _timers[task.id]?.cancel();
    _timers.remove(task.id);
  }

  /// 应用存活时用 Timer 触发响铃 + 播报，重复任务到点后续约。
  void _scheduleInAppTimer(Task task) {
    if (!enableInAppTimers) return;
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

  /// 到点触发：并发启动「响铃 + 语音循环播报」。
  void _fireAlert(Task task) {
    unawaited(_runAlert(task));
  }

  /// 实际执行响铃 + 语音循环播报（异步）。可被 [_stopAlert] 立即中断。
  Future<void> _runAlert(Task task) async {
    _alertStopFlags.remove(task.id); // 清除上一轮（重复任务）残留，避免误杀本轮
    final text = _speakText(task);
    final start = DateTime.now();

    // 静音模式：到点不发声音（仅依赖系统通知展示）；否则响铃 + 语音播报
    if (_settings.mode != ReminderMode.mute) {
      unawaited(audio.playRing(duration: voiceLoopTotal));

      while (DateTime.now().difference(start) < voiceLoopTotal) {
        if (_alertStopFlags.contains(task.id)) break;
        try {
          await tts.setVolume(_settings.volume / 100);
          await tts.speakAndAwait(text);
        } catch (_) {
          // 播报不可用则忽略，继续走完窗口
        }
        if (_alertStopFlags.contains(task.id)) break;
        if (DateTime.now().difference(start) >= voiceLoopTotal) break;
        await Future.delayed(voiceGap);
      }
    }
    _alertStopFlags.remove(task.id);
  }

  /// 立即中断某任务的响铃与语音播报（由取消任务 / 全局停止调用）。
  Future<void> _stopAlert(String taskId) async {
    _alertStopFlags.add(taskId);
    try {
      await audio.stopRing();
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
