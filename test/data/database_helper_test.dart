// DatabaseHelper 单元测试：验证建表、关键字段、唯一约束与外键约束
import 'package:daily_planner/data/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    // 测试注入：使用 FFI 内存库，避免依赖真机平台通道
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('建库后创建 users/session/tasks 三张表', () async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sqlite_master',
      where: "type='table' AND name IN ('users','session','tasks')",
    );
    expect(rows.length, 3);
  });

  test('tasks 表包含 FEATURES 3.1 全部关键业务字段', () async {
    final db = await DatabaseHelper.instance.database;
    final cols = await db.rawQuery('PRAGMA table_info(tasks)');
    final names = cols.map((c) => c['name']).toList();
    expect(
      names,
      containsAll([
        'user_id',
        'title',
        'scheduled_time',
        'countdown_minutes',
        'countdown_seconds',
        'repeat',
        'custom_weekdays',
        'status',
        'source',
        'resource',
        'duration_minutes',
        'ring_seconds',
        'conflict_state',
        'effective',
        'notification_id',
        'completed_at',
        'note',
      ]),
    );
  });

  test('users.username 唯一约束：重复用户名插入抛 DatabaseException', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'xiaoxu',
      'password_hash': 'hash-1',
      'created_at': '2026-08-05T00:00:00',
    });
    await expectLater(
      db.insert('users', {
        'username': 'xiaoxu',
        'password_hash': 'hash-2',
        'created_at': '2026-08-05T00:00:00',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('外键约束开启：不存在的 user_id 写入 tasks 抛 DatabaseException', () async {
    final db = await DatabaseHelper.instance.database;
    await expectLater(
      db.insert('tasks', {
        'user_id': 999,
        'title': '孤儿任务',
        'repeat': 'none',
        'status': 'pending',
        'source': 'manual',
        'duration_minutes': 0,
        'conflict_state': 'none',
        'effective': 1,
        'created_at': '2026-08-05T00:00:00',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v2 建库包含记事本十张表', () async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sqlite_master',
      where:
          "type='table' AND name IN ('shopping_carts','shopping_items','ledger','reading','trips','trip_days','trip_checkpoints','courses','study_records','recipes')",
    );
    expect(rows.length, 10);
  });

  test('shopping_items 删除购物车后 cart_id 置空（未分组回收）', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'u1',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    await db.insert('shopping_carts', {
      'id': 'cart-1',
      'user_id': 1,
      'name': '超市',
      'created_at': '2026-08-05T00:00:00',
    });
    await db.insert('shopping_items', {
      'id': 'item-1',
      'user_id': 1,
      'cart_id': 'cart-1',
      'item': '牛奶',
      'created_at': '2026-08-05T00:00:00',
    });
    await db.delete('shopping_carts', where: 'id = ?', whereArgs: ['cart-1']);
    final rows = await db.query('shopping_items');
    expect(rows.single['cart_id'], isNull);
  });
}
