// ThemeController 单元测试：加载/持久化三档、无效值兜底与相同档位去重
import 'package:daily_planner/data/daos/app_settings_dao.dart';
import 'package:daily_planner/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版设备级设置替身。
class FakeAppSettings extends AppSettingsDao {
  final Map<String, String> store = {};

  @override
  Future<String?> get(String key) async => store[key];

  @override
  Future<void> set(String key, String value) async {
    store[key] = value;
  }
}

void main() {
  test('无持久化记录时默认跟随系统', () async {
    final dao = FakeAppSettings();
    final controller = ThemeController(dao: dao);
    await controller.load();
    expect(controller.mode, ThemeMode.system);
  });

  test('load 读取持久化档位并通知监听者', () async {
    final dao = FakeAppSettings()
      ..store[AppSettingsDao.kThemeModeKey] = 'dark';
    final controller = ThemeController(dao: dao);
    var notified = 0;
    controller.addListener(() => notified++);
    await controller.load();
    expect(controller.mode, ThemeMode.dark);
    expect(notified, 1);
  });

  test('load 遇到非法值保持跟随系统', () async {
    final dao = FakeAppSettings()
      ..store[AppSettingsDao.kThemeModeKey] = 'sepia';
    final controller = ThemeController(dao: dao);
    await controller.load();
    expect(controller.mode, ThemeMode.system);
  });

  test('setMode 持久化并通知；相同档位不重复写库', () async {
    final dao = FakeAppSettings();
    final controller = ThemeController(dao: dao);
    await controller.setMode(ThemeMode.light);
    expect(controller.mode, ThemeMode.light);
    expect(dao.store[AppSettingsDao.kThemeModeKey], 'light');
    // 相同档位：不再触发通知与写库
    var notified = 0;
    controller.addListener(() => notified++);
    await controller.setMode(ThemeMode.light);
    expect(notified, 0);
    expect(dao.store[AppSettingsDao.kThemeModeKey], 'light');
  });
}
