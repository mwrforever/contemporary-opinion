import 'package:daily_planner/data/models/user.dart';
import 'package:daily_planner/services/auth_service.dart';

/// 测试替身：内存版认证服务。
///
/// widget 测试无法在 FakeAsync 环境完成真实 SQLite/FFI 异步，
/// 故以内存实现替代；真实数据库逻辑由 auth_service_test.dart 覆盖。
class FakeAuthService extends AuthService {
  FakeAuthService({User? user}) : loggedInUser = user;

  User? loggedInUser;

  @override
  Future<AuthResult> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    if (loggedInUser?.username == username || username == 'xiaoxu') {
      return const AuthResult(ok: false, error: '用户名已被占用');
    }
    loggedInUser = User(
      id: 1,
      username: username,
      passwordHash: 'fake',
      nickname: nickname,
      createdAt: DateTime(2026, 8, 5),
    );
    return AuthResult(ok: true, user: loggedInUser);
  }

  @override
  Future<AuthResult> login(String username, String password) async {
    final user = loggedInUser;
    if (user == null ||
        user.username != username ||
        password != 'mima123456') {
      return const AuthResult(ok: false, error: '用户名或密码错误');
    }
    return AuthResult(ok: true, user: user);
  }

  @override
  Future<User?> currentUser() async => loggedInUser;

  @override
  Future<void> logout() async => loggedInUser = null;
}
