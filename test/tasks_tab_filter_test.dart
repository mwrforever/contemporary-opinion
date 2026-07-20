import 'package:flutter_test/flutter_test.dart';

import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/theme/task_status_style.dart';

/// 「待办（active）」筛选语义单元测试：逾期的一次性任务移出待办（列表与计数），
/// 仅在「全部」视图按时间桶以红色显示；非逾期任务在待办中的表现不变。
///
/// 直接调用顶层纯函数 [isActionableTask]（由 `TasksTab` 待办筛选/计数复用），
/// **不 pump 任何 Widget、不构造 TasksTab、不依赖 Hive**——headless `flutter_test`
/// 下完整 `TasksTab` 的 `Scaffold→Expanded→TaskList→ListView` 会触发
/// `RenderViewport.performLayout` / `SliverMultiBoxAdaptor` 假象崩溃（真机不出现，
/// 项目记忆已记录「勿 pump 完整 TasksTab」）。本文件覆盖 [isActionableTask] 的
/// 确定性场景；[resolveVisualState] 的窗口语义（inProgress/upcoming）已由
/// `task_visual_state_test.dart` 覆盖，此处不重复。
///
/// 时间选取约定：用过去 / 远期固定时间，规避依赖 `DateTime.now()` 落在某窗口的
/// flaky。[isActionableTask] 内部以 `DateTime.now()` 为判定锚，但下述场景对 now
/// 落在任意时刻均给出确定性结果：过去时刻恒过期、远期时刻恒未来、done/冲突/
/// 待安排/重复与 now 无关。
void main() {
  final base = DateTime(2020); // 统一 createdAt，避免无意义字段干扰

  group('isActionableTask - 待办排除逾期一次性任务', () {
    // 1) 逾期(missed)的一次性任务（过去时刻 + status=missed）→ isFalse
    test('逾期(missed)一次性任务 → 不在待办', () {
      final t = Task(
        id: 't-overdue-missed',
        title: '逾期会议(missed)',
        scheduledTime: DateTime(2025, 6, 15, 17, 47), // 过去时刻
        status: TaskStatus.missed,
        createdAt: base,
        notificationId: 1,
      );
      expect(isActionableTask(t), isFalse,
          reason: 'missed 一次性任务应被移出待办');
    });

    // 2) 逾期(pending 已过期)的一次性任务（过去时刻 + status=pending）→ isFalse
    test('逾期(pending 已过期)一次性任务 → 不在待办', () {
      final t = Task(
        id: 't-overdue-pending',
        title: '逾期会议(pending过期)',
        scheduledTime: DateTime(2025, 6, 15, 9, 0), // 过去时刻
        status: TaskStatus.pending,
        createdAt: base,
        notificationId: 2,
      );
      expect(isActionableTask(t), isFalse,
          reason: 'pending 已过期的一次性任务也应被移出待办');
    });

    // 3) 未来 pending 任务（如 2027 年）→ isTrue
    test('未来 pending 任务 → 仍在待办', () {
      final t = Task(
        id: 't-future',
        title: '未来任务',
        scheduledTime: DateTime(2027, 1, 1, 10, 0), // 远期
        createdAt: base,
        notificationId: 3,
      );
      expect(isActionableTask(t), isTrue,
          reason: '未来 pending 任务应保留在待办');
    });

    // 4) 已完成任务（done）→ isFalse
    test('已完成任务(done) → 不在待办', () {
      final t = Task(
        id: 't-done',
        title: '已完成任务',
        scheduledTime: DateTime(2025, 6, 15, 8, 0),
        status: TaskStatus.done,
        completedAt: DateTime(2025, 6, 15, 8, 30),
        createdAt: base,
        notificationId: 4,
      );
      expect(isActionableTask(t), isFalse,
          reason: '已完成任务本就不在待办');
    });

    // 5) 重复任务（过去种子时刻, RepeatType.daily）→ isTrue
    test('重复任务(daily, 过去种子) → 仍在待办', () {
      final t = Task(
        id: 't-repeat',
        title: '每日健身',
        scheduledTime: DateTime(2025, 6, 15, 8, 0), // 过去种子
        repeat: RepeatType.daily,
        createdAt: base,
        notificationId: 5,
      );
      expect(isActionableTask(t), isTrue,
          reason: '重复任务永不判逾期，应保留在待办');
    });

    // 6) 冲突待处理任务（未来, ConflictState.pendingConflict）→ isTrue
    test('冲突待处理任务(conflictBlocked≠overdue) → 仍在待办', () {
      final t = Task(
        id: 't-conflict',
        title: '资源冲突任务',
        scheduledTime: DateTime(2027, 1, 1, 14, 0), // 未来
        resource: '会议室A',
        conflictState: ConflictState.pendingConflict,
        effective: false,
        createdAt: base,
        notificationId: 6,
      );
      expect(isActionableTask(t), isTrue,
          reason: '冲突待处理（conflictBlocked）非逾期，应保留在待办');
    });

    // 7) 待安排任务（scheduledTime==null）→ isTrue
    test('待安排任务(scheduledTime==null) → 仍在待办', () {
      final t = Task(
        id: 't-unscheduled',
        title: '待安排任务',
        createdAt: base,
        notificationId: 7,
      );
      expect(isActionableTask(t), isTrue,
          reason: '待安排任务（unscheduled）非逾期，应保留在待办');
    });
  });

  group('isActionableTask - 组合：待办过滤等价于列表筛选', () {
    // 以「全部 7 例按同一判据过滤」验证待办集合恒为
    // 全部 - 2 逾期 - 1 已完成 = 4 个可行动任务，与 TasksTab 待办计数/列表一致。
    test('混合 7 例：待办集合恒排除 2 逾期 + 1 已完成，保留 4 个可行动', () {
      final tasks = <Task>[
        Task(
          id: 't-overdue-missed',
          title: '逾期会议(missed)',
          scheduledTime: DateTime(2025, 6, 15, 17, 47),
          status: TaskStatus.missed,
          createdAt: base,
          notificationId: 1,
        ),
        Task(
          id: 't-overdue-pending',
          title: '逾期会议(pending过期)',
          scheduledTime: DateTime(2025, 6, 15, 9, 0),
          status: TaskStatus.pending,
          createdAt: base,
          notificationId: 2,
        ),
        Task(
          id: 't-future',
          title: '未来任务',
          scheduledTime: DateTime(2027, 1, 1, 10, 0),
          createdAt: base,
          notificationId: 3,
        ),
        Task(
          id: 't-done',
          title: '已完成任务',
          scheduledTime: DateTime(2025, 6, 15, 8, 0),
          status: TaskStatus.done,
          completedAt: DateTime(2025, 6, 15, 8, 30),
          createdAt: base,
          notificationId: 4,
        ),
        Task(
          id: 't-repeat',
          title: '每日健身',
          scheduledTime: DateTime(2025, 6, 15, 8, 0),
          repeat: RepeatType.daily,
          createdAt: base,
          notificationId: 5,
        ),
        Task(
          id: 't-conflict',
          title: '资源冲突任务',
          scheduledTime: DateTime(2027, 1, 1, 14, 0),
          resource: '会议室A',
          conflictState: ConflictState.pendingConflict,
          effective: false,
          createdAt: base,
          notificationId: 6,
        ),
        Task(
          id: 't-unscheduled',
          title: '待安排任务',
          createdAt: base,
          notificationId: 7,
        ),
      ];

      final actionable = tasks.where(isActionableTask).toList();
      expect(actionable, hasLength(4),
          reason: '待办应排除 2 逾期 + 1 已完成，保留 4 个可行动任务');
      final ids = actionable.map((t) => t.id).toSet();
      expect(ids, {
        't-future',
        't-repeat',
        't-conflict',
        't-unscheduled',
      }, reason: '待办应仅含未来/重复/冲突/待安排任务');

      // 逾期与已完成均不在待办
      expect(actionable.any((t) => t.id == 't-overdue-missed'), isFalse);
      expect(actionable.any((t) => t.id == 't-overdue-pending'), isFalse);
      expect(actionable.any((t) => t.id == 't-done'), isFalse);
    });
  });

  group('isOverdueTask - 逾期判据（归集到逾期 tab）', () {
    // 1) missed 状态 → true
    test('missed 状态 → 逾期', () {
      final t = Task(
        id: 'o-missed',
        title: '逾期会议(missed)',
        scheduledTime: DateTime(2020, 1, 1, 9, 0), // 过去时刻
        status: TaskStatus.missed,
        createdAt: base,
        notificationId: 11,
      );
      expect(isOverdueTask(t), isTrue, reason: 'missed 一次性任务应判逾期');
    });

    // 2) 一次性任务 scheduledTime 设在过去 → 窗口结束仍未完成 → true
    test('一次性任务过去时刻 → 逾期', () {
      final t = Task(
        id: 'o-past',
        title: '过去任务',
        scheduledTime: DateTime(2020, 1, 1, 9, 0), // 过去时刻
        durationMinutes: 30,
        createdAt: base,
        notificationId: 12,
      );
      expect(isOverdueTask(t), isTrue,
          reason: '过去的一次性任务窗口已结束，应判逾期');
    });

    // 3) 未来任务 → false
    test('未来任务 → 不逾期', () {
      final t = Task(
        id: 'o-future',
        title: '未来任务',
        scheduledTime: DateTime(2099, 1, 1, 10, 0), // 远期
        createdAt: base,
        notificationId: 13,
      );
      expect(isOverdueTask(t), isFalse, reason: '未来任务不应判逾期');
    });

    // 4) 已完成任务（done）→ false
    test('已完成任务(done) → 不逾期', () {
      final t = Task(
        id: 'o-done',
        title: '已完成任务',
        scheduledTime: DateTime(2020, 1, 1, 9, 0),
        status: TaskStatus.done,
        completedAt: DateTime(2020, 1, 1, 9, 30),
        createdAt: base,
        notificationId: 14,
      );
      expect(isOverdueTask(t), isFalse, reason: '已完成任务非逾期');
    });

    // 5) 重复任务（isRepeating=true，任意 scheduledTime）→ false
    test('重复任务 → 不逾期', () {
      final t = Task(
        id: 'o-repeat',
        title: '每日健身',
        scheduledTime: DateTime(2020, 1, 1, 8, 0), // 过去种子
        repeat: RepeatType.daily,
        createdAt: base,
        notificationId: 15,
      );
      expect(isOverdueTask(t), isFalse, reason: '重复任务永不判逾期');
    });

    // 6) 冲突待处理任务（hasPendingConflict）→ false
    test('冲突待处理任务 → 不逾期', () {
      final t = Task(
        id: 'o-conflict',
        title: '资源冲突任务',
        scheduledTime: DateTime(2020, 1, 1, 14, 0),
        resource: '会议室A',
        conflictState: ConflictState.pendingConflict,
        effective: false,
        createdAt: base,
        notificationId: 16,
      );
      expect(isOverdueTask(t), isFalse,
          reason: '冲突待处理（conflictBlocked）非逾期');
    });

    // 7) 待安排任务（scheduledTime==null）→ false
    test('待安排任务(scheduledTime==null) → 不逾期', () {
      final t = Task(
        id: 'o-unscheduled',
        title: '待安排任务',
        createdAt: base,
        notificationId: 17,
      );
      expect(isOverdueTask(t), isFalse, reason: '待安排任务（unscheduled）非逾期');
    });
  });
}
