// SessionDao 单元测试：单行登录态写入/读取/登出清空
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/session_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  // 先落一个有效用户，满足 session.user_id 外键约束
  Future<void> seedUser(String username) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': username,
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
  }

  test('未写入时 read 返回 null', () async {
    expect(await SessionDao().read(), isNull);
  });

  test('登录写入后 read 反映登录用户，登出后清空', () async {
    final dao = SessionDao();
    await seedUser('xiaoxu');
    await dao.write(1, true);
    final loggedIn = await dao.read();
    expect(loggedIn!.isLoggedIn, isTrue);
    expect(loggedIn.userId, 1);

    // 登出：user_id 置空且 is_logged_in=false
    await dao.write(null, false);
    final loggedOut = await dao.read();
    expect(loggedOut!.isLoggedIn, isFalse);
    expect(loggedOut.userId, isNull);
  });

  test('重复写入恒为单行（id=1 覆盖）', () async {
    final dao = SessionDao();
    await seedUser('xiaoxu');
    await seedUser('zhangsan');
    await dao.write(1, true);
    await dao.write(2, true);
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('session', where: 'id = 1');
    expect(rows.length, 1);
    expect(rows.first['user_id'], 2);
  });
}
