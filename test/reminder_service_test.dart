// ReminderService 单元测试：调度派生/取消/权限转发/停止（原生通道以假实现隔离）
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/audio_service.dart';
import 'package:daily_planner/services/reminder_scheduler.dart';
import 'package:daily_planner/services/reminder_service.dart';
import 'package:daily_planner/services/task_store.dart';
import 'package:daily_planner/services/tts_service.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 记录型调度器替身
class FakeScheduler implements ReminderScheduler {
  final scheduled = <int, DateTime>{};
  final vibrateFlags = <int, bool>{};
  final cancelled = <int>[];
  int initCalls = 0;
  int permissionCalls = 0;
  void Function(String payload)? payloadCallback;

  @override
  Future<void> init({void Function(String payload)? onPayload}) async {
    initCalls++;
    payloadCallback = onPayload;
  }

  @override
  Future<void> requestPermissions() async {
    permissionCalls++;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required DateTimeComponents? match,
    required String payload,
    required bool vibrate,
  }) async {
    scheduled[id] = when;
    vibrateFlags[id] = vibrate;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

class FakeAudio extends AudioService {
  bool stopped = false;
  int ringCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> playRing({Duration duration = const Duration(seconds: 5)}) async {
    ringCount++;
  }

  @override
  Future<void> stopRing() async {
    stopped = true;
  }
}

class FakeTts extends TtsService {
  bool stopped = false;
  int speakCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<List<TtsVoice>> availableVoices() async => const [];

  @override
  Future<void> setVoice(String? voiceId) async {}

  @override
  Future<void> speakAndAwait(
    String text, {
    Duration maxWait = const Duration(seconds: 8),
  }) async {
    speakCount++;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late FakeScheduler scheduler;
  late FakeAudio audio;
  late FakeTts tts;
  late ReminderService service;

  setUp(() {
    scheduler = FakeScheduler();
    audio = FakeAudio();
    tts = FakeTts();
    service = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
    );
  });

  DateTime futureTime({int hour = 10}) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour);
  }

  /// 轮询等待条件成立（CI 慢速/高负载环境下固定延时不可靠，避免偶发失败）。
  Future<void> waitUntil(
    bool Function() cond, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  Task buildTask(String id, {RepeatType repeat = RepeatType.none}) => Task(
        id: id,
        title: '任务$id',
        scheduledTime: futureTime(),
        repeat: repeat,
        customWeekdays: repeat == RepeatType.custom ? const [2, 4] : const [],
        createdAt: DateTime(2026, 8, 1),
        notificationId: 7,
      );

  test('scheduleTask 一次性任务：精确调度 base id 且可被 stopAll 清理', () async {
    final task = buildTask('once');
    await service.scheduleTask(task);
    expect(scheduler.scheduled.keys, [7]);
    await service.stopAll();
    expect(audio.stopped, isTrue);
    expect(tts.stopped, isTrue);
  });

  test('工作日重复任务派生 5 个子通知 id', () async {
    await service.scheduleTask(buildTask('week', repeat: RepeatType.weekdays));
    expect(scheduler.scheduled.keys.toSet(),
        {71, 72, 73, 74, 75});
    await service.stopAll();
  });

  test('自定义星期重复任务按星期派生子通知 id', () async {
    await service.scheduleTask(buildTask('custom', repeat: RepeatType.custom));
    expect(scheduler.scheduled.keys.toSet(), {72, 74});
    await service.stopAll();
  });

  test('notifyTaskChanged(done) 取消 base 与全部派生 id', () async {
    final task = buildTask('done', repeat: RepeatType.weekdays);
    await service.scheduleTask(task);
    task.status = TaskStatus.done;
    await service.notifyTaskChanged(task);
    expect(scheduler.cancelled, containsAll([7, 71, 72, 73, 74, 75]));
    await service.stopAll();
  });

  test('ensurePermissions 转发到调度器', () async {
    await service.ensurePermissions();
    expect(scheduler.permissionCalls, 1);
  });

  test('冲突待处理任务（effective=false）不调度执行', () async {
    final task = buildTask('conflict');
    task.effective = false;
    task.conflictState = ConflictState.pendingConflict;
    await service.scheduleTask(task);
    expect(scheduler.scheduled, isEmpty);
    // 已清理旧调度，避免残留通知
    expect(scheduler.cancelled, contains(7));
    await service.stopAll();
  });

  test('通知调度携带震动标志：跟随提醒设置，关闭时通知不带震动', () async {
    // 默认设置（未读库）：vibrate=true
    await service.scheduleTask(buildTask('vib1'));
    expect(scheduler.vibrateFlags[7], isTrue);
    await service.stopAll();
    // 库中 vibrate=0：重排后通知显式禁用震动
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    await db.insert('user_settings', {
      'user_id': 1,
      'reminder_mode': 'voice',
      'vibrate': 0,
      'reminder_volume': 60,
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final svc = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
    );
    await svc.init(store);
    await svc.reloadSettings(1);
    final noVib = buildTask('vib2');
    await store.add(noVib);
    await svc.scheduleTask(noVib);
    expect(scheduler.vibrateFlags[7], isFalse);
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });

  test('scheduleAll 跳过已完成任务', () async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final done = buildTask('done');
    done.status = TaskStatus.done;
    await store.add(done);
    await store.add(buildTask('pending'));
    await service.init(store);
    await service.scheduleAll();
    expect(scheduler.scheduled.keys, [7]);
    await service.stopAll();
    await DatabaseHelper.instance.close();
  });

  test('提醒设置：静音到点不播报但震动仍生效，语音到点纯播报标题（不叠加响铃）', () async {
    // 拦截原生震动通道：记录到点是否触发马达震动
    final vibrateCalls = <String>[];
    final channel = const MethodChannel('daily_planner/vibrate');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      vibrateCalls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    await db.insert('user_settings', {
      'user_id': 1,
      'reminder_mode': 'mute',
      'vibrate': 1,
      'reminder_volume': 60,
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final svc = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
      voiceLoopTotal: const Duration(milliseconds: 150),
      voiceGap: const Duration(milliseconds: 10),
    );
    await svc.init(store);
    await svc.reloadSettings(1);
    // 静音+震动：到点只展示系统通知 + 触发震动，不响铃不播报
    // （一次性任务播报后自动完成，故语音阶段用独立任务，避免触发 _fireAlertById 的 done 拦截）
    final muteTask = buildTask('静音任务');
    muteTask.scheduledTime = DateTime.now().add(const Duration(minutes: 1));
    await store.add(muteTask);
    scheduler.payloadCallback!(muteTask.id);
    // 轮询等待到点触发（避免 CI 负载下固定延时误判）
    await waitUntil(() => vibrateCalls.isNotEmpty);
    expect(tts.speakCount, 0);
    expect(audio.ringCount, 0);
    // 震动持续整个响铃时长（150ms）后自动停止，不遗留常震
    await waitUntil(() => vibrateCalls.contains('cancel'));
    // 切回语音：到点纯语音播报（不再叠加响铃音，避免哔哔声）
    await db.update(
      'user_settings',
      {'reminder_mode': 'voice', 'reminder_volume': 70},
      where: 'user_id = ?',
      whereArgs: [1],
    );
    await svc.reloadSettings(1);
    final voiceTask = buildTask('语音任务');
    voiceTask.scheduledTime = DateTime.now().add(const Duration(minutes: 1));
    await store.add(voiceTask);
    scheduler.payloadCallback!(voiceTask.id);
    await waitUntil(() => tts.speakCount > 0);
    expect(audio.ringCount, 0);
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });

  /// 构造倒计时重复任务：首次触发在 [delayMs] 后，间隔 [intervalSeconds] 秒。
  Task buildDelayedTask(
    String id, {
    required Duration delay,
    required int intervalSeconds,
    required int maxRepeats,
    int repeatCount = 0,
    int notificationId = 8,
  }) =>
      Task(
        id: id,
        title: '任务$id',
        scheduledTime: DateTime.now().add(delay),
        triggerType: TriggerType.delayed,
        intervalSeconds: intervalSeconds,
        maxRepeats: maxRepeats,
        repeatCount: repeatCount,
        createdAt: DateTime(2026, 8, 1),
        notificationId: notificationId,
      );

  test('倒计时重复：播报完成后未达上限推进次数并重排下次执行时间', () async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final svc = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
      voiceLoopTotal: const Duration(milliseconds: 120),
      voiceGap: const Duration(milliseconds: 10),
    );
    await svc.init(store);
    final anchor = DateTime.now().add(const Duration(milliseconds: 250));
    final task = buildDelayedTask(
      'delayed',
      delay: anchor.difference(DateTime.now()),
      intervalSeconds: 60,
      maxRepeats: 3,
    );
    await store.add(task);
    await svc.scheduleTask(task);
    // 等待首次触发 + 播报窗口走完，触发自动推进（轮询，避免 CI 负载下固定延时误判）
    await waitUntil(
      () => (store.getById('delayed')?.repeatCount ?? 0) >= 1,
    );
    final current = store.getById('delayed')!;
    expect(current.status, TaskStatus.pending);
    expect(current.repeatCount, 1);
    // 系统通知已重排到「首次 + 一个间隔」后的下一次
    await waitUntil(
      () => scheduler.scheduled[8] == anchor.add(const Duration(seconds: 60)),
    );
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });

  test('倒计时一直重复(-1)：播报完成后保持待执行并继续重排', () async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final svc = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
      voiceLoopTotal: const Duration(milliseconds: 120),
      voiceGap: const Duration(milliseconds: 10),
    );
    await svc.init(store);
    final anchor = DateTime.now().add(const Duration(milliseconds: 250));
    final task = buildDelayedTask(
      'forever',
      delay: anchor.difference(DateTime.now()),
      intervalSeconds: 60,
      maxRepeats: -1,
    );
    await store.add(task);
    await svc.scheduleTask(task);
    // 轮询等待首次触发 + 播报推进（避免 CI 负载下固定延时误判）
    await waitUntil(() => (store.getById('forever')?.repeatCount ?? 0) >= 1);
    final current = store.getById('forever')!;
    expect(current.status, TaskStatus.pending);
    expect(current.repeatCount, 1);
    await waitUntil(
      () => scheduler.scheduled[8] == anchor.add(const Duration(seconds: 60)),
    );
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });

  test('倒计时重复：次数用尽后播报完成自动标记已完成并取消调度', () async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final svc = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
      voiceLoopTotal: const Duration(milliseconds: 120),
      voiceGap: const Duration(milliseconds: 10),
    );
    await svc.init(store);
    final anchor = DateTime.now().add(const Duration(milliseconds: 250));
    final task = buildDelayedTask(
      'onceDelay',
      delay: anchor.difference(DateTime.now()),
      intervalSeconds: 60,
      maxRepeats: 1,
    );
    await store.add(task);
    await svc.scheduleTask(task);
    // 轮询等待播报完成后的自动收尾（次数用尽置 done + 取消调度）
    await waitUntil(
      () => (store.getById('onceDelay')?.status ?? TaskStatus.pending) ==
          TaskStatus.done,
    );
    final current = store.getById('onceDelay')!;
    expect(current.status, TaskStatus.done);
    expect(current.repeatCount, 1);
    expect(scheduler.cancelled, contains(8));
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });

  test('一次性任务：播报完成后自动标记已完成并取消调度', () async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    final store = TaskStore(userId: 1);
    await store.init();
    final svc = ReminderService(
      scheduler: scheduler,
      audio: audio,
      tts: tts,
      voiceLoopTotal: const Duration(milliseconds: 120),
      voiceGap: const Duration(milliseconds: 10),
    );
    await svc.init(store);
    final task = buildTask('onceAuto');
    task.scheduledTime = DateTime.now().add(const Duration(milliseconds: 250));
    await store.add(task);
    await svc.scheduleTask(task);
    // 轮询等待播报完成自动标记 done
    await waitUntil(
      () => (store.getById('onceAuto')?.status ?? TaskStatus.pending) ==
          TaskStatus.done,
    );
    expect(store.getById('onceAuto')!.status, TaskStatus.done);
    expect(scheduler.cancelled, contains(7));
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });
}
