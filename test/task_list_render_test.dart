import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/modules/tasks/task_list.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TaskList 在 ListView 上下文真实渲染测试（覆盖"任务列表空白"回归盲区）。
///
/// 根因：此前 [TaskCard] 用 `Row(crossAxisAlignment: stretch)` + `Expanded`，被 [TaskList]
/// 的 `all` 分支 `ListView(children:)` 渲染时，子项获得无限竖向约束，`RenderFlex` 无法
/// 解析高度而抛 "BoxConstraints forces an infinite height"，导致整块卡片不渲染（统计走
/// store 不受影响故正常）。修复后外层加 `IntrinsicHeight`。
///
/// 本测试**直接 pump [TaskList]**（`all` 分支 → 真实 ListView 路径），首次覆盖该渲染盲区，
/// 验证：pumpAndSettle 不再抛布局异常、各状态卡片真正渲染可见。
///
/// 注：[TaskList] 的时间桶判定为互斥区间（`上午 hour<12` / `下午 hour>=12 && hour<18` /
/// `晚上 hour>=18` / `待安排 scheduledTime==null`），四桶互不重叠，12 点前的任务只落在「上午」一桶。
/// 互斥用例（见下方「时间桶互斥」）断言 4 任务恰好渲染 4 张卡片、各桶头唯一；其余用例标题断言仍用
/// [findsWidgets]（至少渲染一次即证明卡片可见，非空白）。
///
/// 为让全部时间桶（含靠下的「晚上」「待安排」）在同一视口内构建，测试将视口拉高至 2400，
/// 避免 [ListView] 懒渲染把下方桶延迟到滚动后才构建。
void main() {
  setUp(() {
    // 拉高测试视口，确保 ListView 内全部桶同时构建（非滚动延迟）
    final binding = TestWidgetsFlutterBinding.instance;
    binding.window.physicalSizeTestValue = const Size(400, 2400);
    binding.window.devicePixelRatioTestValue = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.window.clearPhysicalSizeTestValue();
    binding.window.clearDevicePixelRatioTestValue();
  });

  group('TaskList 在 ListView 上下文渲染', () {
    /// 构造覆盖多种视觉状态的 mock 任务：
    /// 上午(pending) / 下午(done) / 晚上(repeat) / 待安排(unscheduled) / 上午(conflict)。
    List<Task> mockTasks() {
      final base = DateTime(2025, 6, 15, 9, 0);
      return [
        Task(
          id: 't1',
          title: '晨会同步',
          scheduledTime: DateTime(2025, 6, 15, 9, 0),
          createdAt: base,
          notificationId: 1,
        ),
        Task(
          id: 't2',
          title: '提交周报',
          scheduledTime: DateTime(2025, 6, 15, 14, 30),
          status: TaskStatus.done,
          createdAt: base,
          notificationId: 2,
        ),
        Task(
          id: 't3',
          title: '健身打卡',
          scheduledTime: DateTime(2025, 6, 15, 20, 0),
          repeat: RepeatType.daily,
          createdAt: base,
          notificationId: 3,
        ),
        Task(
          id: 't4',
          title: '灵感记录',
          scheduledTime: null,
          createdAt: base,
          notificationId: 4,
        ),
        Task(
          id: 't5',
          title: '客户拜访',
          scheduledTime: DateTime(2025, 6, 15, 10, 30),
          resource: '会议室A',
          conflictState: ConflictState.pendingConflict,
          effective: false,
          createdAt: base,
          notificationId: 5,
        ),
      ];
    }

    testWidgets('all 分支 ListView 渲染不抛 infinite height，且各状态卡片可见', (
      tester,
    ) async {
      final tasks = mockTasks();

      // 直接 pump TaskList（all 分支 → 真实 ListView(children:) 无限高路径）
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TaskList(
              filter: TaskFilter.all,
              tasks: tasks,
              onAdd: () {},
              onVoice: () {},
              onTap: (_) {},
              onToggle: (_) {},
              onDelete: (_) {},
              onResolve: (_) {},
            ),
          ),
        ),
      );

      // pumpAndSettle 若遇 "BoxConstraints forces an infinite height" 会直接抛错，
      // 在此 await 即会抛出并令测试失败；否则继续校验无遗留异常。
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 各状态卡片标题均真实渲染可见（时间桶累计区间可能命中多次，故用 findsWidgets）
      expect(find.text('晨会同步'), findsWidgets);
      expect(find.text('提交周报'), findsWidgets);
      expect(find.text('健身打卡'), findsWidgets);
      expect(find.text('灵感记录'), findsWidgets);
      expect(find.text('客户拜访'), findsWidgets);

      // 四个时间桶分组头各渲染（注：「待安排」同时是未排定任务的时刻 meta 文案，
      // 故该文案可能命中多次，统一用 findsWidgets；其余桶名仅作表头，命中一次）
      expect(find.text('上午'), findsOneWidget);
      expect(find.text('下午'), findsOneWidget);
      expect(find.text('晚上'), findsOneWidget);
      expect(find.text('待安排'), findsWidgets);

      // 冲突块（资源冲突·未生效）渲染
      expect(find.text('资源冲突 · 未生效'), findsWidgets);

      // 至少一张 TaskCard 与 ListView 已挂载
      expect(find.byType(TaskCard), findsWidgets);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('active 分支（ListView.separated）同样正常渲染无布局异常', (tester) async {
      final tasks = mockTasks();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TaskList(
              filter: TaskFilter.active,
              tasks: tasks,
              onAdd: () {},
              onVoice: () {},
              onTap: (_) {},
              onToggle: (_) {},
              onDelete: (_) {},
              onResolve: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // active 分支按传入列表原样渲染（不过滤状态），全部可见
      expect(find.text('晨会同步'), findsWidgets);
      expect(find.text('提交周报'), findsWidgets);
      expect(find.text('健身打卡'), findsWidgets);
      expect(find.text('灵感记录'), findsWidgets);
      expect(find.text('客户拜访'), findsWidgets);
      expect(find.byType(TaskCard), findsWidgets);
    });

    testWidgets('overdue 分支（ListView.separated）渲染 2 张逾期卡片', (
      tester,
    ) async {
      final tasks = <Task>[
        Task(
          id: 'o1',
          title: '逾期任务一',
          scheduledTime: DateTime(2020, 1, 1, 9, 0),
          status: TaskStatus.missed,
          createdAt: DateTime(2020, 1, 1),
          notificationId: 101,
        ),
        Task(
          id: 'o2',
          title: '逾期任务二',
          scheduledTime: DateTime(2020, 1, 1, 14, 0),
          status: TaskStatus.pending,
          createdAt: DateTime(2020, 1, 1),
          notificationId: 102,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TaskList(
              filter: TaskFilter.overdue,
              tasks: tasks,
              onAdd: () {},
              onVoice: () {},
              onTap: (_) {},
              onToggle: (_) {},
              onDelete: (_) {},
              onResolve: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 逾期分支按传入列表原样平铺，渲染 2 张逾期卡片
      expect(find.byType(TaskCard), findsNWidgets(2));
      expect(find.text('逾期任务一'), findsOneWidget);
      expect(find.text('逾期任务二'), findsOneWidget);
    });

    testWidgets('时间桶互斥：上午/下午/晚上/待安排 各桶不重叠', (tester) async {
      final base = DateTime(2020, 1, 1);
      final tasks = <Task>[
        Task(
          id: 'b1',
          title: '上午任务',
          scheduledTime: DateTime(2020, 1, 1, 9, 0),
          status: TaskStatus.pending,
          createdAt: base,
          notificationId: 1,
        ),
        Task(
          id: 'b2',
          title: '下午任务',
          scheduledTime: DateTime(2020, 1, 1, 13, 0),
          status: TaskStatus.pending,
          createdAt: base,
          notificationId: 2,
        ),
        Task(
          id: 'b3',
          title: '晚上任务',
          scheduledTime: DateTime(2020, 1, 1, 20, 0),
          status: TaskStatus.pending,
          createdAt: base,
          notificationId: 3,
        ),
        Task(
          id: 'b4',
          title: '待安排任务',
          scheduledTime: null,
          status: TaskStatus.pending,
          createdAt: base,
          notificationId: 4,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TaskList(
              filter: TaskFilter.all,
              tasks: tasks,
              onAdd: () {},
              onVoice: () {},
              onTap: (_) {},
              onToggle: (_) {},
              onDelete: (_) {},
              onResolve: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 每个桶恰好一张卡片（无重叠导致 5 张）；桶头各出现一次。
      expect(find.byType(TaskCard), findsNWidgets(4));
      expect(find.text('上午'), findsOneWidget);
      expect(find.text('下午'), findsOneWidget);
      expect(find.text('晚上'), findsOneWidget);
      expect(find.text('待安排'), findsWidgets);
    });
  });
}
