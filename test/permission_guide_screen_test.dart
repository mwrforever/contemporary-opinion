// 提醒设置引导页测试：通知权限状态回显、授权禁用态、请求回调
import 'package:daily_planner/screens/permission_guide_screen.dart';
import 'package:daily_planner/services/permission_status_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 权限状态替身：可配置通知权限状态。
class FakePermissionStatus extends PermissionStatusService {
  ReminderPermissionStatus status =
      const ReminderPermissionStatus(notification: false);

  @override
  Future<ReminderPermissionStatus> reminderStatus() async => status;
}

void main() {
  // 放大视口，确保清单与底部按钮完整构建
  Future<void> pumpGuide(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('通知权限待处理时展示状态并保留去开启按钮', (tester) async {
    await pumpGuide(
      tester,
      PermissionGuideScreen(
        permissionStatus: FakePermissionStatus(),
        onRequestNotification: () async {},
      ),
    );
    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('已开启'), findsNothing);
    expect(find.widgetWithText(FilledButton, '去开启'), findsOneWidget);
  });

  testWidgets('通知权限授权后按钮变已完成禁用态', (tester) async {
    await pumpGuide(
      tester,
      PermissionGuideScreen(
        permissionStatus: FakePermissionStatus()
          ..status = const ReminderPermissionStatus(notification: true),
        onRequestNotification: () async {},
      ),
    );
    expect(find.text('已开启'), findsOneWidget);
    final doneButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '已完成'),
    );
    expect(doneButton.onPressed, isNull);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('点击通知权限卡片触发通知请求回调', (tester) async {
    var requests = 0;
    await pumpGuide(
      tester,
      PermissionGuideScreen(
        permissionStatus: FakePermissionStatus(),
        onRequestNotification: () async => requests++,
      ),
    );
    await tester.tap(find.text('通知权限'));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });
}
