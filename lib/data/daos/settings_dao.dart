import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../models/reminder_settings.dart';

/// 用户提醒设置 DAO：读写 user_settings 单行记录（按 user_id）。
class SettingsDao {
  SettingsDao({Database? db}) : _db = db;

  final Database? _db;

  Future<Database> get _database async =>
      _db ?? DatabaseHelper.instance.database;

  /// 读取提醒设置；无记录时返回默认值（语音播报 + 震动 + 音量 60）。
  Future<ReminderSettings> get(int userId) async {
    final rows = await (await _database).query(
      'user_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return const ReminderSettings();
    return ReminderSettings.fromRow(rows.first);
  }

  /// 保存提醒设置（upsert）。
  Future<void> save(int userId, ReminderSettings settings) async {
    final db = await _database;
    await db.insert(
      'user_settings',
      settings.toRow(userId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
