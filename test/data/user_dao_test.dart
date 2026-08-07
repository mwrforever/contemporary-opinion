// UserDao 单元测试：插入/查询/更新/唯一约束
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/user_dao.dart';
import 'package:daily_planner/data/models/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
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

  User buildUser({String username = 'xiaoxu'}) => User(
        username: username,
        passwordHash: 'hash',
        nickname: '小许',
        createdAt: DateTime(2026, 8, 5),
      );

  test('插入后可按用户名与 ID 查询到同一用户', () async {
    final dao = UserDao();
    final id = await dao.insert(buildUser());
    final byName = await dao.findByUsername('xiaoxu');
    final byId = await dao.findById(id);
    expect(byName, isNotNull);
    expect(byName!.nickname, '小许');
    expect(byId, isNotNull);
    expect(byId!.username, 'xiaoxu');
    expect(byId.id, id);
  });

  test('update 生效：昵称与默认响铃时长可被更新', () async {
    final dao = UserDao();
    final id = await dao.insert(buildUser());
    final original = await dao.findById(id);
    await dao.update(
      original!.copyWith(nickname: '新昵称', defaultRingSeconds: 30),
    );
    final updated = await dao.findById(id);
    expect(updated!.nickname, '新昵称');
    expect(updated.defaultRingSeconds, 30);
  });

  test('重复用户名插入抛 DatabaseException（username UNIQUE）', () async {
    final dao = UserDao();
    await dao.insert(buildUser());
    await expectLater(
      dao.insert(buildUser()),
      throwsA(isA<DatabaseException>()),
    );
  });
}
