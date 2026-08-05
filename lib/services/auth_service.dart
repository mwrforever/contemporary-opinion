import '../data/daos/session_dao.dart';
import '../data/daos/user_dao.dart';
import '../data/models/user.dart';
import 'password_hasher.dart';

/// 注册/登录结果：ok 表示成功；error 为中文业务错误信息；user 为登录/注册后的用户
class AuthResult {
  const AuthResult({required this.ok, this.error, this.user});

  final bool ok;
  final String? error;
  final User? user;
}

/// 本地账户认证服务：注册/登录/登出/当前用户，全部在设备端完成，无网络请求。
///
/// 依赖 UserDao/SessionDao 与 PasswordHasher；
/// 登录态以 session 单行表持久化，App 重启后由路由守卫恢复。
class AuthService {
  AuthService({UserDao? userDao, SessionDao? sessionDao})
      : _userDao = userDao ?? UserDao(),
        _sessionDao = sessionDao ?? SessionDao();

  final UserDao _userDao;
  final SessionDao _sessionDao;

  /// 注册新账户：校验用户名唯一与密码长度，成功后写入 session
  Future<AuthResult> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final name = username.trim();
    if (name.isEmpty) {
      return const AuthResult(ok: false, error: '用户名不能为空');
    }
    if (password.length < 6) {
      return const AuthResult(ok: false, error: '密码至少 6 位');
    }
    if (await _userDao.findByUsername(name) != null) {
      return const AuthResult(ok: false, error: '用户名已被占用');
    }
    final nick =
        (nickname == null || nickname.trim().isEmpty) ? null : nickname.trim();
    final user = User(
      username: name,
      passwordHash: hash(password),
      nickname: nick,
      createdAt: DateTime.now(),
    );
    final id = await _userDao.insert(user);
    await _sessionDao.write(id, true);
    return AuthResult(
      ok: true,
      user: User(
        id: id,
        username: user.username,
        passwordHash: user.passwordHash,
        nickname: user.nickname,
        avatarPath: user.avatarPath,
        defaultRingSeconds: user.defaultRingSeconds,
        createdAt: user.createdAt,
      ),
    );
  }

  /// 登录：用户名与密码本地校验，成功后写入 session
  Future<AuthResult> login(String username, String password) async {
    final user = await _userDao.findByUsername(username.trim());
    if (user == null || !verify(password, user.passwordHash)) {
      return const AuthResult(ok: false, error: '用户名或密码错误');
    }
    await _sessionDao.write(user.id!, true);
    return AuthResult(ok: true, user: user);
  }

  /// 登出：清空 session（user_id 置空，避免悬挂外键）
  Future<void> logout() => _sessionDao.write(null, false);

  /// 当前登录用户：session 无效或用户已删除时返回 null
  Future<User?> currentUser() async {
    final session = await _sessionDao.read();
    if (session == null || !session.isLoggedIn || session.userId == null) {
      return null;
    }
    return _userDao.findById(session.userId!);
  }

  /// 更新当前用户资料（昵称/头像路径/默认响铃时长）；未登录时静默跳过。
  ///
  /// 传 null 表示保留原值；密码哈希不可经此修改。
  Future<void> updateProfile({
    String? nickname,
    String? avatarPath,
    int? defaultRingSeconds,
  }) async {
    final user = await currentUser();
    if (user == null) return;
    await _userDao.update(user.copyWith(
      nickname: nickname,
      avatarPath: avatarPath,
      defaultRingSeconds: defaultRingSeconds,
    ));
  }
}
