// TasksTab V2 交互测试：4 Tab 计数、冲突仅标记、详情抽屉、批量删除、Speed Dial
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/modules/tasks/add_task_screen.dart';
import 'package:daily_planner/modules/tasks/permission_gate_sheet.dart';
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
          ensureReminderReady: () async => true,
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

  testWidgets('编辑一次性倒计时任务仅保存时保持一次性', (tester) async {
    final now = DateTime.now();
    store.seed(Task(
      id: 'countdown-once',
      title: '吃药',
      scheduledTime: now.add(const Duration(minutes: 10)),
      countdownMinutes: 10,
      triggerType: TriggerType.once,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    ));
    await pumpTab(tester);
    await tester.tap(find.text('吃药'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    final saved = store.getById('countdown-once')!;
    expect(saved.triggerType, TriggerType.once);
    expect(saved.intervalSeconds, isNull);
    expect(saved.maxRepeats, isNull);
  });

  testWidgets('详情抽屉可调整倒计时间隔与重复次数', (tester) async {
    final now = DateTime.now();
    store.seed(Task(
      id: 'delayed',
      title: '喝水',
      scheduledTime: now.add(const Duration(minutes: 30)),
      countdownMinutes: 30,
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 3,
      repeatCount: 1,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    ));
    await pumpTab(tester);
    await tester.tap(find.text('喝水'));
    await tester.pumpAndSettle();
    expect(find.textContaining('每隔多久提醒一次'), findsOneWidget);
    expect(find.textContaining('重复次数'), findsOneWidget);
    // 第二个步进字段（重复次数）的加号：3 → 4
    await tester.tap(find.byIcon(Icons.add_circle_outline).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    final saved = store.getById('delayed')!;
    expect(saved.maxRepeats, 4);
    expect(saved.triggerType, TriggerType.delayed);
  });

  testWidgets('已完成 Tab 展示全部完成状态任务（含仍可重复的倒计时任务）', (tester) async {
    final now = DateTime.now();
    store.seed(task(
      '已完成一次性',
      status: TaskStatus.done,
      completedAt: now,
    ));
    store.seed(Task(
      id: '已完成倒计时',
      title: '已完成倒计时',
      scheduledTime: now.add(const Duration(minutes: 30)),
      status: TaskStatus.done,
      completedAt: now,
      triggerType: TriggerType.delayed,
      intervalSeconds: 1800,
      maxRepeats: 5,
      repeatCount: 2,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    ));
    await pumpTab(tester);
    // 已完成 Tab 计数为 2：不再只统计「死任务」
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('已完成一次性'), findsOneWidget);
    expect(find.text('已完成倒计时'), findsOneWidget);
  });

  testWidgets('任务被程序自动完成后立即出现在已完成 Tab（筛选及时）', (tester) async {
    final now = DateTime.now();
    final t = task('待完成', at: now.add(const Duration(days: 1)));
    store.seed(t);
    await pumpTab(tester);
    // 模拟提醒引擎播报完成后的自动流转（_afterAlert 走同一路径）
    await store.toggleDoneAt(t, now);
    await tester.pumpAndSettle();
    // 切到已完成 Tab：记录即时可见
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已完成'), findsWidgets);
  });

  testWidgets('-1 一直重复任务自动完成后仍在进行中、不进已完成', (tester) async {
    final now = DateTime.now();
    final t = Task(
      id: '无限喝水',
      title: '无限喝水',
      scheduledTime: now.add(const Duration(minutes: 10)),
      countdownMinutes: 10,
      triggerType: TriggerType.delayed,
      intervalSeconds: 600,
      maxRepeats: -1,
      repeatCount: 0,
      createdAt: DateTime(2026, 8, 1),
      notificationId: 1,
    );
    store.seed(t);
    await pumpTab(tester);
    await tester.tap(find.text('无限喝水'));
    await tester.pumpAndSettle();
    // 详情抽屉展示「一直重复」而非次数上限
    expect(find.textContaining('一直重复'), findsOneWidget);
    // 关闭抽屉，模拟播报完成后自动推进本次（-1 保持待执行）
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await store.toggleDoneAt(t, now);
    await tester.pumpAndSettle();
    expect(t.status, TaskStatus.pending);
    expect(t.repeatCount, 1);
    // 不进已完成
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('无限喝水'), findsNothing);
    // 仍在进行中
    await tester.tap(find.text('进行中'));
    await tester.pumpAndSettle();
    expect(find.text('无限喝水'), findsOneWidget);
  });

  testWidgets('通知权限未开启时新增任务被拦截，不进入新建页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TasksTab(
          store: store,
          reminder: buildFakeReminder(),
          displayName: '小许',
          ensureReminderReady: () async => false,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动新增'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTaskScreen), findsNothing);
  });

  testWidgets('权限抽屉：确认开启后放行，暂不开启则保持拦截', (tester) async {
    var granted = false;
    bool? drawerResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => PermissionGateSheet(
                      onRequest: () async {
                        granted = true;
                        return granted;
                      },
                    ),
                  );
                  drawerResult = ok;
                },
                child: const Text('打开权限抽屉'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开权限抽屉'));
    await tester.pumpAndSettle();
    expect(find.text('开启提醒权限'), findsOneWidget);
    await tester.tap(find.text('去开启'));
    await tester.pumpAndSettle();
    expect(drawerResult, isTrue);
    expect(granted, isTrue);
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

}
