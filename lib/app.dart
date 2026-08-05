import 'package:flutter/material.dart';

import 'screens/login_page.dart';
import 'screens/main_page.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

/// 应用根组件：全局主题 + 路由守卫。
///
/// 启动时经 [AuthGate] 读取本地 session：
/// 已登录直接进 [MainPage]，未登录先展示品牌 [SplashScreen] 再进 [LoginPage]。
class App extends StatelessWidget {
  /// 测试注入用；生产环境由 [AuthGate] 自建默认实现
  final AuthService? authService;

  const App({super.key, this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '时说',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: AuthGate(authService: authService ?? AuthService()),
    );
  }
}

/// 路由守卫：读 session 决定进入登录流程或主界面。
class AuthGate extends StatefulWidget {
  final AuthService authService;

  const AuthGate({super.key, required this.authService});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _loggedIn = _resolve();

  Future<bool> _resolve() async {
    return await widget.authService.currentUser() != null;
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
