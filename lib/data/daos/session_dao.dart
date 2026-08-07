import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/session.dart';

/// 登录态会话 DAO：session 表恒为单行（id=1），写入即覆盖。
///
/// 登出时调用 [write] 传入 userId=null 且 isLoggedIn=false，
/// 避免悬挂无效 user_id 触发外键约束。
class SessionDao {
  SessionDao({Database? db}) : _db = db;

  final Database? _db;

  Future<Database> get _database async =>
      _db ?? DatabaseHelper.instance.database;

  /// 覆盖写入当前登录态（恒为 id=1 单行）
  Future<void> write(int? userId, bool isLoggedIn) async {
    await (await _database).insert(
      'session',
      {
        'id': 1,
        'user_id': userId,
        'is_logged_in': isLoggedIn ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取当前登录态；从未写入时返回 null
  Future<Session?> read() async {
    final rows = await (await _database).query(
      'session',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Session(
      userId: row['user_id'] as int?,
      isLoggedIn: (row['is_logged_in'] as int) == 1,
    );
  }
}
