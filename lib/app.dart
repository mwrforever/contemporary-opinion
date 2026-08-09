import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/models/user.dart';
import 'screens/login_page.dart';
import 'screens/main_page.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/legacy_migration.dart';
import 'services/legacy_notebook_migration.dart';
import 'services/reminder_service.dart';
import 'services/task_store.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// 登录成功后钩子：可用于旧数据迁移等一次性的启动期任务。
typedef LoggedInHook = Future<void> Function(int userId);

/// 默认钩子：尽力迁移旧版 Hive 任务数据（幂等，失败静默）。
Future<void> _migrateLegacyData(int userId) async {
  await LegacyMigrationService().migrate(userId: userId);
  await LegacyNotebookMigration().migrate(userId);
}

/// 应用根组件：全局主题 + 路由守卫。
///
/// 启动时经 [AuthGate] 读取本地 session：
/// 已登录直接进 [MainPage]，未登录先展示品牌 [SplashScreen] 再进 [LoginPage]。
class App extends StatefulWidget {
  /// 测试注入用；生产环境由 [AuthGate] 自建默认实现
  final AuthService? authService;

  /// 登录后钩子：生产默认执行旧数据迁移；测试注入空实现避免真实异步
  final LoggedInHook? onLoggedIn;

  /// 测试注入用；生产由 MainPage 自建
  final TaskStore? taskStore;
  final ReminderService? reminder;

  /// 测试注入用；生产由 App 自建并负责加载/持久化主题档位
  final ThemeController? theme;

  const App({
    super.key,
    this.authService,
    this.onLoggedIn,
    this.taskStore,
    this.reminder,
    this.theme,
  });

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  /// 全局主题控制器：跟随系统/浅色/深色三档，持久化于设备级设置。
  late final ThemeController _theme = widget.theme ?? ThemeController();

  @override
  void initState() {
    super.initState();
    // 启动期异步加载持久化主题档位（读取失败保持跟随系统）
    unawaited(_theme.load());
  }

  @override
  Widget build(BuildContext context) {
    // 监听主题档位变更，即时重建 MaterialApp（登录前页面同样生效）
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => ThemeScope(
        controller: _theme,
        child: MaterialApp(
          title: '时说',
          debugShowCheckedModeBanner: false,
          // 全应用固定中文：日期/时间选择器等组件文案（确定/取消、星期月份）均为中文
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _theme.mode,
          home: AuthGate(
            authService: widget.authService ?? AuthService(),
            onLoggedIn: widget.onLoggedIn ?? _migrateLegacyData,
            taskStore: widget.taskStore,
            reminder: widget.reminder,
            theme: _theme,
          ),
        ),
      ),
    );
  }
}

/// 路由守卫：读 session 决定进入登录流程或主界面。
class AuthGate extends StatefulWidget {
  final AuthService authService;
  final LoggedInHook onLoggedIn;
  final TaskStore? taskStore;
  final ReminderService? reminder;
  final ThemeController? theme;

  const AuthGate({
    super.key,
    required this.authService,
    required this.onLoggedIn,
    this.taskStore,
    this.reminder,
    this.theme,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<User?> _user = _resolve();

  Future<User?> _resolve() async {
    final user = await widget.authService.currentUser();
    if (user != null) {
      // 登录成功后的启动期任务（旧数据迁移等），异常已由钩子内部兜底
      await widget.onLoggedIn(user.id ?? 0);
    }
    return user;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _user,
      builder: (context, snapshot) {
        // session 读取中：极短加载态，不展示品牌（FEATURES 约定）
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final user = snapshot.data;
        if (user == null) return const SplashScreen();
        return MainPage(
          authService: widget.authService,
          userId: user.id ?? 0,
          taskStore: widget.taskStore,
          reminder: widget.reminder,
          theme: widget.theme,
        );
      },
    );
  }
}
