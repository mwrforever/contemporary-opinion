import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../services/reminder_service.dart';
import '../../services/task_store.dart';
import '../../theme/task_status_style.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_tab_bar.dart';
import '../../widgets/speed_dial.dart';
import '../../widgets/task_card.dart';
import 'add_task_screen.dart';

/// 任务 Tab（设计稿方向 A）：筛选 Tab + 任务列表 + Speed Dial。
///
/// 数据来自 SQLite [TaskStore]；提醒经 [ReminderService] 编排。
/// 交互：勾选完成（重复任务完成今天滚动）、滑动删除二次确认、
/// 长按进入选择模式批量删除、冲突卡确认覆盖/改时间换资源。
class TasksTab extends StatefulWidget {
  const TasksTab({super.key, required this.store, required this.reminder});

  final TaskStore store;
  final ReminderService reminder;

  @override
  State<TasksTab> createState() => _TasksTabState();
}

enum _Filter { all, active, overdue, conflict, inProgress, done }

class _TasksTabState extends State<TasksTab> {
  _Filter _filter = _Filter.all;
  bool _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    // 加载 SQLite 任务；失败静默，空态兜底
    unawaited(_safe(widget.store.init()));
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// 提醒/存储的插件调用在测试或未初始化环境下失败时静默，不打断交互
  Future<void> _safe(Future<void> future) async {
    try {
      await future;
    } catch (_) {}
  }

  List<Task> _visible() {
    final all = widget.store.all;
    return switch (_filter) {
      _Filter.all => all,
      _Filter.active => all.where(isActionableTask).toList(),
      _Filter.overdue => all.where(isOverdueTask).toList(),
      _Filter.conflict => all.where((t) => t.hasPendingConflict).toList(),
      _Filter.inProgress => all.where(isInProgressTask).toList(),
      _Filter.done => all.where((t) => t.isDone).toList(),
    };
  }

  int _count(_Filter filter) {
    final all = widget.store.all;
    return switch (filter) {
      _Filter.all => all.length,
      _Filter.active => all.where(isActionableTask).length,
      _Filter.overdue => all.where(isOverdueTask).length,
      _Filter.conflict => all.where((t) => t.hasPendingConflict).length,
      _Filter.inProgress => all.where(isInProgressTask).length,
      _Filter.done => all.where((t) => t.isDone).length,
    };
  }

  Future<void> _goAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(
          store: widget.store,
          reminder: widget.reminder,
        ),
      ),
    );
  }

  void _goVoice() {
    // TODO(phase2): 语音规划于阶段 2 落地，当前给用户明确预期
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('语音规划将在阶段 2 上线')),
    );
  }

  Future<void> _openEdit(Task task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(
          store: widget.store,
          reminder: widget.reminder,
          editTask: task,
        ),
      ),
    );
  }

  Future<void> _toggleDone(Task task) async {
    await _safe(widget.store.toggleDone(task));
    await _safe(widget.reminder.notifyTaskChanged(task));
  }

  Future<void> _confirmOverride(Task task) async {
    await _safe(widget.store.resolveOverride(task));
    await _safe(widget.reminder.notifyTaskChanged(task));
  }

  /// 执行删除（滑动删除已在 confirmDismiss 中确认过，不再二次弹框）
  Future<void> _executeDelete(Task task) async {
    await _safe(widget.store.delete(task));
    await _safe(widget.reminder.cancelTask(task));
  }

  Future<void> _deleteSelected() async {
    final ok = await ConfirmDialog.show(
      context,
      '批量删除',
      '将删除已选 ${_selected.length} 个任务，确定吗？',
      '删除',
    );
    if (!ok || !mounted) return;
    for (final id in List<String>.of(_selected)) {
      final task = widget.store.getById(id);
      if (task == null) continue;
      await _safe(widget.store.delete(task));
      await _safe(widget.reminder.cancelTask(task));
    }
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  String _dateLabel() {
    final now = DateTime.now();
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 周${week[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      FilterTabItem(label: '全部', count: _count(_Filter.all)),
      FilterTabItem(label: '待办', count: _count(_Filter.active)),
      FilterTabItem(label: '进行中', count: _count(_Filter.inProgress)),
      FilterTabItem(label: '逾期', count: _count(_Filter.overdue)),
      FilterTabItem(label: '冲突', count: _count(_Filter.conflict)),
      FilterTabItem(label: '已完成', count: _count(_Filter.done)),
    ];
    final index = _Filter.values.indexOf(_filter);
    final visible = _visible();

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              title: Text('已选 ${_selected.length}'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selected.clear();
                  }),
                ),
              ],
            )
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_greeting()}，小许',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(_dateLabel(), style: const TextStyle(fontSize: 20)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_none),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  onPressed: () {},
                ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          FilterTabBar(
            items: items,
            selectedIndex: index,
            onSelected: (i) => setState(() => _filter = _Filter.values[i]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? const EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final task = visible[i];
                      final selected = _selected.contains(task.id);
                      return Dismissible(
                        key: ValueKey('task-${task.id}'),
                        direction: _selectionMode
                            ? DismissDirection.none
                            : DismissDirection.endToStart,
                        confirmDismiss: (_) => _selectionMode
                            ? Future.value(false)
                            : _confirmDeleteDialog(task),
                        onDismissed: (_) => _executeDelete(task),
                        background: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        child: TaskCard(
                          task: task,
                          selectionMode: _selectionMode,
                          selected: selected,
                          onToggleDone: () => _toggleDone(task),
                          onConfirmOverride: () => _confirmOverride(task),
                          onEdit: () => _openEdit(task),
                          onLongPress: () => _enterSelection(task.id),
                          onTap: _selectionMode
                              ? () => _toggleSelect(task.id)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: SpeedDial(onManual: _goAdd, onVoice: _goVoice),
    );
  }

  Future<bool> _confirmDeleteDialog(Task task) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除任务',
      '「${task.title}」删除后不可恢复，确定删除吗？',
      '删除',
    );
    return ok;
  }
}
