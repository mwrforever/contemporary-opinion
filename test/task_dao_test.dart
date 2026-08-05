// TaskDao 单元测试：增删改查、user_id 隔离、状态/生效过滤
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/task_dao.dart';
import 'package:daily_planner/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    for (final i in [1, 2]) {
      await db.insert('users', {
        'username': 'user$i',
        'password_hash': 'hash',
        'created_at': '2026-08-05T00:00:00',
      });
    }
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Task buildTask(String id, {int userId = 1, String status = 'pending'}) =>
      Task(
        id: id,
        title: '任务$id',
        scheduledTime: DateTime(2026, 8, 5, 10, 0),
        status: TaskStatus.values.byName(status),
        conflictState: status == 'pending'
            ? ConflictState.pendingConflict
            : ConflictState.none,
        effective: status != 'pending',
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  test('insert 后 findById 可读回', () async {
    final dao = TaskDao();
    await dao.insert(buildTask('a'), userId: 1);
    final task = await dao.findById('a');
    expect(task, isNotNull);
    expect(task!.title, '任务a');
  });

  test('listByUser 按 user_id 隔离', () async {
    final dao = TaskDao();
    await dao.insert(buildTask('a'), userId: 1);
    await dao.insert(buildTask('b'), userId: 2);
    final user1 = await dao.listByUser(1);
    final user2 = await dao.listByUser(2);
    expect(user1.map((t) => t.id), ['a']);
    expect(user2.map((t) => t.id), ['b']);
  });

  test('status 与 effectiveOnly 过滤生效', () async {
    final dao = TaskDao();
    await dao.insert(buildTask('done', status: 'done'), userId: 1);
    await dao.insert(buildTask('conflict', status: 'pending'), userId: 1);
    final done = await dao.listByUser(1, status: 'done');
    expect(done.single.id, 'done');
    final effective = await dao.listByUser(1, effectiveOnly: true);
    expect(effective.map((t) => t.id), ['done']);
  });

  test('update 与 delete 生效', () async {
    final dao = TaskDao();
    await dao.insert(buildTask('a'), userId: 1);
    final loaded = await dao.findById('a');
    loaded!.title = '改标题';
    await dao.update(loaded);
    expect((await dao.findById('a'))!.title, '改标题');
    await dao.delete('a');
    expect(await dao.findById('a'), isNull);
  });
}
