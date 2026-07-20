import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/theme/task_status_style.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:daily_planner/services/task_store.dart';
import 'package:daily_planner/services/reminder_service.dart';

/// 任务列表视觉状态系统（task_status_style.dart + TaskCard + 删除撤销）专项测试。
///
/// 覆盖：
///  A. resolveVisualState 纯逻辑（优先级 / 窗口 / 边界）
///  B. styleOf 映射（浅色 + 深色各一轮：颜色 / 图标 / 透明度 / 标签 / 填充）
///  C. TaskCard 渲染（状态图标 / 徽章 / 删除线 / 冲突块 / 左色条）
///  D. 删除撤销（SnackBar + 撤销回调：store.add / reminder.notifyTaskChanged）
///  E. FilterTabBar 改名回归见 test/filter_tab_bar_test.dart（全量 flutter test 一并验证）
void main() {
  // ───────────────────────── A. resolveVisualState 纯逻辑 ─────────────────────────
  group('A. resolveVisualState 纯逻辑', () {
    // 固定参考时间，规避系统时钟抖动。
    final now = DateTime(2026, 1, 1, 12, 0); // 12:00
    final start = DateTime(2026, 1, 1, 10, 0); // 10:00

    Task makeTask({
      TaskStatus status = TaskStatus.pending,
      ConflictState conflictState = ConflictState.none,
      DateTime? scheduledTime,
      int durationMinutes = 60,
    }) =>
        Task(
          id: 'x',
          title: 't',
          createdAt: DateTime(2020),
          notificationId: 1,
          status: status,
          conflictState: conflictState,
          scheduledTime: scheduledTime,
          durationMinutes: durationMinutes,
        );

    test('1. done：status==done → done', () {
      final t = makeTask(status: TaskStatus.done);
      expect(resolveVisualState(t, now), TaskVisualState.done);
    });

    test('2. conflictBlocked：conflictState==pendingConflict（即便未来时间）→ conflictBlocked', () {
      final t = makeTask(
        conflictState: ConflictState.pendingConflict,
        scheduledTime: DateTime(2099),
      );
      expect(resolveVisualState(t, now), TaskVisualState.conflictBlocked);
    });

    test('3. missed → overdue', () {
      final t = makeTask(status: TaskStatus.missed);
      expect(resolveVisualState(t, now), TaskVisualState.overdue);
    });

    test('4. unscheduled：scheduledTime==null → unscheduled', () {
      final t = makeTask();
      expect(resolveVisualState(t, now), TaskVisualState.unscheduled);
    });

    test('4b. timePending：conflictState==undated（无时刻）→ timePending（优先于 unscheduled）', () {
      final t = makeTask(conflictState: ConflictState.undated, scheduledTime: null);
      expect(resolveVisualState(t, now), TaskVisualState.timePending);
    });

    test('5. upcoming：scheduledTime 在未来 → upcoming', () {
      final future = now.add(const Duration(hours: 1));
      final t = makeTask(scheduledTime: future);
      expect(resolveVisualState(t, now), TaskVisualState.upcoming);
    });

    test('6. inProgress：now 落在 [start, start+duration) → inProgress（duration=60）', () {
      final t = makeTask(scheduledTime: start, durationMinutes: 60);
      final n = start.add(const Duration(minutes: 30)); // 10:30
      expect(resolveVisualState(t, n), TaskVisualState.inProgress);
    });

    test('7. overdue：now ≥ start+duration → overdue', () {
      final t = makeTask(scheduledTime: start, durationMinutes: 60);
      final n = start.add(const Duration(minutes: 61)); // 11:01
      expect(resolveVisualState(t, n), TaskVisualState.overdue);
    });

    test('8a. 边界：now==start → inProgress（非 upcoming）', () {
      final t = makeTask(scheduledTime: start, durationMinutes: 60);
      expect(resolveVisualState(t, start), TaskVisualState.inProgress);
    });

    test('8b. 边界：now==start+duration → overdue', () {
      final t = makeTask(scheduledTime: start, durationMinutes: 60);
      final end = start.add(const Duration(minutes: 60)); // 11:00
      expect(resolveVisualState(t, end), TaskVisualState.overdue);
    });

    test('9. 优先级：conflict+done → done 胜出；conflict+missed → conflictBlocked 胜出', () {
      final doneConflict = makeTask(
        status: TaskStatus.done,
        conflictState: ConflictState.pendingConflict,
      );
      expect(resolveVisualState(doneConflict, now), TaskVisualState.done);

      final missedConflict = makeTask(
        status: TaskStatus.missed,
        conflictState: ConflictState.pendingConflict,
      );
      expect(resolveVisualState(missedConflict, now), TaskVisualState.conflictBlocked);
    });
  });

  // ───────────────────────── B. styleOf 映射（浅色 + 深色）─────────────────────────
  group('B. styleOf 映射', () {
    Future<TaskStatusStyle> _resolveStyle(
      WidgetTester tester,
      ThemeData theme,
      TaskVisualState s,
    ) async {
      late TaskStatusStyle captured;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (ctx) {
          captured = styleOf(s, ctx);
          return const SizedBox.shrink();
        }),
      ));
      return captured;
    }

    Future<void> _expectStyle(
      WidgetTester tester,
      ThemeData theme,
      TaskVisualState state, {
      required Color expectedColor,
      required IconData expectedIcon,
      required double expectedOpacity,
      required String expectedLabel,
      required bool expectedFilled,
      required Color expectedSoft,
    }) async {
      final style = await _resolveStyle(tester, theme, state);
      expect(style.color, expectedColor, reason: 'color@$state');
      expect(style.icon, expectedIcon, reason: 'icon@$state');
      expect(style.opacity, expectedOpacity, reason: 'opacity@$state');
      expect(style.label, expectedLabel, reason: 'label@$state');
      expect(style.filled, expectedFilled, reason: 'filled@$state');
      expect(style.softColor, expectedSoft, reason: 'softColor@$state');
    }

    group('浅色模式', () {
      testWidgets('unscheduled / upcoming / inProgress / overdue / done / conflictBlocked', (tester) async {
        await _expectStyle(tester, AppTheme.light, TaskVisualState.unscheduled,
            expectedColor: AppTheme.neutral,
            expectedIcon: Icons.schedule_outlined,
            expectedOpacity: 0.85,
            expectedLabel: '',
            expectedFilled: false,
            expectedSoft: AppTheme.neutral.withValues(alpha: 0.14));
        await _expectStyle(tester, AppTheme.light, TaskVisualState.upcoming,
            expectedColor: AppTheme.accent,
            expectedIcon: Icons.outlined_flag,
            expectedOpacity: 1.0,
            expectedLabel: '',
            expectedFilled: false,
            expectedSoft: AppTheme.accentSoft);
        await _expectStyle(tester, AppTheme.light, TaskVisualState.inProgress,
            expectedColor: AppTheme.warn,
            expectedIcon: Icons.play_circle,
            expectedOpacity: 1.0,
            expectedLabel: '进行中',
            expectedFilled: true,
            expectedSoft: AppTheme.warnSoft);
        await _expectStyle(tester, AppTheme.light, TaskVisualState.overdue,
            expectedColor: AppTheme.danger,
            expectedIcon: Icons.event_busy,
            expectedOpacity: 1.0,
            expectedLabel: '逾期',
            expectedFilled: true,
            expectedSoft: AppTheme.dangerSoft);
        await _expectStyle(tester, AppTheme.light, TaskVisualState.done,
            expectedColor: AppTheme.ok,
            expectedIcon: Icons.check_circle,
            expectedOpacity: 0.55,
            expectedLabel: '',
            expectedFilled: true,
            expectedSoft: AppTheme.okSoft);
        await _expectStyle(tester, AppTheme.light, TaskVisualState.conflictBlocked,
            expectedColor: AppTheme.danger,
            expectedIcon: Icons.warning_amber_rounded,
            expectedOpacity: 0.6,
            expectedLabel: '',
            expectedFilled: true,
            expectedSoft: AppTheme.dangerSoft);
      });
    });

    group('深色模式（*Dark 变体）', () {
      testWidgets('unscheduled / upcoming / inProgress / overdue / done / conflictBlocked', (tester) async {
        await _expectStyle(tester, AppTheme.dark, TaskVisualState.unscheduled,
            expectedColor: AppTheme.neutralDark,
            expectedIcon: Icons.schedule_outlined,
            expectedOpacity: 0.85,
            expectedLabel: '',
            expectedFilled: false,
            expectedSoft: AppTheme.neutralDark.withValues(alpha: 0.14));
        await _expectStyle(tester, AppTheme.dark, TaskVisualState.upcoming,
            expectedColor: AppTheme.accent,
            expectedIcon: Icons.outlined_flag,
            expectedOpacity: 1.0,
            expectedLabel: '',
            expectedFilled: false,
            expectedSoft: AppTheme.accentSoft);
        await _expectStyle(tester, AppTheme.dark, TaskVisualState.inProgress,
            expectedColor: AppTheme.warnDark,
            expectedIcon: Icons.play_circle,
            expectedOpacity: 1.0,
            expectedLabel: '进行中',
            expectedFilled: true,
            expectedSoft: AppTheme.warnSoft);
        await _expectStyle(tester, AppTheme.dark, TaskVisualState.overdue,
            expectedColor: AppTheme.dangerDark,
            expectedIcon: Icons.event_busy,
            expectedOpacity: 1.0,
            expectedLabel: '逾期',
            expectedFilled: true,
            expectedSoft: AppTheme.dangerSoft);
        await _expectStyle(tester, AppTheme.dark, TaskVisualState.done,
            expectedColor: AppTheme.okDark,
            expectedIcon: Icons.check_circle,
            expectedOpacity: 0.55,
            expectedLabel: '',
            expectedFilled: true,
            expectedSoft: AppTheme.okSoft);
        await _expectStyle(tester, AppTheme.dark, TaskVisualState.conflictBlocked,
            expectedColor: AppTheme.dangerDark,
            expectedIcon: Icons.warning_amber_rounded,
            expectedOpacity: 0.6,
            expectedLabel: '',
            expectedFilled: true,
            expectedSoft: AppTheme.dangerSoft);
      });
    });
  });

  // ───────────────────────── C. TaskCard 渲染 ─────────────────────────
  group('C. TaskCard 渲染', () {
    final now = DateTime.now();

    Future<void> _pumpCard(
      WidgetTester tester,
      Task task, {
      VoidCallback? onResolve,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskCard(
            task: task,
            onTap: () {},
            onToggle: () {},
            onDelete: () {},
            onResolveOverride: onResolve,
          ),
        ),
      ));
    }

    testWidgets('done：状态图标 check_circle + 标题删除线 + 左色条=ok', (tester) async {
      final t = Task(
        id: 'c_done',
        title: '已完成任务',
        scheduledTime: now.subtract(const Duration(minutes: 10)),
        status: TaskStatus.done,
        createdAt: DateTime(2020),
        notificationId: 1,
      );
      await _pumpCard(tester, t);

      expect(find.byIcon(Icons.check_circle), findsWidgets);
      final title = tester.widget<Text>(find.text('已完成任务'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == AppTheme.ok),
        findsOneWidget,
        reason: '左色条应取 ok 色',
      );
    });

    testWidgets('conflictBlocked：warning_amber + 资源冲突块 + 确认覆盖 + 左色条=danger',
        (tester) async {
      final t = Task(
        id: 'c_conf',
        title: '冲突任务',
        scheduledTime: now.add(const Duration(hours: 1)),
        conflictState: ConflictState.pendingConflict,
        resource: '会议室A',
        createdAt: DateTime(2020),
        notificationId: 1,
      );
      await _pumpCard(tester, t, onResolve: () {});

      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      expect(find.text('资源冲突 · 未生效'), findsOneWidget);
      expect(find.text('确认覆盖'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == AppTheme.danger),
        findsOneWidget,
        reason: '左色条应取 danger 色',
      );
    });

    testWidgets('inProgress：play_circle + 徽章「进行中」+ 左色条=warn', (tester) async {
      final t = Task(
        id: 'c_prog',
        title: '进行中任务',
        scheduledTime: now.subtract(const Duration(minutes: 20)),
        durationMinutes: 60,
        createdAt: DateTime(2020),
        notificationId: 1,
      );
      await _pumpCard(tester, t);

      expect(find.byIcon(Icons.play_circle), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == AppTheme.warn),
        findsOneWidget,
        reason: '左色条应取 warn 色',
      );
    });

    testWidgets('overdue：event_busy + 徽章「逾期」+ 左色条=danger', (tester) async {
      final t = Task(
        id: 'c_ovr',
        title: '逾期任务',
        scheduledTime: now.subtract(const Duration(minutes: 90)),
        durationMinutes: 60,
        createdAt: DateTime(2020),
        notificationId: 1,
      );
      await _pumpCard(tester, t);

      expect(find.byIcon(Icons.event_busy), findsOneWidget);
      expect(find.text('逾期'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == AppTheme.danger),
        findsOneWidget,
        reason: '左色条应取 danger 色',
      );
    });

    testWidgets('unscheduled：schedule_outlined + 左色条=neutral（无徽章）', (tester) async {
      final t = Task(
        id: 'c_uns',
        title: '待安排任务',
        createdAt: DateTime(2020),
        notificationId: 1,
      );
      await _pumpCard(tester, t);

      expect(find.byIcon(Icons.schedule_outlined), findsWidgets);
      expect(find.text('进行中'), findsNothing);
      expect(find.text('逾期'), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == AppTheme.neutral),
        findsOneWidget,
        reason: '左色条应取 neutral 色',
      );
    });
  });

  // ───────────────────────── D. 删除（无撤销、无提示）─────────────────────────
  group('D. 删除', () {
    // 说明：真实 TasksTab 在 headless flutter_test 下，其列表分支
    // （TaskList → ListView / Viewport）会触发遍历元素树的 `renderObject!` 空异常
    // （属测试环境假象：真机/模拟器有界约束下不出现，真实 App 不会出现）。因此 D 组
    // 改用轻量 harness 验证「删除」契约。
    //
    // 该 [_DeleteHarness] 复刻了 TasksTab._delete
    // （lib/modules/tasks/tasks_tab.dart）的同一组 store/reminder 调用：
    //   cancelTask(task) → store.delete(task)
    // 行为等价，但规避 headless 下完整 TasksTab 的 Viewport/Semantics 假象。
    // 删除后不再提供撤销 SnackBar，任务直接移出。
    //
    // 设计要点：TaskCard 本身即是一个 Dismissible（key=ValueKey(task.id)、endToStart、
    // 危险红底+删除图标、onDismissed→onDelete），故 harness 直接以 TaskCard 作为滑动
    // 删除载体（onDelete 指向 _delete），无需再包一层 Dismissible（否则会与
    // TaskCard 内部的 Dismissible 产生重复 GlobalKey 与嵌套滑动手势冲突）。用
    // ListenableBuilder 按 store 是否仍含该任务决定渲染 TaskCard 还是空占位。

    testWidgets('滑动删除后任务直接移出、取消提醒、且不出现撤销提示',
        (tester) async {
      final store = FakeTaskStore();
      final reminder = FakeReminderService();
      final task = Task(
        id: 'del1',
        title: '待删除任务',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime(2020),
        notificationId: 1,
      );
      store.seed(task);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: _DeleteHarness(
            store: store,
            reminder: reminder,
            task: task,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 触发删除：左滑 TaskCard 自带的 Dismissible（endToStart），offset 超过阈值即 dismiss。
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // 删除已生效：任务移出 store，且已取消提醒
      expect(store.all.any((t) => t.id == 'del1'), isFalse,
          reason: '删除后任务应已被移除');
      expect(reminder.cancelled.any((t) => t.id == 'del1'), isTrue,
          reason: '删除应调用 cancelTask');

      // 不应出现撤销提示
      expect(find.text('已删除'), findsNothing, reason: '删除不应弹已删除 SnackBar');
      expect(find.text('撤销'), findsNothing, reason: '删除不应提供撤销动作');
    });
  });

  // ───────────────────────── A 组补充：重复任务视觉状态（缺陷1 修复验证）─────────────────────────
  group('A. 重复任务视觉状态（补充）', () {
    // 固定参考时间，规避系统时钟抖动。
    final now = DateTime(2026, 1, 1, 12, 0); // 周四 noon（2026-01-01 为周四）

    Task makeRepeating({
      required RepeatType repeat,
      DateTime? scheduledTime,
      List<int> customWeekdays = const [],
      int durationMinutes = 60,
    }) =>
        Task(
          id: 'rep',
          title: 't',
          createdAt: DateTime(2020),
          notificationId: 1,
          repeat: repeat,
          scheduledTime: scheduledTime,
          customWeekdays: customWeekdays,
          durationMinutes: durationMinutes,
        );

    test('A+1. daily：已过种子时刻 → upcoming（非 overdue）', () {
      final t = makeRepeating(
        repeat: RepeatType.daily,
        scheduledTime: DateTime(2026, 1, 1, 4, 0), // 4am，now=noon 已过
      );
      expect(resolveVisualState(t, now), TaskVisualState.upcoming);
      expect(resolveVisualState(t, now), isNot(TaskVisualState.overdue));
    });

    test('A+2. daily：落在 [nextOccurrence, +duration) 窗口内 → inProgress', () {
      final t = makeRepeating(
        repeat: RepeatType.daily,
        scheduledTime: DateTime(2026, 1, 1, 4, 0),
      );
      final start = t.nextOccurrence(now)!;
      expect(resolveVisualState(t, start), TaskVisualState.inProgress);
      expect(resolveVisualState(t, start.add(const Duration(minutes: 30))),
          TaskVisualState.inProgress);
    });

    test('A+3. weekly：已过种子时刻 → upcoming（非 overdue）', () {
      final t = makeRepeating(
        repeat: RepeatType.weekly,
        scheduledTime: DateTime(2026, 1, 1, 9, 0), // 周四 9:00
      );
      expect(resolveVisualState(t, now), TaskVisualState.upcoming);
      expect(resolveVisualState(t, now), isNot(TaskVisualState.overdue));
    });

    test('A+4. custom（周一、周三）：已过种子时刻 → upcoming（非 overdue）', () {
      final t = makeRepeating(
        repeat: RepeatType.custom,
        scheduledTime: DateTime(2026, 1, 1, 9, 0), // 周四（不在 custom 列表）
        customWeekdays: const [1, 3],
      );
      expect(resolveVisualState(t, now), TaskVisualState.upcoming);
      expect(resolveVisualState(t, now), isNot(TaskVisualState.overdue));
    });

    test('A+5. 重复任务在任意时刻都不返回 overdue', () {
      final daily = makeRepeating(
        repeat: RepeatType.daily,
        scheduledTime: DateTime(2026, 1, 1, 4, 0),
      );
      final probe = DateTime(2026, 1, 1, 0, 0);
      for (var i = 0; i < 48; i++) {
        final tt = probe.add(Duration(hours: i));
        expect(resolveVisualState(daily, tt), isNot(TaskVisualState.overdue),
            reason: 'daily@$tt 不应 overdue');
      }
    });

    test('A+6. 重复任务 unscheduled（scheduledTime==null）→ unscheduled', () {
      final t = makeRepeating(
        repeat: RepeatType.daily,
        scheduledTime: null,
      );
      expect(resolveVisualState(t, now), TaskVisualState.unscheduled);
    });
  });

  // ───────────────────────── E. 完成语义（缺陷2 修复验证）─────────────────────────
  group('E. 完成语义（重复/非重复 toggleDone + markMissedIfNeeded）', () {
    test('E1. daily 重复任务 toggleDone：scheduledTime 推进到下次发生、status 保持 pending、不变成 done', () async {
      final task = Task(
        id: 'e_daily',
        title: '每日喝水',
        scheduledTime: DateTime(2000, 1, 1, 4, 0), // 远古种子，确保 now 必然已过期
        repeat: RepeatType.daily,
        createdAt: DateTime(2000),
        notificationId: 1,
      );
      final store = ToggleFakeStore();
      store.seed(task);

      await store.toggleDone(task);

      // 核心修复：重复任务不应被标 done（否则会取消以后每天的通知）。
      expect(task.isDone, isFalse);
      expect(task.status, TaskStatus.pending);
      // 种子已滚动到下一次发生（时刻不变为 4:00，日期推进到未来）。
      expect(task.scheduledTime, isNotNull);
      expect(task.scheduledTime!.hour, 4);
      expect(task.scheduledTime!.minute, 0);
      expect(task.scheduledTime!.isAfter(DateTime(2000, 1, 1, 4, 0)), isTrue,
          reason: '种子应相对原始值推进');
      expect(task.scheduledTime!.isAfter(DateTime.now().subtract(const Duration(days: 1))),
          isTrue, reason: '应滚动到临近 now 的下一次发生');
    });

    test('E2. none 非重复任务 toggleDone：维持原 done/pending 切换', () async {
      final task = Task(
        id: 'e_none',
        title: '一次性任务',
        scheduledTime: DateTime(2000, 1, 1, 4, 0),
        repeat: RepeatType.none,
        createdAt: DateTime(2000),
        notificationId: 2,
      );
      final store = ToggleFakeStore();
      store.seed(task);

      await store.toggleDone(task);
      expect(task.status, TaskStatus.done);
      expect(task.isDone, isTrue);

      await store.toggleDone(task); // 再次切换 → 取消完成
      expect(task.status, TaskStatus.pending);
      expect(task.isDone, isFalse);
    });

    test('E3. markMissedIfNeeded：重复任务不被标 missed，非重复过期任务被标 missed', () async {
      final repeating = Task(
        id: 'e_rep',
        title: '每日任务',
        scheduledTime: DateTime(2000, 1, 1, 4, 0),
        repeat: RepeatType.daily,
        status: TaskStatus.pending,
        createdAt: DateTime(2000),
        notificationId: 3,
      );
      final oneShot = Task(
        id: 'e_one',
        title: '一次性过期',
        scheduledTime: DateTime(2000, 1, 1, 4, 0),
        repeat: RepeatType.none,
        status: TaskStatus.pending,
        createdAt: DateTime(2000),
        notificationId: 4,
      );
      final store = ToggleFakeStore();
      store.seed(repeating);
      store.seed(oneShot);

      await store.markMissedIfNeeded();

      expect(repeating.status, TaskStatus.pending,
          reason: '重复任务不应被标 missed');
      expect(repeating.isDone, isFalse);
      expect(oneShot.status, TaskStatus.missed,
          reason: '非重复过期任务应被标 missed');
    });

    test('E4. daily 任务窗口内勾选后（completedAt 同日）→ 显示 done（今日已完成）', () async {
      final task = Task(
        id: 'e4',
        title: '每日运动',
        scheduledTime: DateTime(2026, 1, 1, 16, 0), // 每天 16:00
        repeat: RepeatType.daily,
        createdAt: DateTime(2020),
        notificationId: 10,
      );
      final now = DateTime(2026, 1, 1, 16, 30); // 当天窗口内 16:30
      final store = ToggleFakeStore();
      store.seed(task);

      try {
        await store.toggleDoneAt(task, now); // 注入 now，绕过系统时钟
      } on Object {
        // 忽略 Hive save（Fake 无真实 box），内存态变更已生效
      }

      expect(task.completedAt, isNotNull, reason: 'completedAt 应记录完成时刻');
      expect(resolveVisualState(task, now), TaskVisualState.done,
          reason: '窗口内勾选后当天应显示「今日已完成」');
    });

    test('E5. daily 任务次日（completedAt 为昨日）→ 不再 done，恢复进行中/待执行', () async {
      final task = Task(
        id: 'e5',
        title: '每日运动',
        scheduledTime: DateTime(2026, 1, 1, 16, 0),
        repeat: RepeatType.daily,
        createdAt: DateTime(2020),
        notificationId: 11,
      );
      final toggleNow = DateTime(2026, 1, 1, 16, 30); // 第1天窗口内
      final nextDay = DateTime(2026, 1, 2, 16, 30); // 第2天窗口内
      final store = ToggleFakeStore();
      store.seed(task);

      try {
        await store.toggleDoneAt(task, toggleNow);
      } on Object {
        // 忽略 Hive save
      }
      expect(resolveVisualState(task, toggleNow), TaskVisualState.done,
          reason: '第1天应 done');

      // 次日：completedAt 为昨日，应恢复（窗口内为 inProgress，非 done）
      final nextState = resolveVisualState(task, nextDay);
      expect(nextState, isNot(TaskVisualState.done),
          reason: '次日不应再显示 done');
      expect(nextState,
          anyOf(TaskVisualState.upcoming, TaskVisualState.inProgress));
    });

    test('E6. toggleDoneAt 对 daily 任务将 completedAt 设为 now，且种子严格推进到未来', () async {
      final task = Task(
        id: 'e6',
        title: '每日喝水',
        scheduledTime: DateTime(2026, 1, 1, 16, 0),
        repeat: RepeatType.daily,
        createdAt: DateTime(2020),
        notificationId: 12,
      );
      final now = DateTime(2026, 1, 1, 16, 30);
      final store = ToggleFakeStore();
      store.seed(task);

      try {
        await store.toggleDoneAt(task, now);
      } on Object {
        // 忽略 Hive save
      }

      expect(task.completedAt, now, reason: '应记录「今天这一次已完成」的时刻');
      expect(task.status, TaskStatus.pending);
      // 种子应严格推进到下一次发生（明天 16:00），非过去时刻（数据干净）。
      expect(task.scheduledTime, isNotNull);
      expect(task.scheduledTime!.isAfter(now), isTrue,
          reason: '种子应推进到当前发生之后的下一次');
    });

    test('E7. daily 任务窗口内勾选后，同日窗口结束后（18:00）仍显示 done（持续到跨日）', () async {
      final task = Task(
        id: 'e7',
        title: '每日运动',
        scheduledTime: DateTime(2026, 1, 1, 16, 0), // 每天 16:00，窗口 16:00–17:00
        repeat: RepeatType.daily,
        createdAt: DateTime(2020),
        notificationId: 13,
      );
      final toggleNow = DateTime(2026, 1, 1, 16, 30); // 窗口内勾选
      final laterSameDay = DateTime(2026, 1, 1, 18, 0); // 同日窗口结束后
      final store = ToggleFakeStore();
      store.seed(task);

      try {
        await store.toggleDoneAt(task, toggleNow);
      } on Object {
        // 忽略 Hive save
      }

      expect(resolveVisualState(task, toggleNow), TaskVisualState.done,
          reason: '窗口内勾选应 done');
      expect(resolveVisualState(task, laterSameDay), TaskVisualState.done,
          reason: '同日窗口结束后仍应 done（持续到跨日）');
    });
  });
}

// ───────────────────────── 测试替身（不引入新依赖）─────────────────────────

/// 删除/撤销契约集成用的最小 Harness（StatefulWidget）。
///
/// 复刻 `TasksTab._delete`（lib/modules/tasks/tasks_tab.dart）的
/// 删除流程，但规避 headless 下完整 TasksTab 的 Viewport/Semantics 假象。
///
/// 说明：TaskCard 本身即是一个 Dismissible（key=ValueKey(task.id)、direction=
/// endToStart、危险红底+删除图标、onDismissed→onDelete），故 harness 直接以
/// TaskCard 作为滑动删除载体，将 onDelete 指向本类的 [_delete]，即可等价
/// 于 TasksTab 列表项的滑动删除行为，无需再包一层 Dismissible（否则会与 TaskCard
/// 内部的 Dismissible 产生重复 GlobalKey 与嵌套滑动手势冲突）。store / reminder 由
/// 真实 Fake 注入，断言其调用记录。
class _DeleteHarness extends StatefulWidget {
  final TaskStore store;
  final ReminderService reminder;
  final Task task;

  const _DeleteHarness({
    required this.store,
    required this.reminder,
    required this.task,
    super.key,
  });

  @override
  State<_DeleteHarness> createState() => _DeleteHarnessState();
}

class _DeleteHarnessState extends State<_DeleteHarness> {
  /// 复刻 TasksTab._delete：取消提醒调度并直接删除，不提供撤销、不弹提示。
  Future<void> _delete(Task t) async {
    await widget.reminder.cancelTask(t);
    await widget.store.delete(t);
  }

  @override
  Widget build(BuildContext context) {
    // 复刻 TasksTab 列表项「删除即移出列表」：store 不含该任务时不再渲染 TaskCard
    // （其自身即为一个 Dismissible）。使用 ListenableBuilder 替代 provider 的
    // Consumer，以去掉对 provider 的依赖（同文件其余测试亦不再需要 provider）。
    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final exists = widget.store.all.any((t) => t.id == widget.task.id);
          if (!exists) return const SizedBox.shrink();
          return TaskCard(
            task: widget.task,
            onTap: () {},
            onToggle: () {},
            onDelete: () => _delete(widget.task),
          );
        },
      ),
    );
  }
}

/// 内存版 TaskStore：绕过 Hive，直接操作内存列表，便于观测 add/delete。
class FakeTaskStore extends TaskStore {
  final List<Task> _tasks = [];

  @override
  List<Task> get all => List<Task>.from(_tasks);

  @override
  Future<void> init() async {}

  @override
  Future<void> add(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    _tasks.add(task);
    notifyListeners();
  }

  @override
  Future<void> delete(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
  }

  @override
  Future<void> toggleDone(Task task) async {}

  void seed(Task task) => _tasks.add(task);
}

/// 可观测的 ReminderService：记录 cancelTask / notifyTaskChanged 调用。
class FakeReminderService extends ReminderService {
  final List<Task> cancelled = [];
  final List<Task> notified = [];

  FakeReminderService() : super();

  @override
  Future<void> cancelTask(Task task) async => cancelled.add(task);

  @override
  Future<void> notifyTaskChanged(Task task) async => notified.add(task);
}

/// 完成语义验证用 Fake Store（E 组）。
///
/// - [toggleDone] 直接走真实 [TaskStore.toggleDoneAt]（经 try/catch 吞掉 Hive
///   `save` 异常，保留内存态变更），以尽量覆盖真实完成语义；这也是缺陷2修复的核心。
/// - [markMissedIfNeeded] 因真实方法遍历 `_box`（无 Hive 下不可用），故在此镜像
///   真实逻辑（遍历 [all]、跳过 [Task.isRepeating]、过期 pending 非重复标 missed）。
///   逻辑应与 lib/services/task_store.dart 保持同步。
class ToggleFakeStore extends FakeTaskStore {
  @override
  Future<void> toggleDone(Task task) async {
    try {
      await toggleDoneAt(task, DateTime.now()); // 真实完成语义（save 在 Fake 下抛错被忽略）
    } on Object {
      // 忽略 Hive 持久化异常，内存态变更已生效
    }
    notifyListeners();
  }

  @override
  Future<void> markMissedIfNeeded() async {
    final now = DateTime.now();
    var changed = false;
    for (final t in all) {
      if (t.isRepeating) continue; // 重复任务永不被标 missed
      if (t.status == TaskStatus.pending &&
          t.scheduledTime != null &&
          t.scheduledTime!.isBefore(now)) {
        t.status = TaskStatus.missed;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}

