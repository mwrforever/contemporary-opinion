// ReminderService 单元测试：调度派生/取消/权限转发/停止（原生通道以假实现隔离）
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/audio_service.dart';
import 'package:daily_planner/services/reminder_scheduler.dart';
import 'package:daily_planner/services/reminder_service.dart';
import 'package:daily_planner/services/task_store.dart';
import 'package:daily_planner/services/tts_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 记录型调度器替身
class FakeScheduler implements ReminderScheduler {
  final scheduled = <int, DateTime>{};
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
  }) async {
    scheduled[id] = when;
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

  test('提醒设置：静音到点不播报，语音到点播报（含音量）', () async {
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
    final task = buildTask('提醒');
    task.scheduledTime = DateTime.now().add(const Duration(minutes: 1));
    await store.add(task);
    // 静音：到点只展示系统通知，不响铃不播报
    scheduler.payloadCallback!(task.id);
    await Future.delayed(const Duration(milliseconds: 80));
    expect(tts.speakCount, 0);
    expect(audio.ringCount, 0);
    // 切回语音：到点响铃 + 播报
    await db.update(
      'user_settings',
      {'reminder_mode': 'voice', 'reminder_volume': 70},
      where: 'user_id = ?',
      whereArgs: [1],
    );
    await svc.reloadSettings(1);
    scheduler.payloadCallback!(task.id);
    await Future.delayed(const Duration(milliseconds: 300));
    expect(tts.speakCount, greaterThan(0));
    expect(audio.ringCount, greaterThan(0));
    await svc.stopAll();
    await DatabaseHelper.instance.close();
  });
}
