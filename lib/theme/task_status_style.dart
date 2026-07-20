import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/app_theme.dart';

/// 判断两个时刻是否同一天（用于重复任务「今日已完成」视觉判定）。
bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 任务视觉状态枚举。
///
/// 覆盖 6 个视觉状态：待安排 / 待执行 / 进行中 / 已过期 / 已完成 / 冲突待处理。
/// 其中 inProgress / overdue 为纯派生状态（由 [resolveVisualState] 依据现有字段
/// + 当前时间计算），不持久化、不影响 [Task.effective] 与提醒调度。
enum TaskVisualState {
  unscheduled, // 待安排：scheduledTime == null
  upcoming, // 待执行：已排定，触发时间在未来
  inProgress, // 进行中：[start, start+duration) 窗口内（派生）
  overdue, // 已过期：窗口结束仍未完成，或 status == missed（派生）
  done, // 已完成：status == done
  conflictBlocked, // 冲突待处理：hasPendingConflict（未生效）
  timePending, // 时间待定：conflictState == undated（无具体时刻，未生效，待补时间）
}

/// 纯函数：由现有字段 + [now] 解析视觉状态。
///
/// 优先级自上而下：done > conflictBlocked > [重复任务短路] > missed(→overdue) >
/// unscheduled > 时间窗口判定(inProgress / overdue / upcoming)。与深浅模式无关，保持可测。
///
/// 重复任务（[Task.isRepeating]）提前短路：以 [Task.nextOccurrence] 为判定锚点，
/// 且**永不判 overdue/missed**——其自身会滚到第二天，语义是「每天提醒」而非「已过期」。
TaskVisualState resolveVisualState(Task t, DateTime now) {
  if (t.isDone) return TaskVisualState.done;
  if (t.hasPendingConflict) return TaskVisualState.conflictBlocked;
  if (t.conflictState == ConflictState.undated) {
    return TaskVisualState.timePending;
  }
  if (t.isRepeating) {
    final start = t.nextOccurrence(now);
    if (start == null) return TaskVisualState.unscheduled;
    // 今天这一次已完成（completedAt 为同一天）→ 显示「今日已完成」，复用 done 视觉；
    // 次日 completedAt 跨日自动回落为 upcoming/inProgress，永不卡死。
    if (t.completedAt != null && _isSameDay(t.completedAt!, now)) {
      return TaskVisualState.done;
    }
    // [start, start+duration) 内为进行中；其余（含窗口结束后）均为待执行，绝不逾期。
    if (!now.isBefore(start)) return TaskVisualState.inProgress;
    return TaskVisualState.upcoming;
  }
  if (t.status == TaskStatus.missed) return TaskVisualState.overdue;
  if (t.scheduledTime == null) return TaskVisualState.unscheduled;
  final start = t.scheduledTime!;
  final end = start.add(Duration(minutes: t.durationMinutes));
  if (!now.isBefore(end)) return TaskVisualState.overdue;
    if (!now.isBefore(start)) return TaskVisualState.inProgress;
    return TaskVisualState.upcoming;
  }

  /// 是否仍属「待办」（未来可行动）任务。
  ///
  /// 判据：未完成，且视觉状态不为 [TaskVisualState.overdue]。
  /// [resolveVisualState] 是唯一逾期判据——同时覆盖 `status==missed` 与
  /// pending-已过期两种情形；对重复任务永不返回 overdue，对冲突/待安排/
  /// 未来任务返回各自状态。逾期的一次性任务不进待办列表与待办计数，
  /// 仅在「全部」视图按时间桶以红色显示。
  bool isActionableTask(Task t) {
    if (t.status == TaskStatus.done) return false;
    return resolveVisualState(t, DateTime.now()) != TaskVisualState.overdue;
  }

  /// 是否逾期（需单独归集到「逾期」tab）。
  /// 判据唯一来源是 [resolveVisualState] == [TaskVisualState.overdue]；
  /// 已完成(done)/冲突(conflictBlocked)/重复(永远不逾期)/待安排/未来任务均不会命中。
  bool isOverdueTask(Task t) =>
      resolveVisualState(t, DateTime.now()) == TaskVisualState.overdue;

/// 视觉状态样式：集中「状态 → 颜色 / 软底 / 图标 / 描边填充 / 标签 / 透明度」。
///
/// 所有视觉映射只在此处定义；组件内禁止散落 [AppTheme] 字面量判定状态。
/// [filled] 表示图标为填充（filled）风格（完成/强提醒），否则为描边（outline）。
/// [actionable] 表示该状态是否仍需用户处理（用于语义区分，交互层仍保留 onToggle）。
class TaskStatusStyle {
  final Color color; // 主色（左色条 / 图标）
  final Color softColor; // 软底（徽章背景）
  final IconData icon; // 状态图标（Icons.*）
  final bool filled; // 描边 vs 填充
  final String label; // 徽章文案（无则空串）
  final bool actionable; // 是否可执行
  final double opacity; // 卡片透明度
  final String a11yLabel; // 无障碍标签

  const TaskStatusStyle({
    required this.color,
    required this.softColor,
    required this.icon,
    required this.filled,
    required this.label,
    required this.actionable,
    required this.opacity,
    required this.a11yLabel,
  });
}

/// 按视觉状态 + 主题取样式。深浅模式在此分支：暗色下文字/图标改用 *Dark 变体
/// 提对比（满足 WCAG AA），背景仍用 *Soft 软底。
TaskStatusStyle styleOf(TaskVisualState s, BuildContext ctx) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final danger = isDark ? AppTheme.dangerDark : AppTheme.danger;
  final ok = isDark ? AppTheme.okDark : AppTheme.ok;
  final warn = isDark ? AppTheme.warnDark : AppTheme.warn;
  final neutral = isDark ? AppTheme.neutralDark : AppTheme.neutral;
  const accent = AppTheme.accent; // 强调色固定青绿（规格未定义暗色变体）

  switch (s) {
    case TaskVisualState.unscheduled:
      return TaskStatusStyle(
        color: neutral,
        softColor: neutral.withValues(alpha: 0.14),
        icon: Icons.schedule_outlined,
        filled: false,
        label: '',
        actionable: true,
        opacity: 0.85,
        a11yLabel: '待安排任务',
      );
    case TaskVisualState.upcoming:
      return TaskStatusStyle(
        color: accent,
        softColor: AppTheme.accentSoft,
        icon: Icons.outlined_flag,
        filled: false,
        label: '',
        actionable: true,
        opacity: 1.0,
        a11yLabel: '待执行任务',
      );
    case TaskVisualState.inProgress:
      return TaskStatusStyle(
        color: warn,
        softColor: AppTheme.warnSoft,
        icon: Icons.play_circle,
        filled: true,
        label: '进行中',
        actionable: true,
        opacity: 1.0,
        a11yLabel: '进行中任务',
      );
    case TaskVisualState.overdue:
      return TaskStatusStyle(
        color: danger,
        softColor: AppTheme.dangerSoft,
        icon: Icons.event_busy,
        filled: true,
        label: '逾期',
        actionable: true,
        opacity: 1.0,
        a11yLabel: '已过期任务',
      );
    case TaskVisualState.done:
      return TaskStatusStyle(
        color: ok,
        softColor: AppTheme.okSoft,
        icon: Icons.check_circle,
        filled: true,
        label: '',
        actionable: false,
        opacity: 0.55,
        a11yLabel: '已完成任务',
      );
    case TaskVisualState.timePending:
      return TaskStatusStyle(
        color: warn,
        softColor: AppTheme.warnSoft,
        icon: Icons.schedule_outlined,
        filled: false,
        label: '时间待定',
        actionable: true,
        opacity: 0.9,
        a11yLabel: '时间待定任务',
      );
    case TaskVisualState.conflictBlocked:
      return TaskStatusStyle(
        color: danger,
        softColor: AppTheme.dangerSoft,
        icon: Icons.warning_amber_rounded,
        filled: true,
        label: '', // 冲突块沿用现有"资源冲突·未生效"
        actionable: false,
        opacity: 0.6,
        a11yLabel: '资源冲突未生效任务',
      );
  }
}
