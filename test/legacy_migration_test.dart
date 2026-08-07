// 旧 Hive → SQLite 迁移测试：空库、字段映射、幂等、损坏数据容错
import 'dart:io';

import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/services/legacy_migration.dart';
import 'package:daily_planner/services/legacy_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('legacy_hive_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(LegacyTaskAdapter());
  });

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    // 目标用户：升级后首个注册用户通常为 id=1
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'legacy_owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    // 全量关闭并删除盒子，避免上一条用例的迁移标记/数据残留
    await Hive.close();
    await Hive.deleteBoxFromDisk('tasks');
    await Hive.deleteBoxFromDisk('app_meta');
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  LegacyTask buildLegacyTask() => LegacyTask(
        id: 'legacy-1',
        title: '旧会议',
        scheduledTime: DateTime(2026, 8, 1, 10, 0),
        repeatIndex: 2, // weekly
        customWeekdays: const [3],
        statusIndex: 0, // pending
        sourceIndex: 1, // voice
        createdAt: DateTime(2026, 7, 20),
        notificationId: 7,
        resource: '会议室A',
        conflictStateIndex: 1, // pendingConflict
        effective: false,
        durationMinutes: 60,
        ringSeconds: 30,
      );

  test('空任务 box：不写入且标记已迁移', () async {
    final migrated = await LegacyMigrationService().migrate(userId: 1);
    expect(migrated, isFalse);
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('tasks', where: 'user_id = 1');
    expect(rows, isEmpty);
    final meta = await Hive.openBox('app_meta');
    expect(meta.get('legacy_migrated'), isTrue);
  });

  test('迁移旧任务并完整映射字段、归属 user_id', () async {
    final box = await Hive.openBox<LegacyTask>('tasks');
    await box.put('legacy-1', buildLegacyTask());

    final migrated = await LegacyMigrationService().migrate(userId: 1);
    expect(migrated, isTrue);

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('tasks', where: 'user_id = 1');
    expect(rows.length, 1);
    final row = rows.first;
    expect(row['title'], '旧会议');
    expect(row['scheduled_time'], '2026-08-01T10:00:00.000');
    expect(row['repeat'], 'weekly');
    expect(row['custom_weekdays'], '[3]');
    expect(row['source'], 'voice');
    expect(row['resource'], '会议室A');
    expect(row['duration_minutes'], 60);
    expect(row['ring_seconds'], 30);
    expect(row['conflict_state'], 'pendingConflict');
    expect(row['effective'], 0);
    expect(row['notification_id'], 7);
  });

  test('二次调用幂等：不再重复写入', () async {
    final box = await Hive.openBox<LegacyTask>('tasks');
    await box.put('legacy-1', buildLegacyTask());

    final service = LegacyMigrationService();
    await service.migrate(userId: 1);
    final again = await service.migrate(userId: 1);
    expect(again, isFalse);
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('tasks', where: 'user_id = 1');
    expect(rows.length, 1);
  });

  test('box 含非任务数据：静默跳过不抛错', () async {
    final box = await Hive.openBox<dynamic>('tasks');
    await box.put('junk', '不是任务对象');

    final migrated = await LegacyMigrationService().migrate(userId: 1);
    expect(migrated, isFalse);
  });
}
