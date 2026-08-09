// 注册页测试：密码一致性/长度校验、用户名重复、注册成功导航
import 'package:daily_planner/data/models/user.dart';
import 'package:daily_planner/screens/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_service.dart';

void main() {
  Future<void> pumpRegister(
    WidgetTester tester,
    FakeAuthService auth,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(authService: auth)),
    );
  }

  testWidgets('两次密码不一致提示「两次输入的密码不一致」', (tester) async {
    await pumpRegister(tester, FakeAuthService());
    await tester.enterText(find.byType(TextField).at(0), 'newuser');
    await tester.enterText(find.byType(TextField).at(1), 'mima123456');
    await tester.enterText(find.byType(TextField).at(2), 'different1');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pump();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
  });

  testWidgets('密码少于 6 位提示「密码至少 6 位」', (tester) async {
    await pumpRegister(tester, FakeAuthService());
    await tester.enterText(find.byType(TextField).at(0), 'newuser');
    await tester.enterText(find.byType(TextField).at(1), '123');
    await tester.enterText(find.byType(TextField).at(2), '123');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pump();
    expect(find.text('密码至少 6 位'), findsOneWidget);
  });

  testWidgets('用户名重复提示「用户名已被占用」', (tester) async {
    final auth = FakeAuthService(
      user: User(
        id: 1,
        username: 'xiaoxu',
        passwordHash: 'fake',
        createdAt: DateTime(2026, 8, 5),
      ),
    );
    await pumpRegister(tester, auth);
    await tester.enterText(find.byType(TextField).at(0), 'xiaoxu');
    await tester.enterText(find.byType(TextField).at(1), 'mima123456');
    await tester.enterText(find.byType(TextField).at(2), 'mima123456');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pumpAndSettle();
    expect(find.text('用户名已被占用'), findsOneWidget);
  });

  testWidgets('含中文用户名被拦截，提示不能包含中文', (tester) async {
    await pumpRegister(tester, FakeAuthService());
    await tester.enterText(find.byType(TextField).at(0), '小许');
    await tester.enterText(find.byType(TextField).at(1), 'mima123456');
    await tester.enterText(find.byType(TextField).at(2), 'mima123456');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pump();
    expect(find.text('用户名不能包含中文'), findsOneWidget);
  });

  testWidgets('用户名/昵称框关闭自动纠正与联想（荣耀机型软键盘不弹的修复）', (tester) async {
    await pumpRegister(tester, FakeAuthService());
    final username = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(username.autocorrect, isFalse);
    expect(username.enableSuggestions, isFalse);
    final nickname = tester.widget<TextField>(find.byType(TextField).at(3));
    expect(nickname.autocorrect, isFalse);
    expect(nickname.enableSuggestions, isFalse);
  });

  testWidgets('注册成功进入主界面', (tester) async {
    await pumpRegister(tester, FakeAuthService());
    await tester.enterText(find.byType(TextField).at(0), 'newuser');
    await tester.enterText(find.byType(TextField).at(1), 'mima123456');
    await tester.enterText(find.byType(TextField).at(2), 'mima123456');
    await tester.enterText(find.byType(TextField).at(3), '新用户');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pumpAndSettle();
    expect(find.text('任务'), findsWidgets);
  });
}
