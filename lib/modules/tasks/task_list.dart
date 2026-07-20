import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/fade_in.dart';
import '../../widgets/task_card.dart';

/// 任务列表筛选维度。
enum TaskFilter { all, active, overdue, conflict }

/// 居中滑动筛选 Tab（全部 / 进行中 / 冲突，自带随动指示器动画）。
///
/// 自持 [TabController]（随组件生命周期创建/释放），指示器为 [AppTheme.accentSoft]
/// 圆角 pill，随 [TabBar] 内建动画随动；切换无跳变。文案与计数由父级传入，
/// 选中变化通过 [onChanged] 上抛 [TaskFilter]。
class FilterTabBar extends StatefulWidget {
  final TaskFilter filter;
  final ValueChanged<TaskFilter> onChanged;
  final int total;
  final int active;
  final int conflict;
  final int overdue;

  const FilterTabBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.total,
    required this.active,
    required this.conflict,
    required this.overdue,
  });

  @override
  State<FilterTabBar> createState() => _FilterTabBarState();
}

class _FilterTabBarState extends State<FilterTabBar>
    with SingleTickerProviderStateMixin {
  static const List<(TaskFilter, String)> _tabs = [
    (TaskFilter.all, '全部'),
    (TaskFilter.active, '待办'),
    (TaskFilter.overdue, '逾期'),
    (TaskFilter.conflict, '冲突'),
  ];

  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _indexOf(widget.filter),
    );
  }

  @override
  void didUpdateWidget(covariant FilterTabBar old) {
    super.didUpdateWidget(old);
    final target = _indexOf(widget.filter);
    if (target != _controller.index) _controller.animateTo(target);
  }

  int _indexOf(TaskFilter f) => _tabs.indexWhere((t) => t.$1 == f);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spaceLg),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: TabBar(
        controller: _controller,
        isScrollable: false,
        padding: EdgeInsets.zero,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppTheme.accentSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        labelColor: AppTheme.accent,
        unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.5),
        labelStyle: Theme.of(context).textTheme.labelMedium,
        unselectedLabelStyle: Theme.of(context).textTheme.labelMedium,
        onTap: (i) {
          _controller.animateTo(i);
          widget.onChanged(_tabs[i].$1);
        },
        tabs: [
          for (final (f, label) in _tabs) Tab(text: '$label  ${_count(f)}'),
        ],
      ),
    );
  }

  int _count(TaskFilter f) {
    switch (f) {
      case TaskFilter.all:
        return widget.total;
      case TaskFilter.active:
        return widget.active;
      case TaskFilter.overdue:
        return widget.overdue;
      case TaskFilter.conflict:
        return widget.conflict;
    }
  }
}

/// 列表分组头：主色竖条 + 标题 + 计数（与表单 [Section] 视觉语言一致）。
class SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const SectionHeader({super.key, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 任务列表：全部视图下按 上午 / 下午 / 晚上 / 待安排 时间桶分组。
class TaskList extends StatelessWidget {
  final TaskFilter filter;
  final List<Task> tasks;
  final VoidCallback onAdd;
  final VoidCallback onVoice;
  final ValueChanged<Task> onTap;
  final ValueChanged<Task> onToggle;
  final ValueChanged<Task> onDelete;
  final ValueChanged<Task> onResolve;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<Task>? onLongPress;
  final ValueChanged<Task>? onSelect;
  final Future<bool> Function(Task)? confirmDismiss;

  const TaskList({
    super.key,
    required this.filter,
    required this.tasks,
    required this.onAdd,
    required this.onVoice,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
    required this.onResolve,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onLongPress,
    this.onSelect,
    this.confirmDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const EmptyState();
    }

    if (filter != TaskFilter.all) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _card(tasks[i], i),
      );
    }

    final buckets = <(String, bool Function(Task))>[
      ('上午', (t) => t.scheduledTime != null && t.scheduledTime!.hour < 12),
      ('下午',
          (t) =>
              t.scheduledTime != null &&
              t.scheduledTime!.hour >= 12 &&
              t.scheduledTime!.hour < 18),
      ('晚上', (t) => t.scheduledTime != null && t.scheduledTime!.hour >= 18),
      ('待安排', (t) => t.scheduledTime == null),
    ];

    final widgets = <Widget>[];
    var idx = 0;
    for (final (label, pred) in buckets) {
      final items = tasks.where(pred).toList();
      if (items.isEmpty) continue;
      widgets.add(SectionHeader(label: label, count: items.length));
      for (final t in items) {
        widgets.add(_card(t, idx));
        widgets.add(const SizedBox(height: 12));
        idx++;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: widgets,
    );
  }

  Widget _card(Task task, int index) => FadeIn(
        delay: Duration(milliseconds: index * 40),
        child: TaskCard(
          task: task,
          selectionMode: selectionMode,
          selected: selectedIds.contains(task.id),
          onTap: () => onTap(task),
          onToggle: () => onToggle(task),
          onDelete: () => onDelete(task),
          onLongPress: onLongPress == null ? null : () => onLongPress!(task),
          onSelect: onSelect == null ? null : () => onSelect!(task),
          onResolveOverride: task.hasPendingConflict
              ? () => onResolve(task)
              : null,
          confirmDismiss: confirmDismiss == null
              ? null
              : () => confirmDismiss!(task),
        ),
      );
}
