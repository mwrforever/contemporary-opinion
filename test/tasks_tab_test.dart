// TasksTab 交互测试：筛选计数、确认覆盖、勾选完成、滑动删除、选择模式、Speed Dial
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/modules/tasks/tasks_tab.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeTaskStore store;

  setUp(() {
    store = FakeTaskStore();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TasksTab(store: store, reminder: buildFakeReminder()),
      ),
    );
    await tester.pump();
  }

  Task task(
    String id, {
    DateTime? at,
    String? resource,
    int duration = 0,
    ConflictState conflict = ConflictState.none,
    TaskStatus status = TaskStatus.pending,
  }) =>
      Task(
        id: id,
        title: id,
        scheduledTime: at ?? DateTime.now().add(const Duration(days: 1)),
        resource: resource,
        durationMinutes: duration,
        conflictState: conflict,
        effective: conflict == ConflictState.none,
        status: status,
        createdAt: DateTime(2026, 8, 1),
        notificationId: 1,
      );

  testWidgets('筛选计数与冲突卡渲染', (tester) async {
    store.seed(task('普通'));
    store.seed(task(
      '冲突',
      resource: '会议室A',
      duration: 60,
      conflict: ConflictState.pendingConflict,
    ));
    store.seed(task('已完成', status: TaskStatus.done));
    await pumpTab(tester);
    expect(find.text('资源冲突'), findsOneWidget);
    expect(find.text('确认覆盖'), findsOneWidget);
    // 全部计数角标为 3
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('确认覆盖后冲突徽标消失', (tester) async {
    store.seed(task(
      '冲突',
      resource: '会议室A',
      duration: 60,
      conflict: ConflictState.pendingConflict,
    ));
    await pumpTab(tester);
    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();
    expect(store.getById('冲突')!.conflictState, ConflictState.confirmedOverride);
    expect(find.text('资源冲突'), findsNothing);
  });

  testWidgets('勾选完成切换一次性任务为 done', (tester) async {
    store.seed(task('待办'));
    await pumpTab(tester);
    await tester.tap(find.byKey(const ValueKey('task-check-待办')));
    await tester.pumpAndSettle();
    expect(store.getById('待办')!.status, TaskStatus.done);
  });

  testWidgets('滑动删除需二次确认', (tester) async {
    store.seed(task('要删的'));
    await pumpTab(tester);
    await tester.fling(find.byType(TaskCard), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('删除任务'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.getById('要删的'), isNull);
  });

  testWidgets('长按进入选择模式并批量删除', (tester) async {
    store.seed(task('A'));
    store.seed(task('B'));
    await pumpTab(tester);
    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.all, isEmpty);
  });

  testWidgets('Speed Dial 手动新增打开新建任务页', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动新增'));
    await tester.pumpAndSettle();
    expect(find.text('新建任务'), findsOneWidget);
  });
}
