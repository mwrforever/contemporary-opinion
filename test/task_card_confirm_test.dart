import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TaskCard] 滑动删除二次确认测试（T6 增量）。
///
/// 直接 pump [TaskCard]（包于 MaterialApp + Scaffold），模拟左滑手势（endToStart）
/// 触发 [Dismissible] 的 confirmDismiss 链路：
///  - confirmDismiss 返回 false → 回弹不删（onDelete 不调用）
///  - confirmDismiss 返回 true  → 确认删除（onDelete 被调用）
///  - confirmDismiss 为 null    → 直接放行删除
///  - selectionMode 下 direction=none，滑动不触发任何删除链路
///
/// 删除的判定以 onDelete 闭包标记为准：本测试孤立 pump 卡片，父级不会因
/// onDismissed 自动移除卡片，故不依赖 find.byType(TaskCard) 消失。
void main() {
  final base = DateTime(2020, 1, 1);

  Task _sample() => Task(
        id: 'c1',
        title: '滑动删除测试任务',
        scheduledTime: DateTime(2027, 1, 1, 9, 0),
        createdAt: base,
        notificationId: 1,
      );

  Future<void> _pumpCard(
    WidgetTester tester, {
    required Future<bool> Function()? confirmDismiss,
    required VoidCallback onDelete,
    bool selectionMode = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskCard(
            task: _sample(),
            selectionMode: selectionMode,
            selected: false,
            onTap: () {},
            onToggle: () {},
            onDelete: onDelete,
            confirmDismiss: confirmDismiss,
          ),
        ),
      ),
    );
  }

  /// 模拟一次左滑（endToStart）手势，越过多数视口宽度的 40% 阈值。
  Future<void> _swipeLeft(WidgetTester tester) async {
    final dismissible = find.byType(Dismissible);
    await tester.drag(dismissible, const Offset(-1000, 0));
    await tester.pumpAndSettle();
  }

  group('TaskCard.confirmDismiss - 二次确认', () {
    testWidgets('confirmDismiss 返回 false → onDelete 不调用，卡片保留', (tester) async {
      var deleted = false;
      await _pumpCard(
        tester,
        confirmDismiss: () async => false,
        onDelete: () => deleted = true,
      );
      await tester.pumpAndSettle();
      await _swipeLeft(tester);
      expect(deleted, isFalse, reason: '取消应回弹，不触发删除');
      expect(find.byType(TaskCard), findsOneWidget, reason: '卡片应仍在');
    });

    testWidgets('confirmDismiss 返回 true → onDelete 被调用', (tester) async {
      var deleted = false;
      await _pumpCard(
        tester,
        confirmDismiss: () async => true,
        onDelete: () => deleted = true,
      );
      await tester.pumpAndSettle();
      await _swipeLeft(tester);
      expect(deleted, isTrue, reason: '确认才删除');
    });

    testWidgets('confirmDismiss 为 null → 直接放行删除', (tester) async {
      var deleted = false;
      await _pumpCard(
        tester,
        confirmDismiss: null,
        onDelete: () => deleted = true,
      );
      await tester.pumpAndSettle();
      await _swipeLeft(tester);
      expect(deleted, isTrue, reason: '无二次确认应直接删除');
    });
  });

  group('TaskCard - 选择模式不触发滑动删除', () {
    testWidgets('selectionMode 下 Dismissible direction=none', (tester) async {
      await _pumpCard(
        tester,
        confirmDismiss: () async => true,
        onDelete: () {},
        selectionMode: true,
      );
      await tester.pumpAndSettle();
      final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
      expect(dismissible.direction, DismissDirection.none);
    });

    testWidgets('selectionMode 下左滑不触发 confirmDismiss/onDelete', (tester) async {
      var confirmed = false;
      var deleted = false;
      await _pumpCard(
        tester,
        confirmDismiss: () async {
          confirmed = true;
          return true;
        },
        onDelete: () => deleted = true,
        selectionMode: true,
      );
      await tester.pumpAndSettle();
      await _swipeLeft(tester);
      expect(confirmed, isFalse, reason: 'selectionMode 不应进入 dismiss 链路');
      expect(deleted, isFalse);
      expect(find.byType(TaskCard), findsOneWidget);
    });
  });
}
