import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/widgets/empty_state.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 组件冒烟测试（可选）。
///
/// 完整 MyApp 依赖 Hive / 本地通知 / 音频 / 语音等平台插件，在 headless 的
/// `flutter test` 环境下无法初始化，因此这里只对「无平台依赖」的纯 UI 叶子组件
/// 做冒烟断言，确保 widget 树能正常构建、关键文案可见、不抛错。
void main() {
  testWidgets('EmptyState 渲染并包含首屏引导文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: const EmptyState(),
        ),
      ),
    );
    // 首屏「无任务」时空状态的主标题与副标题
    expect(find.text('还没有安排'), findsOneWidget);
    expect(find.text('点右下角 +，手动添加或语音录入都行。'), findsOneWidget);
  });

  testWidgets('TaskCard 渲染任务标题与待安排标签', (tester) async {
    final task = Task(
      id: 'c1',
      title: '买菜',
      createdAt: DateTime(2026, 7, 14),
      notificationId: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskCard(
            task: task,
            onTap: () {},
            onToggle: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.text('买菜'), findsOneWidget);
    // scheduledTime 为 null 时应显示「待安排」
    expect(find.text('待安排'), findsOneWidget);
  });
}
