import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/daos/settings_dao.dart';
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
import 'reminder_settings_sheet.dart';
import 'task_detail_sheet.dart';
import 'task_feedback_card.dart';
import 'voice_input_screen.dart';

/// 任务 Tab（V2）：4 状态 Tab + 统一记录行 + 详情抽屉 + 批量删除 + 语音浮层。
///
/// 冒烟整改口径：
/// - Tab 收敛为 全部/进行中/冲突/已完成；列表按创建时间降序（Store 保证）；
/// - 问候语动态读取昵称；铃铛=提醒方式设置；头像=跳转我的页；
/// - 长按多选 → 底部「删除（N）/ 取消」双按钮；
/// - 点击记录进详情抽屉（可编辑 + 冲突处理）。
class TasksTab extends StatefulWidget {
  const TasksTab({
    super.key,
    required this.store,
    required this.reminder,
    this.displayName = '朋友',
    this.userId = 1,
    this.onOpenProfile,
  });

  final TaskStore store;
  final ReminderService reminder;

  /// 首页问候语展示名（昵称优先，未设置回退用户名）
  final String displayName;
  final int userId;

  /// 头像按钮跳转「我的」页回调（由 MainPage 切换 Tab）
  final VoidCallback? onOpenProfile;

  @override
  State<TasksTab> createState() => _TasksTabState();
}

enum _Filter { all, inProgress, conflict, done }

class _TasksTabState extends State<TasksTab> {
  _Filter _filter = _Filter.all;
  bool _selectionMode = false;
  final Set<String> _selected = {};
  VoicePlanResult? _planResult;

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

  DateTime get _now => DateTime.now();

  List<Task> _visible() {
    final all = widget.store.all;
    return switch (_filter) {
      _Filter.all => all,
      _Filter.inProgress => all.where((t) => isInProgressTask(t, _now)).toList(),
      _Filter.conflict => all.where(isConflictTask).toList(),
      _Filter.done => all.where((t) => isDeadDoneTask(t, _now)).toList(),
    };
  }

  int _count(_Filter filter) {
    final all = widget.store.all;
    return switch (filter) {
      _Filter.all => all.length,
      _Filter.inProgress => all.where((t) => isInProgressTask(t, _now)).length,
      _Filter.conflict => all.where(isConflictTask).length,
      _Filter.done => all.where((t) => isDeadDoneTask(t, _now)).length,
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

  Future<void> _goVoice() async {
    final result = await showModalBottomSheet<VoicePlanResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceInputScreen(
        store: widget.store,
        reminder: widget.reminder,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _planResult = result);
  }

  /// 打开任务详情抽屉（可编辑 + 冲突处理）
  Future<void> _openDetail(Task task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: TaskDetailSheet(
            store: widget.store,
            reminder: widget.reminder,
            task: task,
          ),
        ),
      ),
    );
  }

  /// 铃铛：提醒方式设置浮层
  Future<void> _openReminderSettings() async {
    final dao = SettingsDao();
    final settings = await dao.get(widget.userId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ReminderSettingsSheet(
            userId: widget.userId,
            settings: settings,
            dao: dao,
          ),
        ),
      ),
    );
    // 设置变更后重新编排提醒（静音/音量等生效）
    await widget.reminder.reloadSettings(widget.userId);
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
      FilterTabItem(label: '进行中', count: _count(_Filter.inProgress)),
      FilterTabItem(label: '冲突', count: _count(_Filter.conflict)),
      FilterTabItem(label: '已完成', count: _count(_Filter.done)),
    ];
    final index = _Filter.values.indexOf(_filter);
    final visible = _visible();

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(title: Text('已选 ${_selected.length}'))
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_greeting()}，${widget.displayName}',
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
                  tooltip: '提醒方式',
                  onPressed: _openReminderSettings,
                ),
                IconButton(
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      widget.displayName.characters.first,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  tooltip: '我的',
                  onPressed: widget.onOpenProfile,
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
          if (_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.touch_app_outlined,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '点卡片勾选/取消',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
          if (_planResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TaskFeedbackCard(
                result: _planResult!,
                onDismiss: () => setState(() => _planResult = null),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? const EmptyState()
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: _selectionMode ? 120 : 88,
                    ),
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
                            color: scheme.error,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              if (_selectionMode) ...[
                                GestureDetector(
                                  key: ValueKey('select-${task.id}'),
                                  onTap: () => _toggleSelect(task.id),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    margin: const EdgeInsets.only(top: 10),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? scheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: selected
                                            ? scheme.primary
                                            : scheme.outline,
                                        width: 2,
                                      ),
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check,
                                            size: 15, color: Colors.white)
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: TaskCard(
                                  task: task,
                                  onTap: _selectionMode
                                      ? () => _toggleSelect(task.id)
                                      : () => _openDetail(task),
                                  onLongPress: _selectionMode
                                      ? null
                                      : () => _enterSelection(task.id),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : SpeedDial(onManual: _goAdd, onVoice: _goVoice),
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: _deleteSelected,
                        child: Text('删除（${_selected.length}）'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: () => setState(() {
                          _selectionMode = false;
                          _selected.clear();
                        }),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
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
