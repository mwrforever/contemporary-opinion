import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ConfirmDialog 组件测试（T02）。
///
/// 覆盖：确认回调返回 true 且确认按钮为 danger 样式、
/// 取消回调返回 false、点击遮罩（barrier）返回 false。
void main() {
  group('ConfirmDialog - 确认/取消回调与 danger 样式', () {
    testWidgets('点击确认返回 true 且确认按钮为 danger 样式', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await ConfirmDialog.show(
                  tester.element(find.byType(TextButton)),
                  '清空已完成任务',
                  '将删除所有已完成任务，此操作不可撤销。',
                  '清空',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('清空已完成任务'), findsOneWidget);
      expect(find.text('将删除所有已完成任务，此操作不可撤销。'), findsOneWidget);

      // 确认按钮为 FilledButton 且背景色为 AppTheme.danger
      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '清空'),
      );
      expect(confirmBtn.style?.backgroundColor?.resolve({}), AppTheme.danger);

      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('点击取消返回 false', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await ConfirmDialog.show(
                  tester.element(find.byType(TextButton)),
                  '清空已完成任务',
                  '说明',
                  '清空',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('点击遮罩（barrier）返回 false', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await ConfirmDialog.show(
                  tester.element(find.byType(TextButton)),
                  '删除打卡点',
                  '确定删除吗？',
                  '删除',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 点击对话框外的空白区域（遮罩）
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
