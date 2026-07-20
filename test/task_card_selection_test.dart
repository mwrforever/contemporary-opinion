import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TaskCard] 选择模式相关行为测试。
///
/// 仅直接 pump [TaskCard]（包于 MaterialApp + Scaffold），不构造 [TasksTab]，
/// 避免 headless 下完整 Tab 的 ListView 假崩。覆盖：
///  - 非选择模式无勾选指示（_SelectIndicator 不渲染）
///  - 选择模式选中显示勾选
///  - 选择模式点击卡片触发 onSelect（而非编辑）
///  - 非选择模式长按触发 onLongPress
void main() {
  final base = DateTime(2020, 1, 1);

  Task _sample({DateTime? scheduledTime}) => Task(
        id: 's1',
        title: '选择测试任务',
        scheduledTime: scheduledTime,
        createdAt: base,
        notificationId: 1,
      );

  Future<void> _pumpCard(
    WidgetTester tester, {
    required Task task,
    required bool selectionMode,
    required bool selected,
    VoidCallback? onTap,
    VoidCallback? onToggle,
    VoidCallback? onDelete,
    VoidCallback? onLongPress,
    VoidCallback? onSelect,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskCard(
            task: task,
            selectionMode: selectionMode,
            selected: selected,
            onTap: onTap ?? () {},
            onToggle: onToggle ?? () {},
            onDelete: onDelete ?? () {},
            onLongPress: onLongPress,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }

  group('TaskCard 选择模式', () {
    testWidgets('非选择模式无勾选指示', (tester) async {
      await _pumpCard(
        tester,
        task: _sample(scheduledTime: DateTime(2027, 1, 1, 9, 0)),
        selectionMode: false,
        selected: false,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('选择模式选中显示勾选', (tester) async {
      await _pumpCard(
        tester,
        task: _sample(scheduledTime: DateTime(2027, 1, 1, 9, 0)),
        selectionMode: true,
        selected: true,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('选择模式点击触发 onSelect', (tester) async {
      var tapped = false;
      await _pumpCard(
        tester,
        task: _sample(scheduledTime: DateTime(2027, 1, 1, 9, 0)),
        selectionMode: true,
        selected: false,
        onSelect: () => tapped = true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TaskCard));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('非选择模式长按触发 onLongPress', (tester) async {
      var longPressed = false;
      await _pumpCard(
        tester,
        task: _sample(scheduledTime: DateTime(2027, 1, 1, 9, 0)),
        selectionMode: false,
        selected: false,
        onLongPress: () => longPressed = true,
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(TaskCard));
      await tester.pump();
      expect(longPressed, isTrue);
    });
  });
}
