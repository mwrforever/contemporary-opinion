// 路由守卫测试：已登录直达主界面、未登录品牌页后进登录页、登出回登录页
import 'package:daily_planner/app.dart';
import 'package:daily_planner/data/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_service.dart';

void main() {
  User buildUser() => User(
        id: 1,
        username: 'xiaoxu',
        passwordHash: 'fake',
        nickname: '小许',
        createdAt: DateTime(2026, 8, 5),
      );

  testWidgets('已登录用户启动直达主界面，不展示品牌页', (tester) async {
    await tester.pumpWidget(
      App(
        authService: FakeAuthService(user: buildUser()),
        onLoggedIn: (_) async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('任务'), findsWidgets);
    expect(find.text('时说'), findsNothing);
  });

  testWidgets('未登录用户先见品牌页，约 1.2s 后进入登录页', (tester) async {
    await tester.pumpWidget(
      App(authService: FakeAuthService(), onLoggedIn: (_) async {}),
    );
    await tester.pump();
    expect(find.text('时说'), findsOneWidget);
    // 推进品牌展示计时器
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsWidgets);
  });

  testWidgets('在「我的」页登出后回到登录页且 session 清空', (tester) async {
    final auth = FakeAuthService(user: buildUser());
    await tester.pumpWidget(App(authService: auth, onLoggedIn: (_) async {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsWidgets);
    expect(await auth.currentUser(), isNull);
  });
}
