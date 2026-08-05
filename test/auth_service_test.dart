// AuthService 单元测试：注册/登录/登出/当前用户（本地账户全流程）
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/services/auth_service.dart';
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

  test('注册成功：写入登录态并返回用户与昵称', () async {
    final auth = AuthService();
    final r = await auth.register(
      username: 'xiaoxu',
      password: 'mima123456',
      nickname: '小许',
    );
    expect(r.ok, isTrue);
    expect(r.error, isNull);
    expect(r.user!.nickname, '小许');
    final current = await auth.currentUser();
    expect(current!.username, 'xiaoxu');
  });

  test('注册：重复用户名返回「用户名已被占用」', () async {
    final auth = AuthService();
    await auth.register(username: 'xiaoxu', password: 'mima123456');
    final r2 = await auth.register(
      username: 'xiaoxu',
      password: 'other123456',
    );
    expect(r2.ok, isFalse);
    expect(r2.error, '用户名已被占用');
  });

  test('注册：密码少于 6 位返回「密码至少 6 位」', () async {
    final r = await AuthService().register(
      username: 'newuser',
      password: '12345',
    );
    expect(r.ok, isFalse);
    expect(r.error, '密码至少 6 位');
  });

  test('登录：正确密码成功并写入 session', () async {
    final auth = AuthService();
    await auth.register(username: 'xiaoxu', password: 'mima123456');
    final r = await auth.login('xiaoxu', 'mima123456');
    expect(r.ok, isTrue);
    expect((await auth.currentUser())!.username, 'xiaoxu');
  });

  test('登录：密码错误返回「用户名或密码错误」', () async {
    final auth = AuthService();
    await auth.register(username: 'xiaoxu', password: 'mima123456');
    final r = await auth.login('xiaoxu', 'wrong-pass');
    expect(r.ok, isFalse);
    expect(r.error, '用户名或密码错误');
  });

  test('登出：清空 session 后 currentUser 为 null', () async {
    final auth = AuthService();
    await auth.register(username: 'xiaoxu', password: 'mima123456');
    await auth.logout();
    expect(await auth.currentUser(), isNull);
  });

  test('updateProfile：昵称与默认响铃时长持久化', () async {
    final auth = AuthService();
    await auth.register(username: 'xiaoxu', password: 'mima123456');
    await auth.updateProfile(nickname: '新昵称', defaultRingSeconds: 30);
    final user = await auth.currentUser();
    expect(user!.nickname, '新昵称');
    expect(user.defaultRingSeconds, 30);
  });
}
