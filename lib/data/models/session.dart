/// 登录态会话模型：对应 session 表（恒为单行 id=1）。
///
/// [userId] 为 null 表示未登录；[isLoggedIn] 与 userId 同时维护，
/// 以兼容「先读表再判断」的调用方式。
class Session {
  const Session({this.userId, required this.isLoggedIn});

  final int? userId;
  final bool isLoggedIn;
}
