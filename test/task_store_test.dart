// TaskStore（SQLite 版）单元测试：加载/冲突/覆盖/完成滚动/过期标记
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/task_dao.dart';
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/task_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Task buildTask(
    String id, {
    DateTime? scheduledTime,
    String? resource,
    int durationMinutes = 0,
    RepeatType repeat = RepeatType.none,
  }) =>
      Task(
        id: id,
        title: id,
        scheduledTime: scheduledTime,
        resource: resource,
        durationMinutes: durationMinutes,
        repeat: repeat,
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  /// 冲突检测窗口以 now 起算，需用未来时刻才能参与重叠判定
  DateTime futureTime(int hour, [int minute = 0]) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute);
  }

  test('init 加载数据库已有任务', () async {
    final dao = TaskDao();
    await dao.insert(buildTask('a', scheduledTime: DateTime(2026, 8, 5, 9)), userId: 1);
    final store = TaskStore(userId: 1);
    await store.init();
    expect(store.all.map((t) => t.id), ['a']);
  });

  test('addWithConflictCheck：资源占用冲突 → pendingConflict 且不生效', () async {
    final store = TaskStore(userId: 1);
    await store.init();
    final base = buildTask(
      '会议A',
      scheduledTime: futureTime(10),
      resource: '会议室A',
      durationMinutes: 60,
    );
    final candidate = buildTask(
      '会议B',
      scheduledTime: futureTime(10, 30),
      resource: '会议室A',
      durationMinutes: 60,
    );
    await store.add(base);
    await store.addWithConflictCheck(candidate);
    final saved = store.getById('会议B')!;
    expect(saved.conflictState, ConflictState.pendingConflict);
    expect(saved.effective, isFalse);
  });

  test('resolveOverride 强制生效', () async {
    final store = TaskStore(userId: 1);
    await store.init();
    await store.add(buildTask('a', scheduledTime: DateTime(2026, 8, 5, 10)));
    final conflict = buildTask(
      'b',
      scheduledTime: futureTime(10, 30),
      resource: '会议室A',
      durationMinutes: 60,
    );
    await store.addWithConflictCheck(conflict);
    await store.resolveOverride(store.getById('b')!);
    final saved = store.getById('b')!;
    expect(saved.conflictState, ConflictState.confirmedOverride);
    expect(saved.effective, isTrue);
  });

  test('toggleDone：重复任务完成今天后滚动到下次且保持 pending', () async {
    final store = TaskStore(userId: 1);
    await store.init();
    final daily = buildTask(
      '晨跑',
      scheduledTime: DateTime(2026, 8, 5, 7),
      repeat: RepeatType.daily,
    );
    await store.add(daily);
    final now = DateTime(2026, 8, 5, 8);
    await store.toggleDoneAt(store.getById('晨跑')!, now);
    final saved = store.getById('晨跑')!;
    expect(saved.status, TaskStatus.pending);
    expect(saved.completedAt, now);
    expect(saved.scheduledTime, isNot(DateTime(2026, 8, 5, 7)));
  });

  test('init 后按创建时间降序返回（新任务在前）', () async {
    final dao = TaskDao();
    Task make(String id, DateTime created) => Task(
          id: id,
          title: id,
          scheduledTime: DateTime(2026, 8, 5, 9),
          createdAt: created,
          notificationId: 1,
        );
    await dao.insert(make('老任务', DateTime(2026, 8, 1)), userId: 1);
    await dao.insert(make('新任务', DateTime(2026, 8, 5)), userId: 1);
    final store = TaskStore(userId: 1);
    await store.init();
    expect(store.all.map((t) => t.id), ['新任务', '老任务']);
  });

  test('toggleDone：倒计时重复推进次数，达到上限后完成（死任务）', () async {
    final store = TaskStore(userId: 1);
    await store.init();
    final delayed = Task(
      id: '喝水',
      title: '喝水',
      scheduledTime: DateTime(2026, 8, 5, 8, 0),
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 2,
      repeatCount: 0,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    await store.add(delayed);
    final now = DateTime(2026, 8, 5, 8, 10);
    await store.toggleDoneAt(store.getById('喝水')!, now);
    var saved = store.getById('喝水')!;
    expect(saved.status, TaskStatus.pending);
    expect(saved.repeatCount, 1);
    expect(saved.nextFireTime, DateTime(2026, 8, 5, 8, 30));
    // 第二次完成达到上限 → 死任务（done）
    await store.toggleDoneAt(store.getById('喝水')!, now);
    saved = store.getById('喝水')!;
    expect(saved.status, TaskStatus.done);
    expect(saved.isDeadDoneAt(now), isTrue);
  });
}
