// 我的页测试：资料渲染/编辑、备份导出导入、提醒设置入口、退出登录
import 'package:daily_planner/data/models/user.dart';
import 'package:daily_planner/screens/profile_page.dart';
import 'package:daily_planner/services/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_service.dart';
import 'support/fakes.dart';

/// 备份服务替身：记录调用并返回固定结果，避免触碰平台插件
class FakeBackup extends BackupService {
  int exportCalls = 0;
  String? importedJson;

  @override
  Future<String> exportJson(int userId) async {
    exportCalls++;
    return '{}';
  }

  @override
  Future<void> shareExport(String fileName, String json) async {}

  @override
  Future<String?> pickImportFile() async => '{"version":1,"tasks":[]}';

  @override
  Future<int> importJson(int userId, String json) async {
    importedJson = json;
    return 3;
  }
}

void main() {
  late FakeAuthService auth;
  late FakeBackup backup;

  User buildUser() => User(
        id: 1,
        username: 'xiaoxu',
        passwordHash: 'fake',
        nickname: '小许',
        defaultRingSeconds: 30,
        createdAt: DateTime(2026, 8, 5),
      );

  setUp(() {
    auth = FakeAuthService(user: buildUser());
    backup = FakeBackup();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          auth: auth,
          backup: backup,
          reminder: buildFakeReminder(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染昵称、用户名与默认响铃', (tester) async {
    await pumpPage(tester);
    expect(find.text('小许'), findsWidgets);
    expect(find.text('@xiaoxu · 本地账户'), findsOneWidget);
    expect(find.text('30 秒'), findsOneWidget);
  });

  testWidgets('编辑昵称持久化并刷新', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('编辑昵称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新昵称');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(auth.loggedInUser!.nickname, '新昵称');
    expect(find.text('新昵称'), findsWidgets);
  });

  testWidgets('导出数据调用备份服务并提示', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('导出数据'));
    await tester.pumpAndSettle();
    expect(backup.exportCalls, 1);
    expect(find.text('备份已生成，请保存到安全位置'), findsOneWidget);
  });

  testWidgets('导入数据提示条数', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('导入数据'));
    await tester.pumpAndSettle();
    expect(backup.importedJson, '{"version":1,"tasks":[]}');
    expect(find.text('已导入 3 条任务'), findsOneWidget);
  });

  testWidgets('提醒设置入口打开引导页', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('提醒设置'));
    await tester.pumpAndSettle();
    expect(find.text('开启提醒，日程不迟到'), findsOneWidget);
  });

  testWidgets('退出登录回到登录页并清空 session', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(auth.loggedInUser, isNull);
  });
}
