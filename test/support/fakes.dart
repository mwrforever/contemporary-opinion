// 共享测试替身：内存 TaskStore 与提醒三件套，隔离真实数据库/插件通道
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/audio_service.dart';
import 'package:daily_planner/services/reminder_scheduler.dart';
import 'package:daily_planner/services/reminder_service.dart';
import 'package:daily_planner/services/task_store.dart';
import 'package:daily_planner/services/tts_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;

/// 内存版任务仓储：widget 测试使用，避免 FakeAsync 中真实 SQLite 异步无法完成。
class FakeTaskStore extends TaskStore {
  FakeTaskStore() : super(userId: 1);

  final List<Task> _tasks = [];

  @override
  List<Task> get all => List.of(_tasks)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> init() async {}

  @override
  Task? getById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<void> add(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    _tasks.add(task);
    notifyListeners();
  }

  @override
  Future<void> update(Task task) async {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) _tasks[i] = task;
    notifyListeners();
  }

  @override
  Future<void> delete(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
  }

  @override
  Future<void> addWithConflictCheck(Task candidate, {DateTime? now}) async {
    await add(candidate);
  }

  @override
  Future<void> recheck(Task task, {DateTime? now}) async {
    await update(task);
  }

  @override
  Future<void> resolveOverride(Task task) async {
    task.conflictState = ConflictState.confirmedOverride;
    task.effective = true;
    await update(task);
  }

  @override
  Future<void> toggleDoneAt(Task task, DateTime now) async {
    if (task.status == TaskStatus.done) {
      task.status = TaskStatus.pending;
      task.completedAt = null;
    } else {
      task.status = TaskStatus.done;
      task.completedAt = now;
    }
    await update(task);
  }

  void seed(Task task) => _tasks.add(task);
}

/// 记录型调度器替身
class FakeScheduler implements ReminderScheduler {
  final scheduled = <int, DateTime>{};
  final cancelled = <int>[];
  int initCalls = 0;
  int permissionCalls = 0;

  @override
  Future<void> init({void Function(String payload)? onPayload}) async {
    initCalls++;
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

  @override
  Future<void> init() async {}

  @override
  Future<void> playRing({Duration duration = const Duration(seconds: 5)}) async {}

  @override
  Future<void> stopRing() async {
    stopped = true;
  }
}

class FakeTts extends TtsService {
  bool stopped = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> speakAndAwait(
    String text, {
    Duration maxWait = const Duration(seconds: 8),
  }) async {}

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// 组装一个带假依赖的提醒服务（widget 测试通用）。
ReminderService buildFakeReminder() => ReminderService(
      scheduler: FakeScheduler(),
      audio: FakeAudio(),
      tts: FakeTts(),
      enableInAppTimers: false,
    );
