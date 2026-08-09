// AppSettingsDao 单元测试：设备级键值读写往返、缺失默认与覆盖保存
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/app_settings_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('未写入的键返回 null（调用方按默认值处理）', () async {
    final dao = AppSettingsDao();
    expect(await dao.get(AppSettingsDao.kThemeModeKey), isNull);
    expect(await dao.get(AppSettingsDao.kTtsVoiceIdKey), isNull);
  });

  test('写入后可读回，重复写入为覆盖（upsert）', () async {
    final dao = AppSettingsDao();
    await dao.set(AppSettingsDao.kThemeModeKey, 'dark');
    expect(await dao.get(AppSettingsDao.kThemeModeKey), 'dark');
    // 覆盖写
    await dao.set(AppSettingsDao.kThemeModeKey, 'light');
    expect(await dao.get(AppSettingsDao.kThemeModeKey), 'light');
    final rows = await (await DatabaseHelper.instance.database)
        .query('app_settings', where: 'key = ?', whereArgs: [AppSettingsDao.kThemeModeKey]);
    expect(rows, hasLength(1));
  });

  test('多个键互不影响，可并存', () async {
    final dao = AppSettingsDao();
    await dao.set(AppSettingsDao.kTtsVoiceIdKey, 'v-female');
    expect(await dao.get(AppSettingsDao.kTtsVoiceIdKey), 'v-female');
    expect(await dao.get(AppSettingsDao.kThemeModeKey), isNull);
  });
}
