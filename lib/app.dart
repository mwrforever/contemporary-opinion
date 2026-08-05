import 'package:flutter/material.dart';

import 'screens/login_page.dart';
import 'screens/main_page.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/legacy_migration.dart';
import 'theme/app_theme.dart';

/// 登录成功后钩子：可用于旧数据迁移等一次性的启动期任务。
typedef LoggedInHook = Future<void> Function(int userId);

/// 默认钩子：尽力迁移旧版 Hive 任务数据（幂等，失败静默）。
Future<void> _migrateLegacyData(int userId) async {
  await LegacyMigrationService().migrate(userId: userId);
}

/// 应用根组件：全局主题 + 路由守卫。
///
/// 启动时经 [AuthGate] 读取本地 session：
/// 已登录直接进 [MainPage]，未登录先展示品牌 [SplashScreen] 再进 [LoginPage]。
class App extends StatelessWidget {
  /// 测试注入用；生产环境由 [AuthGate] 自建默认实现
  final AuthService? authService;

  /// 登录后钩子：生产默认执行旧数据迁移；测试注入空实现避免真实异步
  final LoggedInHook? onLoggedIn;

  const App({super.key, this.authService, this.onLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '时说',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: AuthGate(
        authService: authService ?? AuthService(),
        onLoggedIn: onLoggedIn ?? _migrateLegacyData,
      ),
    );
  }
}

/// 路由守卫：读 session 决定进入登录流程或主界面。
class AuthGate extends StatefulWidget {
  final AuthService authService;
  final LoggedInHook onLoggedIn;

  const AuthGate({
    super.key,
    required this.authService,
    required this.onLoggedIn,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _loggedIn = _resolve();

  Future<bool> _resolve() async {
    final user = await widget.authService.currentUser();
    if (user != null) {
      // 登录成功后的启动期任务（旧数据迁移等），异常已由钩子内部兜底
      await widget.onLoggedIn(user.id ?? 0);
    }
    return user != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loggedIn,
      builder: (context, snapshot) {
        // session 读取中：极短加载态，不展示品牌（FEATURES 约定）
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return snapshot.data == true
            ? MainPage(authService: widget.authService)
            : const SplashScreen();
      },
    );
  }
}
