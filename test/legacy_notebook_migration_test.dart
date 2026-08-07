// 旧 Hive 记事本 → SQLite 迁移测试：购物/账本/菜谱归属、幂等、损坏容错
import 'dart:io';

import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/models/notebook_ledger.dart';
import 'package:daily_planner/models/notebook_recipe.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/services/legacy_notebook_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('legacy_nb_test');
    Hive.init(tempDir.path);
  });

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
    await Hive.close();
    for (final box in [
      'notebook_shopping_carts',
      'notebook_shopping',
      'notebook_ledger',
      'notebook_recipe',
      'app_meta',
    ]) {
      await Hive.deleteBoxFromDisk(box);
    }
  });

  tearDownAll(() async {
    tempDir.deleteSync(recursive: true);
  });

  test('迁移购物/账本/菜谱并归属 user_id', () async {
    final carts = await Hive.openBox('notebook_shopping_carts');
    await carts.put(
      'c1',
      NotebookShoppingCart(
        id: 'c1',
        name: '超市',
        note: null,
        createdAt: DateTime(2026, 8, 1),
      ).toJson(),
    );
    final items = await Hive.openBox('notebook_shopping');
    await items.put(
      'i1',
      // 模拟存量旧 Hive 数据（含预期/实付双字段），验证 fromJson 实付优先兜底
      {
        'id': 'i1',
        'item': '牛奶',
        'expected_price': 10,
        'actual_price': 9.5,
        'category': '食品',
        'note': '',
        'cartId': 'c1',
        'date': '2026-08-05',
        'createdAt': '2026-08-01T00:00:00',
      },
    );
    final ledger = await Hive.openBox('notebook_ledger');
    await ledger.put(
      'l1',
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 12000,
        category: '薪资',
        date: '2026-08-05',
        note: '',
      ).toJson(),
    );
    final recipes = await Hive.openBox('notebook_recipe');
    await recipes.put(
      'r1',
      NotebookRecipe(
        id: 'r1',
        name: '红烧肉',
        category: '荤菜',
        ingredients: const ['五花肉'],
        steps: const ['炖'],
        difficulty: 'hard',
        rating: 5,
        note: '',
      ).toJson(),
    );

    final moved = await LegacyNotebookMigration().migrate(1);
    expect(moved, isTrue);
    final db = await DatabaseHelper.instance.database;
    expect((await db.query('shopping_carts', where: 'user_id = 1')).length, 1);
    expect((await db.query('shopping_items', where: 'user_id = 1')).length, 1);
    final migrated =
        (await db.query('shopping_items', where: 'user_id = 1')).single;
    expect(migrated['price'], 9.5);
    expect((await db.query('ledger', where: 'user_id = 1')).length, 1);
    expect((await db.query('recipes', where: 'user_id = 1')).length, 1);
    final meta = await Hive.openBox('app_meta');
    expect(meta.get('legacy_notebook_migrated'), isTrue);
  });

  test('幂等：二次迁移返回 false 且不重复写入', () async {
    final ledger = await Hive.openBox('notebook_ledger');
    await ledger.put(
      'l1',
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 1,
        category: '',
        date: '',
        note: '',
      ).toJson(),
    );
    final migration = LegacyNotebookMigration();
    await migration.migrate(1);
    expect(await migration.migrate(1), isFalse);
    final db = await DatabaseHelper.instance.database;
    expect((await db.query('ledger', where: 'user_id = 1')).length, 1);
  });

  test('损坏值跳过不中断', () async {
    final ledger = await Hive.openBox('notebook_ledger');
    await ledger.put('junk', '不是对象');
    final moved = await LegacyNotebookMigration().migrate(1);
    expect(moved, isFalse); // 无有效数据 → false，但不抛错
    final meta = await Hive.openBox('app_meta');
    expect(meta.get('legacy_notebook_migrated'), isTrue);
  });
}
