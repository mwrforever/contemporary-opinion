import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/app_theme.dart';

/// 任务卡片（设计稿方向 A）：正常/冲突/时间待定/已完成/已逾期五态。
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleDone,
    this.onConfirmOverride,
    this.onEdit,
    this.onLongPress,
    this.onTap,
  });

  final Task task;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleDone;
  final VoidCallback? onConfirmOverride;
  final VoidCallback? onEdit;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  static const _weekdayChars = ['一', '二', '三', '四', '五', '六', '日'];

  String get _repeatLabel => switch (task.repeat) {
        RepeatType.none => '',
        RepeatType.daily => '每天',
        RepeatType.weekly => '每周',
        RepeatType.weekdays => '工作日',
        RepeatType.custom => task.customWeekdays.isEmpty
            ? ''
            : '每周${task.customWeekdays.map((w) => _weekdayChars[w - 1]).join()}',
      };

  String _timeText(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isConflict = task.hasPendingConflict;
    final isUndated = task.conflictState == ConflictState.undated;
    final isDone = task.isDone;
    final isMissed = task.status == TaskStatus.missed;

    Color? borderColor;
    Color? bgColor;
    if (isConflict) {
      borderColor = AppTheme.danger;
      bgColor = AppTheme.dangerSoft;
    } else if (isUndated) {
      borderColor = AppTheme.warn;
      bgColor = AppTheme.warnSoft;
    }

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor ?? scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: borderColor ?? scheme.outlineVariant,
            width: borderColor != null ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 勾选 / 选择态
            GestureDetector(
              key: ValueKey('task-check-${task.id}'),
              onTap: selectionMode ? onTap : onToggleDone,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDone || selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDone || selected ? scheme.primary : scheme.outline,
                  ),
                ),
                child: isDone || selected
                    ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: isDone
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (isConflict)
                        _Badge(text: '资源冲突', color: AppTheme.danger),
                      if (isMissed)
                        _Badge(
                          text: '已逾期',
                          color: scheme.surfaceContainerHighest,
                          foreground: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (task.scheduledTime != null)
                        Text(
                          _timeText(task.scheduledTime!),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isMissed
                                ? AppTheme.danger
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      if (task.durationMinutes > 0)
                        Text(
                          '${task.durationMinutes} 分钟',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (task.resource != null && task.resource!.isNotEmpty)
                        _ResourceChip(resource: task.resource!),
                      if (_repeatLabel.isNotEmpty)
                        Text(
                          _repeatLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (isConflict) ...[
                    const SizedBox(height: 8),
                    Text(
                      '与既有任务时段重叠且占用同一资源，暂不生效',
                      style: TextStyle(fontSize: 12, color: AppTheme.danger),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: onConfirmOverride,
                          child: const Text(
                            '确认覆盖',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: onEdit,
                          child: const Text(
                            '改时间/换资源',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (isUndated) ...[
                    const SizedBox(height: 8),
                    Text(
                      '时间待定，补时间后生效',
                      style: TextStyle(fontSize: 12, color: AppTheme.warn),
                    ),
                    TextButton(
                      onPressed: onEdit,
                      child: const Text('设时间', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态徽标
class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.foreground});

  final String text;
  final Color color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground ?? Colors.white,
        ),
      ),
    );
  }
}

/// 资源胶囊
class _ResourceChip extends StatelessWidget {
  const _ResourceChip({required this.resource});

  final String resource;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        resource,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
