import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/user.dart';

/// 用户表 DAO：注册写入、按用户名/ID 查询、资料更新。
///
/// 依赖 DatabaseHelper 单例；传入 [db] 时用于测试复用同一连接。
class UserDao {
  UserDao({Database? db}) : _db = db;

  final Database? _db;

  Future<Database> get _database async =>
      _db ?? DatabaseHelper.instance.database;

  /// 插入用户，返回自增主键 id
  Future<int> insert(User user) async =>
      (await _database).insert('users', user.toMap());

  /// 按用户名精确查询（username 唯一），不存在返回 null
  Future<User?> findByUsername(String username) async {
    final rows = await (await _database).query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  /// 按主键查询，不存在返回 null
  Future<User?> findById(int id) async {
    final rows = await (await _database).query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  /// 更新用户资料（按 id 定位）
  Future<void> update(User user) async {
    await (await _database).update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }
}
