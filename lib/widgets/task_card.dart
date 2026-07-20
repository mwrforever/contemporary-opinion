import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../theme/app_theme.dart';
import '../theme/task_status_style.dart';

/// 任务卡片：状态勾选、时间/重复/资源（内联轻量 meta）、点击编辑、左滑删除。
///
/// 视觉状态系统：通过 [resolveVisualState] + [styleOf] 集中映射「状态 → 颜色 /
/// 图标 / 标签 / 透明度」。[_StatusIcon] 兼具状态表达与勾选控件。冲突红边框 +
/// "资源冲突·未生效"块 + "确认覆盖"按钮原样保留。
class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onResolveOverride;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelect;

  /// 滑动删除二次确认：返回 [Future<bool>]。返回 false → 卡片自动回弹不删；
  /// 返回 true → 触发 [onDismissed]（= [onDelete]）。为 null 时直接放行。
  /// [selectionMode] 下 [Dismissible] 方向为 none，本回调不参与。
  final Future<bool> Function()? confirmDismiss;

  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
    this.onResolveOverride,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onSelect,
    this.confirmDismiss,
  });

  String get _timeLabel {
    if (task.scheduledTime == null) return '待安排';
    final t = task.scheduledTime!;
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final fmt = sameDay ? DateFormat('HH:mm') : DateFormat('MM/dd HH:mm');
    return fmt.format(t);
  }

  String get _repeatLabel {
    switch (task.repeat) {
      case RepeatType.daily:
        return '每天';
      case RepeatType.weekly:
        return '每周';
      case RepeatType.weekdays:
        return '工作日';
      case RepeatType.custom:
        final names = ['一', '二', '三', '四', '五', '六', '日'];
        final s = task.customWeekdays.map((w) => names[w - 1]).join('');
        return '每周$s';
      case RepeatType.none:
        return '';
    }
  }

  String get _createdLabel {
    final t = task.createdAt;
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final fmt = sameDay ? DateFormat('HH:mm') : DateFormat('MM/dd HH:mm');
    return '创建 ${fmt.format(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = resolveVisualState(task, DateTime.now());
    final style = styleOf(state, context);
    final conflict = task.hasPendingConflict;
    final undated = task.conflictState == ConflictState.undated;
    final done = task.isDone;

    // 选择模式下，状态图标点击 = 切换选中（而非完成切换）
    final VoidCallback? statusTap = selectionMode ? onSelect : onToggle;

    final titleColor = (conflict || undated)
        ? style.color
        : (done ? scheme.onSurface.withValues(alpha: 0.4) : scheme.onSurface);
    final metaColor = scheme.onSurface.withValues(alpha: 0.55);

    return Dismissible(
      key: ValueKey(task.id),
      direction: selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async =>
          confirmDismiss == null ? true : await confirmDismiss!(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Icon(Icons.delete_outline, color: AppTheme.danger),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          side: BorderSide(
            color: selectionMode && selected
                ? AppTheme.accent.withValues(alpha: 0.6)
                : (conflict
                    ? AppTheme.danger.withValues(alpha: 0.55)
                    : (undated
                        ? AppTheme.warn.withValues(alpha: 0.55)
                        : scheme.onSurface.withValues(alpha: 0.07))),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: selectionMode ? onSelect : onTap,
          onLongPress: selectionMode ? null : onLongPress,
            child: Opacity(
            opacity: style.opacity,
            // IntrinsicHeight 吸收 ListView(children:) 给子项的「无限竖向约束」：
            // 在无限高下，Row(crossAxisAlignment: stretch) + Expanded 无法解析高度会抛
            // "BoxConstraints forces an infinite height"；IntrinsicHeight 先取内容固有高度
            // （确定值）再让 stretch / Expanded 撑满，视觉完全不变。
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左色条：各状态主色（conflictBlocked 外加整卡红线边框，见上）
                  Container(width: 4, color: style.color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusIcon(style: style, onTap: statusTap ?? onToggle),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    color: titleColor,
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 7),
                                // 轻量 meta 行：时间为主，重复/资源以内联图标+文字呈现
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 14,
                                  children: [
                                    _MetaItem(
                                      icon: Icons.schedule_outlined,
                                      text: _timeLabel,
                                      color: style.color,
                                    ),
                                    if (task.countdownSeconds != null)
                                      _MetaItem(
                                        icon: Icons.timer_outlined,
                                        text: '${task.countdownSeconds}秒后',
                                        color: AppTheme.warn,
                                      ),
                                    if (_repeatLabel.isNotEmpty)
                                      _MetaItem(
                                        icon: Icons.repeat_outlined,
                                        text: _repeatLabel,
                                        color: metaColor,
                                      ),
                                    if (task.resource != null)
                                      _MetaItem(
                                        icon: Icons.place_outlined,
                                        text: task.resource!,
                                        color: metaColor,
                                      ),
                                    _MetaItem(
                                      icon: Icons.edit_calendar_outlined,
                                      text: _createdLabel,
                                      color: metaColor,
                                    ),
                                  ],
                                ),
                                // 状态徽章：进行中/逾期（conflictBlocked 沿用冲突块）
                                if (style.label.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _StatusBadge(style: style),
                                ],
                                if (conflict && onResolveOverride != null) ...[
                                  const SizedBox(height: 12),
                                  _ConflictBlock(onResolve: onResolveOverride!),
                                ] else if (undated && !selectionMode) ...[
                                  const SizedBox(height: 12),
                                  _UndatedBlock(onEdit: onTap),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _SelectIndicator(selected: selected),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选择模式下的勾选指示：圆形描边 + 选中时填充主色与对勾，带 200ms 过渡。
class _SelectIndicator extends StatelessWidget {
  final bool selected;

  const _SelectIndicator({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? AppTheme.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        border: Border.all(
          color: selected
              ? AppTheme.accent
              : scheme.onSurface.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 18, color: AppTheme.accent)
          : null,
    );
  }
}

/// 状态图标控件：兼具「状态表达」与「勾选完成」双重职责。
///
/// 渲染：左色条由 [TaskCard] 负责，此处渲染一个带状态色的圆形控件 +
/// [TaskStatusStyle.icon]（filled 态用软底填充，outline 态用描边环），点击 →
/// [onTap]（即 onToggle 切换完成）。点击后状态转 done 时图标自然变 check_circle。
class _StatusIcon extends StatelessWidget {
  final TaskStatusStyle style;
  final VoidCallback onTap;

  const _StatusIcon({required this.style, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = style.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Semantics(
          label: style.a11yLabel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.filled
                  ? color.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                color: style.filled
                    ? color.withValues(alpha: 0.0)
                    : color.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Icon(style.icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// 状态徽章：进行中 / 逾期 的小 pill（软底 + 状态主色文字）。
class _StatusBadge extends StatelessWidget {
  final TaskStatusStyle style;

  const _StatusBadge({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.softColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: style.color,
        ),
      ),
    );
  }
}

/// 内联 meta 单元：图标 + 文字，避免重复堆叠胶囊。
class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaItem({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 冲突块：单一醒目色块，承载"未生效"说明与"确认覆盖"动作。
class _ConflictBlock extends StatelessWidget {
  final VoidCallback onResolve;

  const _ConflictBlock({required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 17, color: AppTheme.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '资源冲突 · 未生效',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.danger,
              ),
            ),
          ),
          TextButton(
            onPressed: onResolve,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.danger,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('确认覆盖'),
          ),
        ],
      ),
    );
  }
}

/// 时间待定块：amber 警示，引导用户点击「设置时间」编辑补具体时刻后生效。
class _UndatedBlock extends StatelessWidget {
  final VoidCallback onEdit;

  const _UndatedBlock({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warnSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, size: 17, color: AppTheme.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '时间待定 · 未生效，设置时间后才会提醒',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.warn,
              ),
            ),
          ),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.warn,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('设置时间'),
          ),
        ],
      ),
    );
  }
}
