import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/task_status_style.dart';

/// 任务记录卡片（V2 统一记录行）。
///
/// 冒烟整改口径：
/// - 每条记录以状态图标打头，标题与元信息各一行、超出省略；
/// - 冲突任务与其它记录同构，仅以红色状态图标 + 「冲突 · 暂不生效」标记；
/// - 冲突原因/处理入口收进详情抽屉（[onTap]）；
/// - 复选框只在批量删除模式出现，且由列表层渲染在卡片之外。
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, this.onTap, this.onLongPress});

  final Task task;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final state = resolveVisualState(task, now);
    final style = styleOf(state, context);
    final isDead = state == TaskVisualState.done || state == TaskVisualState.past;
    final isConflict = task.hasPendingConflict;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态图标打头（42×42 圆角方块，语义色软底）
          Container(
            key: ValueKey('task-icon-${task.id}'),
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: style.softColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              style.icon,
              size: 20,
              color: style.color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F101315),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Opacity(
                opacity: style.opacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题：单行，超出省略
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: isDead
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                        decoration:
                            isDead ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 元信息：单行，超出省略
                    _MetaLine(task: task, state: state, now: now),
                    if (isConflict) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 13,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '点击查看冲突详情',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单行元信息：时间 · 时长 · 资源 · 重复/倒计时进度 · 冲突标记。
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.task, required this.state, required this.now});

  final Task task;
  final TaskVisualState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];

    void addText(String text, {Color? color, FontWeight? weight}) {
      if (items.isNotEmpty) {
        items.add(Text(
          '·',
          style: TextStyle(fontSize: 12.5, color: scheme.outline),
        ));
      }
      items.add(Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: color ?? scheme.onSurfaceVariant,
            fontWeight: weight,
          ),
        ),
      ));
    }

    final delayed = _delayedLabel();
    if (delayed.isNotEmpty) {
      addText(delayed, color: scheme.tertiary, weight: FontWeight.w700);
    } else if (task.isRecurring && _repeatLabel().isNotEmpty) {
      addText(_repeatLabel(), color: scheme.tertiary, weight: FontWeight.w700);
    }

    if (task.hasPendingConflict) {
      addText('冲突 · 暂不生效', color: scheme.error, weight: FontWeight.w700);
    }

    final fire = task.nextFireFor(now);
    if (fire != null) {
      if (state == TaskVisualState.inProgress) {
        addText(
          '${_hm(fire)} 进行中',
          color: Theme.of(context).colorScheme.tertiary,
          weight: FontWeight.w700,
        );
      } else {
        addText(_timeText(fire));
      }
    } else if (task.scheduledTime != null) {
      addText(_timeText(task.scheduledTime!));
    }

    if (task.durationMinutes > 0) {
      addText('${task.durationMinutes} 分钟');
    }
    if (task.resource != null && task.resource!.isNotEmpty) {
      items.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          task.resource!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ));
    }

    return Row(
      children: items,
    );
  }

  String _hm(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  String _timeText(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
  }

  String _delayedLabel() {
    if (!task.isDelayed) return '';
    final secs = task.intervalSeconds ?? 0;
    final unit = secs % 3600 == 0
        ? '${secs ~/ 3600} 小时'
        : secs % 60 == 0
            ? '${secs ~/ 60} 分钟'
            : '$secs 秒';
    final total = task.maxRepeats;
    if (task.repeatsForever) {
      // 一直重复：不显示上限，仅展示当前次数
      return '每 $unit · 第 ${task.repeatCount + 1} 次';
    }
    return total == null ? '每 $unit' : '每 $unit · 第 ${task.repeatCount + 1}/$total 次';
  }

  String _repeatLabel() {
    const chars = ['一', '二', '三', '四', '五', '六', '日'];
    return switch (task.repeat) {
      RepeatType.none => '',
      RepeatType.daily => '每天',
      RepeatType.weekly => '每周',
      RepeatType.weekdays => '工作日',
      RepeatType.custom => task.customWeekdays.isEmpty
          ? ''
          : '每周${task.customWeekdays.map((w) => chars[w - 1]).join()}',
    };
  }
}
