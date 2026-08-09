import 'package:flutter/material.dart';

import '../data/daos/app_settings_dao.dart';

/// 全局主题控制器：持有深色模式三档（跟随系统/浅色/深色）状态。
///
/// 负责从设备级 `app_settings` 加载与持久化主题档位，变更时通知
/// [ListenableBuilder] 重建 [MaterialApp]（登录前页面同样生效）。
///
/// 注意：非线程安全，仅 UI 主线程使用；读/写失败时静默保持跟随系统，
/// 保证旧版本库或测试环境不阻断启动。
class ThemeController extends ChangeNotifier {
  ThemeController({AppSettingsDao? dao}) : _dao = dao ?? AppSettingsDao();

  final AppSettingsDao _dao;

  ThemeMode _mode = ThemeMode.system;

  /// 当前主题档位（默认跟随系统）。
  ThemeMode get mode => _mode;

  /// 从设备级设置加载主题档位；无记录或读取失败时保持跟随系统。
  Future<void> load() async {
    try {
      final raw = await _dao.get(AppSettingsDao.kThemeModeKey);
      if (raw == null) return;
      final parsed = ThemeMode.values
          .where((m) => m.name == raw)
          .firstOrNull;
      if (parsed == null) return;
      _mode = parsed;
      notifyListeners();
    } catch (_) {
      // 读取失败保持默认跟随系统，不阻断启动
    }
  }

  /// 设置并持久化主题档位，立即生效。
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _dao.set(AppSettingsDao.kThemeModeKey, mode.name);
    } catch (_) {
      // 持久化失败不阻断本次切换，下次启动回退默认档位
    }
  }
}

/// 全局主题作用域：向整棵 widget 树暴露唯一的 [ThemeController]。
///
/// 由 [App] 包在 MaterialApp 外层，登录页 / 注册页 / 主界面 / 我的页均可
/// 通过 [ThemeScope.of] 拿到同一个控制器，保证「深色模式」切换全局即时生效
/// （修复此前登录流程各自新建控制器导致切换无效的问题）。
///
/// 注意：仅 UI 主线程使用；未包 [ThemeScope] 的测试环境回退新建独立控制器。
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 取当前作用域的控制器；无作用域（如独立测试）时回退独立实例。
  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    return scope?.notifier ?? ThemeController();
  }
}
