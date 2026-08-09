import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';

/// 设备级设置 DAO：读写 `app_settings` 键值表。
///
/// 用于深色模式三档（theme_mode）与播报音色（tts_voice_id）——
/// 均为设备级偏好，与具体用户无关（登录前也需生效）。
///
/// 注意：单例数据库连接，App 内顺序读写即可；写入使用 replace 覆盖语义。
class AppSettingsDao {
  AppSettingsDao({Database? db}) : _db = db;

  final Database? _db;

  /// 深色模式档位键（值：system / light / dark）
  static const String kThemeModeKey = 'theme_mode';

  /// 播报音色标识键（值：语音 key，空串/缺省 = 系统默认音色）
  static const String kTtsVoiceIdKey = 'tts_voice_id';

  Future<Database> get _database async =>
      _db ?? DatabaseHelper.instance.database;

  /// 读取指定键的值；不存在或读取失败时返回 null（调用方按默认值处理）。
  Future<String?> get(String key) async {
    try {
      final rows = await (await _database).query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      // 表不存在（旧库未迁移）等异常按未设置处理，不阻断业务
      return null;
    }
  }

  /// 写入（upsert）指定键值。
  Future<void> set(String key, String value) async {
    final db = await _database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
