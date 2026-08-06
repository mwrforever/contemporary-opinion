// SettingsDao 单元测试：提醒设置默认值、读写往返与覆盖保存
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/settings_dao.dart';
import 'package:daily_planner/data/models/reminder_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('无记录时返回默认值（语音 + 震动 + 音量 60）', () async {
    final dao = SettingsDao();
    final settings = await dao.get(1);
    expect(settings.mode, ReminderMode.voice);
    expect(settings.vibrate, isTrue);
    expect(settings.volume, 60);
  });

  test('保存后可读回，重复保存为覆盖（upsert）', () async {
    final dao = SettingsDao();
    await dao.save(
      1,
      const ReminderSettings(
        mode: ReminderMode.mute,
        vibrate: false,
        volume: 30,
      ),
    );
    var settings = await dao.get(1);
    expect(settings.mode, ReminderMode.mute);
    expect(settings.vibrate, isFalse);
    expect(settings.volume, 30);
    // 覆盖保存
    await dao.save(
      1,
      const ReminderSettings(
        mode: ReminderMode.voice,
        vibrate: true,
        volume: 80,
      ),
    );
    settings = await dao.get(1);
    expect(settings.mode, ReminderMode.voice);
    expect(settings.vibrate, isTrue);
    expect(settings.volume, 80);
  });
}
