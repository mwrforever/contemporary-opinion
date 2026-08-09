// v4 → v5 迁移测试：升级后新增设备级 app_settings 键值表且可读写
import 'dart:io';

import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/app_settings_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    // 独立临时文件库，避免 :memory: 无法触发 onUpgrade 的问题
    tempDir = await Directory.systemTemp.createTemp('app_settings_v5_test_');
    dbPath = '${tempDir.path}${Platform.pathSeparator}migration.db';
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await tempDir.delete(recursive: true);
  });

  /// 手工构造 v4 库：仅建 users 表即可触发 v5 迁移（v5 只新增表，无依赖）。
  Future<Database> createV4Db() async {
    return databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              created_at TEXT NOT NULL
            )''');
        },
      ),
    );
  }

  test('v4 库升级到 v5：app_settings 表存在且读写正常', () async {
    final raw = await createV4Db();
    await raw.insert('users', {
      'username': 'u1',
      'password_hash': 'h',
      'created_at': '2026-08-01T00:00:00',
    });
    await raw.close();

    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(dbPath);
    final db = await DatabaseHelper.instance.database;

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'app_settings'",
    ));
    expect(tables, isNotEmpty);

    // 迁移后设备级设置可正常读写
    final dao = AppSettingsDao();
    expect(await dao.get(AppSettingsDao.kThemeModeKey), isNull);
    await dao.set(AppSettingsDao.kThemeModeKey, 'dark');
    expect(await dao.get(AppSettingsDao.kThemeModeKey), 'dark');
  });
}
