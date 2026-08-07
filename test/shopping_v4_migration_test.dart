// v3 → v4 购物表迁移测试：去 expected_price、actual_price 改名 price、实付优先/预期兜底
import 'dart:io';

import 'package:daily_planner/data/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    // 每个用例独立临时文件库，避免 :memory: 无法触发 onUpgrade 的问题
    tempDir = await Directory.systemTemp.createTemp('shopping_v4_test_');
    dbPath = '${tempDir.path}${Platform.pathSeparator}migration.db';
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await tempDir.delete(recursive: true);
  });

  /// 手工构造 v3 库（version=3，onCreate 复刻旧 shopping_items 结构）。
  Future<Database> createV3Db() async {
    return databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              created_at TEXT NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE shopping_carts(
              id TEXT PRIMARY KEY,
              user_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              note TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )''');
          await db.execute('''
            CREATE TABLE shopping_items(
              id TEXT PRIMARY KEY,
              user_id INTEGER NOT NULL,
              cart_id TEXT,
              item TEXT NOT NULL,
              expected_price REAL,
              actual_price REAL,
              category TEXT,
              note TEXT,
              date TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
              FOREIGN KEY(cart_id) REFERENCES shopping_carts(id) ON DELETE SET NULL
            )''');
        },
      ),
    );
  }

  test('v3 库升级到 v4：shopping_items 去 expected_price、actual_price 改名 price、实付优先兜底预期', () async {
    final raw = await createV3Db();
    await raw.insert('users', {
      'username': 'u1',
      'password_hash': 'h',
      'created_at': '2026-08-01T00:00:00',
    });
    // 实付 > 0：迁移后 price = 实付
    await raw.insert('shopping_items', {
      'id': 'i1', 'user_id': 1, 'cart_id': null, 'item': '牛奶',
      'expected_price': 10, 'actual_price': 9.5, 'category': '生鲜食品',
      'note': '', 'date': '2026-08-06', 'created_at': '2026-08-06T00:00:00',
    });
    // 实付 = 0 且预期 > 0：迁移后 price = 预期（兜底）
    await raw.insert('shopping_items', {
      'id': 'i2', 'user_id': 1, 'cart_id': null, 'item': '苹果',
      'expected_price': 5, 'actual_price': 0, 'category': '生鲜食品',
      'note': '', 'date': '', 'created_at': '2026-08-06T00:00:00',
    });
    await raw.close();

    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(dbPath);
    final db = await DatabaseHelper.instance.database;

    final cols = (await db.rawQuery('PRAGMA table_info(shopping_items)'))
        .map((c) => c['name'])
        .toList();
    expect(cols, contains('price'));
    expect(cols, isNot(contains('expected_price')));
    expect(cols, isNot(contains('actual_price')));

    final rows = await db.query('shopping_items', orderBy: 'id ASC');
    expect(rows[0]['price'], 9.5);
    expect(rows[1]['price'], 5);
  });
}
