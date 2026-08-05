// 登录页测试：必填校验、密码显隐、错误提示、登录成功导航
import 'package:daily_planner/data/models/user.dart';
import 'package:daily_planner/screens/login_page.dart';
import 'package:flutter/material.dart';
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

  Future<void> pumpLogin(WidgetTester tester, FakeAuthService auth) async {
    await tester.pumpWidget(MaterialApp(home: LoginPage(authService: auth)));
  }

  testWidgets('空表单提交提示用户名与密码必填', (tester) async {
    await pumpLogin(tester, FakeAuthService());
    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('用户名不能为空'), findsOneWidget);
    expect(find.text('密码至少 6 位'), findsOneWidget);
  });

  testWidgets('密码框支持显隐切换', (tester) async {
    await pumpLogin(tester, FakeAuthService());
    await tester.enterText(find.byType(TextField).at(1), 'mima123456');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
      isFalse,
    );
  });

  testWidgets('密码错误提示「用户名或密码错误」', (tester) async {
    await pumpLogin(tester, FakeAuthService(user: buildUser()));
    await tester.enterText(find.byType(TextField).at(0), 'xiaoxu');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-pass');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.text('用户名或密码错误'), findsOneWidget);
  });

  testWidgets('登录成功进入主界面', (tester) async {
    await pumpLogin(tester, FakeAuthService(user: buildUser()));
    await tester.enterText(find.byType(TextField).at(0), 'xiaoxu');
    await tester.enterText(find.byType(TextField).at(1), 'mima123456');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.text('任务'), findsWidgets);
  });
}
