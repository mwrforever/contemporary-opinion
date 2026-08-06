// TaskCard V2 测试：统一记录行渲染（状态图标/单行省略/冲突标记）与回调
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({
    String id = 't1',
    String title = '任务标题',
    ConflictState conflict = ConflictState.none,
    TaskStatus status = TaskStatus.pending,
  }) =>
      Task(
        id: id,
        title: title,
        scheduledTime: DateTime(2026, 8, 6, 10),
        resource: '会议室A',
        conflictState: conflict,
        effective: conflict == ConflictState.none,
        status: status,
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  Future<void> pump(
    WidgetTester tester,
    Task t, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(task: t, onTap: onTap, onLongPress: onLongPress),
        ),
      ),
    );
  }

  testWidgets('统一记录行：状态图标 + 标题 + 冲突仅标记', (tester) async {
    await pump(tester, task(conflict: ConflictState.pendingConflict));
    // 状态图标存在（冲突为红色警告图标）
    expect(find.byKey(const ValueKey('task-icon-t1')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // 冲突仅行内标记，列表页不展示冲突原因/处理按钮
    expect(find.text('冲突 · 暂不生效'), findsOneWidget);
    expect(find.text('确认覆盖'), findsNothing);
    expect(find.text('冲突原因'), findsNothing);
  });

  testWidgets('点击记录触发 onTap（进入详情抽屉）', (tester) async {
    var tapped = false;
    await pump(tester, task(), onTap: () => tapped = true);
    await tester.tap(find.text('任务标题'));
    expect(tapped, isTrue);
  });

  testWidgets('长按触发 onLongPress（进入选择模式）', (tester) async {
    var longPressed = false;
    await pump(tester, task(), onLongPress: () => longPressed = true);
    await tester.longPress(find.text('任务标题'));
    expect(longPressed, isTrue);
  });

  testWidgets('已完成任务置灰展示且不再展示冲突标记', (tester) async {
    await pump(
      tester,
      task(status: TaskStatus.done, conflict: ConflictState.none),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('冲突 · 暂不生效'), findsNothing);
  });

  testWidgets('倒计时重复任务展示进度标记', (tester) async {
    await pump(
      tester,
      Task(
        id: 't-delay',
        title: '提醒喝水',
        scheduledTime: DateTime(2026, 8, 6, 12, 40),
        triggerType: TriggerType.delayed,
        intervalSeconds: 1800,
        maxRepeats: 5,
        repeatCount: 1,
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      ),
    );
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.text('每 30 分钟 · 第 2/5 次'), findsOneWidget);
  });
}
