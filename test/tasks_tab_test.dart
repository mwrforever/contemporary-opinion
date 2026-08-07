// TasksTab V2 交互测试：4 Tab 计数、冲突仅标记、详情抽屉、批量删除、Speed Dial
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/modules/tasks/add_task_screen.dart';
import 'package:daily_planner/modules/tasks/task_feedback_card.dart';
import 'package:daily_planner/modules/tasks/tasks_tab.dart';
import 'package:daily_planner/modules/tasks/voice_input_screen.dart';
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
        home: TasksTab(
          store: store,
          reminder: buildFakeReminder(),
          displayName: '小许',
        ),
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
    DateTime? createdAt,
    DateTime? completedAt,
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
        completedAt: completedAt,
        createdAt: createdAt ?? DateTime(2026, 8, 1),
        notificationId: 1,
      );

  testWidgets('4 个状态 Tab 计数正确，冲突不进入进行中', (tester) async {
    final now = DateTime.now();
    store.seed(task('未来任务', at: now.add(const Duration(hours: 1))));
    store.seed(task(
      '窗口任务',
      at: now.subtract(const Duration(minutes: 10)),
      duration: 60,
    ));
    store.seed(task(
      '冲突任务',
      at: now.add(const Duration(hours: 2)),
      resource: '会议室A',
      duration: 60,
      conflict: ConflictState.pendingConflict,
    ));
    store.seed(task(
      '死任务',
      status: TaskStatus.done,
      completedAt: now,
    ));
    await pumpTab(tester);
    // 全部 4 / 进行中 2（未来 + 窗口，冲突不算）/ 冲突 1 / 已完成 1
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('冲突'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('列表页冲突仅状态标记，详情抽屉承载冲突原因与处理', (tester) async {
    store.seed(task(
      '冲突任务',
      resource: '会议室A',
      duration: 60,
      conflict: ConflictState.pendingConflict,
    ));
    await pumpTab(tester);
    // 列表页只有行内标记，不展示冲突详情与处理按钮
    expect(find.text('冲突 · 暂不生效'), findsOneWidget);
    expect(find.text('确认覆盖'), findsNothing);
    expect(find.text('冲突原因'), findsNothing);
    // 点击记录进入详情抽屉
    await tester.tap(find.text('冲突任务'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('冲突原因'), findsOneWidget);
    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();
    expect(store.getById('冲突任务')!.conflictState, ConflictState.confirmedOverride);
    expect(find.text('任务详情'), findsNothing);
  });

  testWidgets('点击普通记录进详情抽屉，完成保存后自动返回', (tester) async {
    store.seed(task('普通任务'));
    await pumpTab(tester);
    await tester.tap(find.text('普通任务'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsNothing);
  });

  testWidgets('详情抽屉可标记完成（任务完成操作收进详情）', (tester) async {
    store.seed(task('待办任务'));
    await pumpTab(tester);
    await tester.tap(find.text('待办任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-done-toggle')));
    await tester.pumpAndSettle();
    expect(store.getById('待办任务')!.status, TaskStatus.done);
  });

  testWidgets('长按进入选择模式：底部双按钮删除/取消，右上角无图标', (tester) async {
    store.seed(task('A', createdAt: DateTime(2026, 8, 2)));
    store.seed(task('B', createdAt: DateTime(2026, 8, 1)));
    await pumpTab(tester);
    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('删除（1）'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('删除（2）'), findsOneWidget);
    await tester.tap(find.text('删除（2）'));
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
    expect(find.byType(AddTaskScreen), findsOneWidget);
  });

  testWidgets('Speed Dial 语音规划打开同页底部浮层', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语音规划'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceInputScreen), findsOneWidget);
  });

  testWidgets('TaskFeedbackCard 渲染摘要与冲突/跳过计数', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TaskFeedbackCard(
            result: VoicePlanResult(added: 2, conflict: 1, skipped: 1),
          ),
        ),
      ),
    );
    expect(find.text('已添加 2 条 · 1 条冲突待处理 · 跳过 1 条'), findsOneWidget);
  });
}
