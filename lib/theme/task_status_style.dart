import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/app_theme.dart';

/// 判断两个时刻是否同一天（用于重复任务「今日已完成」视觉判定）。
bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 任务视觉状态枚举。
///
/// 冒烟整改后覆盖 8 个视觉状态：待安排 / 待执行 / 进行中 / 倒计时重复 /
/// 已过期 / 已完成 / 冲突待处理 / 时间待定。
/// 「待办」「逾期」Tab 已移除：已过期（[TaskVisualState.past]）仅在「全部」
/// 中置灰展示；「进行中」不包含冲突任务；「已完成」只展示不再执行的死任务。
/// 除 [done]/[conflictBlocked]/[timePending] 外的状态均为纯派生（由
/// [resolveVisualState] 依据现有字段 + 当前时间计算），不持久化。
enum TaskVisualState {
  unscheduled, // 待安排：scheduledTime == null
  upcoming, // 待执行：已排定，触发时间在未来
  inProgress, // 进行中：[start, start+duration) 窗口内（派生）
  timer, // 倒计时重复：DELAYED 型任务（每 N 分钟 × M 次）
  past, // 已过期：一次性任务窗口已结束仍未完成（仅在「全部」置灰展示）
  done, // 已完成：不再需要执行的死任务
  conflictBlocked, // 冲突待处理：hasPendingConflict（未生效）
  timePending, // 时间待定：conflictState == undated（无具体时刻，未生效，待补时间）
}

/// 纯函数：由现有字段 + [now] 解析视觉状态。
///
/// 优先级自上而下：done > conflictBlocked > 时间待定 > 倒计时重复 >
/// 重复任务短路 > 待安排 > 时间窗口判定(inProgress / past / upcoming)。
/// 重复任务（[Task.isRepeating]）以 [Task.nextOccurrence] 为判定锚点，
/// 永不判 past——其自身会滚到下次，语义是「持续提醒」而非「已过期」。
TaskVisualState resolveVisualState(Task t, DateTime now) {
  if (t.isDone) return TaskVisualState.done;
  if (t.hasPendingConflict) return TaskVisualState.conflictBlocked;
  if (t.conflictState == ConflictState.undated) {
    return TaskVisualState.timePending;
  }
  if (t.isDelayed) {
    if (t.scheduledTime == null) return TaskVisualState.unscheduled;
    return TaskVisualState.timer;
  }
  if (t.isRepeating) {
    final start = t.nextOccurrence(now);
    if (start == null) return TaskVisualState.unscheduled;
    // 今天这一次已完成（completedAt 为同一天）→ 显示「进行中」（仍有后续执行计划，
    // 不因单次完成而判 done）；次日跨日自动回落。
    if (t.completedAt != null && _isSameDay(t.completedAt!, now)) {
      return TaskVisualState.inProgress;
    }
    if (!now.isBefore(start)) return TaskVisualState.inProgress;
    return TaskVisualState.upcoming;
  }
  if (t.scheduledTime == null) return TaskVisualState.unscheduled;
  final start = t.scheduledTime!;
  final end = start.add(Duration(minutes: t.durationMinutes));
  if (!now.isBefore(end)) return TaskVisualState.past;
  if (!now.isBefore(start)) return TaskVisualState.inProgress;
  return TaskVisualState.upcoming;
}

/// 是否属于「进行中」Tab 口径：未完成、非冲突、仍待执行
/// （含执行窗口内、未来待执行、倒计时重复链）。已过期与死任务不进入。
bool isInProgressTask(Task t, DateTime now) =>
    switch (resolveVisualState(t, now)) {
      TaskVisualState.inProgress ||
      TaskVisualState.upcoming ||
      TaskVisualState.timer => true,
      _ => false,
    };

/// 是否冲突任务（「冲突」Tab 口径）。
bool isConflictTask(Task t) => t.hasPendingConflict;

/// 是否已完成死任务（「已完成」Tab 口径：完成且未来不再执行）。
bool isDeadDoneTask(Task t, DateTime now) => t.isDeadDoneAt(now);

/// 是否已过期（仅「全部」中置灰展示）。
bool isPastTask(Task t, DateTime now) =>
    resolveVisualState(t, now) == TaskVisualState.past;

/// 视觉状态样式：集中「状态 → 颜色 / 软底 / 图标 / 描边填充 / 标签 / 透明度」。
///
/// 所有视觉映射只在此处定义；组件内禁止散落 [AppTheme] 字面量判定状态。
class TaskStatusStyle {
  final Color color;
  final Color softColor;
  final IconData icon;
  final bool filled;
  final String label;
  final bool actionable;
  final double opacity;
  final String a11yLabel;

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
  const accent = AppTheme.accent;

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
    case TaskVisualState.timer:
      return TaskStatusStyle(
        color: accent,
        softColor: AppTheme.accentSoft,
        icon: Icons.timer_outlined,
        filled: false,
        label: '',
        actionable: true,
        opacity: 1.0,
        a11yLabel: '倒计时重复任务',
      );
    case TaskVisualState.past:
      return TaskStatusStyle(
        color: neutral,
        softColor: neutral.withValues(alpha: 0.12),
        icon: Icons.history,
        filled: true,
        label: '',
        actionable: false,
        opacity: 0.55,
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
        label: '',
        actionable: false,
        opacity: 1.0,
        a11yLabel: '资源冲突未生效任务',
      );
  }
}
