// BackupService 单元测试：导出不含敏感字段、导入 round-trip、损坏容错
import 'dart:convert';

import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/backup_service.dart';
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
      'password_hash': 'secret-hash',
      'nickname': '小许',
      'default_ring_seconds': 30,
      'created_at': '2026-08-05T00:00:00',
    });
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Task buildTask(String id) => Task(
        id: id,
        title: '任务$id',
        scheduledTime: DateTime(2026, 8, 6, 10),
        repeat: RepeatType.daily,
        resource: '会议室A',
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  test('导出 JSON 不含 password_hash 且含任务与偏好', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('tasks', buildTask('a').toMap(userId: 1));

    final json = await BackupService().exportJson(1);
    expect(json.contains('password_hash'), isFalse);
    expect(json.contains('secret-hash'), isFalse);
    final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
    expect(data['version'], 1);
    expect((data['user'] as Map)['nickname'], '小许');
    expect((data['tasks'] as List).length, 1);
  });

  test('导入 round-trip 恢复任务条数', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('tasks', buildTask('a').toMap(userId: 1));
    final json = await BackupService().exportJson(1);
    // 清空任务后从备份导入
    await db.delete('tasks');
    final count = await BackupService().importJson(1, json);
    expect(count, 1);
    final rows = await db.query('tasks', where: 'user_id = 1');
    expect(rows.single['title'], '任务a');
  });

  test('损坏 JSON 抛中文异常', () async {
    expect(
      () => BackupService().importJson(1, 'not-json'),
      throwsFormatException,
    );
  });

  test('格式不符（非 version 1 / 无 tasks）抛异常', () async {
    await expectLater(
      BackupService().importJson(1, '{"version":2,"tasks":[]}'),
      throwsFormatException,
    );
  });
}
