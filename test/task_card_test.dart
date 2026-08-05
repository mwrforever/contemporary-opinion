// TaskCard 状态测试：冲突/时间待定/已完成/已逾期渲染与回调
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({
    String title = '任务',
    ConflictState conflict = ConflictState.none,
    TaskStatus status = TaskStatus.pending,
  }) =>
      Task(
        id: 'id',
        title: title,
        scheduledTime: DateTime(2026, 8, 6, 10),
        resource: '会议室A',
        conflictState: conflict,
        effective: conflict == ConflictState.none,
        status: status,
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  Future<void> pump(WidgetTester tester, Task t, {VoidCallback? onConfirm}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(task: t, onConfirmOverride: onConfirm),
        ),
      ),
    );
  }

  testWidgets('冲突态：红徽标与确认覆盖回调', (tester) async {
    var confirmed = false;
    await pump(
      tester,
      task(conflict: ConflictState.pendingConflict),
      onConfirm: () => confirmed = true,
    );
    expect(find.text('资源冲突'), findsOneWidget);
    await tester.tap(find.text('确认覆盖'));
    expect(confirmed, isTrue);
  });

  testWidgets('时间待定态提示补时间', (tester) async {
    await pump(tester, task(conflict: ConflictState.undated));
    expect(find.text('时间待定，补时间后生效'), findsOneWidget);
    expect(find.text('设时间'), findsOneWidget);
  });

  testWidgets('已完成态展示勾选', (tester) async {
    await pump(tester, task(status: TaskStatus.done));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('已逾期徽标', (tester) async {
    await pump(tester, task(status: TaskStatus.missed));
    expect(find.text('已逾期'), findsOneWidget);
  });
}
