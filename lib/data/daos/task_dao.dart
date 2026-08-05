import 'package:sqflite/sqflite.dart';

import '../../models/task.dart';
import '../database_helper.dart';

/// 任务表 DAO：SQLite 读写，按 user_id 隔离。
///
/// 依赖 DatabaseHelper 单例；传入 [db] 时用于测试复用同一连接。
class TaskDao {
  TaskDao({Database? db}) : _db = db;

  final Database? _db;

  Future<Database> get _database async =>
      _db ?? DatabaseHelper.instance.database;

  /// 插入任务（id 为客户端 UUID，归属 [userId]）
  Future<void> insert(Task task, {required int userId}) async {
    await (await _database).insert('tasks', task.toMap(userId: userId));
  }

  /// 按主键查询，不存在返回 null
  Future<Task?> findById(String id) async {
    final rows = await (await _database).query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Task.fromMap(rows.first);
  }

  /// 按用户列出任务；[status] 与 [effectiveOnly] 可选过滤
  Future<List<Task>> listByUser(
    int userId, {
    String? status,
    bool? effectiveOnly,
  }) async {
    final where = StringBuffer('user_id = ?');
    final args = <Object?>[userId];
    if (status != null) {
      where.write(' AND status = ?');
      args.add(status);
    }
    if (effectiveOnly == true) {
      where.write(' AND effective = 1');
    }
    final rows = await (await _database).query(
      'tasks',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'scheduled_time ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  /// 更新任务（按 id 定位）
  Future<void> update(Task task) async {
    await (await _database).update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// 删除任务
  Future<void> delete(String id) async {
    await (await _database).delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
