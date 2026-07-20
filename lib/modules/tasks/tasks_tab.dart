import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../theme/task_status_style.dart';
import '../../services/aliyun_asr_service.dart';
import '../../services/aliyun_schedule_service.dart';
import '../../services/reminder_service.dart';
import '../../services/settings_service.dart';
import '../../services/task_store.dart';
import '../../screens/settings_screen.dart';
import '../../widgets/speed_dial.dart';
import '../../widgets/task_feedback_card.dart';
import 'add_task_screen.dart';
import 'task_list.dart';
import 'voice_input_screen.dart';

/// 任务 Tab：当日概览 + 时间分组列表 + 居中滑动筛选 + Speed Dial。
///
/// 由 [HomeScreen] 重组而来，仅调整目录归属与依赖引用，逻辑保持不变。
class TasksTab extends StatefulWidget {
  final ReminderService reminder;
  final AliyunAsrService asr;
  final AliyunScheduleService schedule;
  final SettingsService settings;

  const TasksTab({
    super.key,
    required this.reminder,
    required this.asr,
    required this.schedule,
    required this.settings,
  });

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  TaskFilter _filter = TaskFilter.all;
  bool _fabOpen = false;
  bool _selectionMode = false;
  final Set<String> _selected = {};

  List<Task> _sortedFiltered(TaskStore store) {
    final list = switch (_filter) {
      TaskFilter.active => store.all.where(isActionableTask).toList(),
      TaskFilter.overdue => store.all.where(isOverdueTask).toList(),
      TaskFilter.conflict =>
        store.all.where((t) => t.hasPendingConflict).toList(),
      TaskFilter.all => List<Task>.from(store.all),
    };
    list.sort((a, b) {
      final ta = a.scheduledTime;
      final tb = b.scheduledTime;
      if (ta == null && tb == null) return a.title.compareTo(b.title);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    return list;
  }

  void _goAdd() {
    setState(() => _fabOpen = false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AddTaskScreen(reminder: widget.reminder, settings: widget.settings),
      ),
    );
  }

  /// 进入语音规划页；待其 `pop` 回传结果（{'added':n,'conflict':k}），
  /// 用 [TaskFeedbackCard] 展示成功反馈（解决屏内 SnackBar 不可见问题）。
  Future<void> _goVoice() async {
    setState(() => _fabOpen = false);
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceInputScreen(
          store: context.read<TaskStore>(),
          reminder: widget.reminder,
          asr: widget.asr,
          schedule: widget.schedule,
        ),
      ),
    );
    if (result is Map && result['added'] != null) {
      final added = result['added'] as int;
      final conflict = (result['conflict'] as int? ?? 0);
      final message = conflict > 0
          ? '已添加 $added 个任务，其中 $conflict 项存在冲突、待处理后生效'
          : '已添加 $added 个任务';
      TaskFeedbackCard.show(
        context,
        type: FeedbackType.success,
        message: message,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _toggle(Task task, TaskStore store) async {
    await store.toggleDone(task);
    await widget.reminder.notifyTaskChanged(task);
  }

  /// 删除任务：取消提醒调度并直接删除，不提供撤销、不弹提示。
  Future<void> _delete(Task task, TaskStore store) async {
    await widget.reminder.cancelTask(task);
    await store.delete(task);
  }

  void _goEdit(Task task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(
          reminder: widget.reminder,
          settings: widget.settings,
          task: task,
        ),
      ),
    );
  }

  /// 进入选择模式并选中指定任务。
  void _enterSelection(Task t) {
    setState(() {
      _selectionMode = true;
      _selected.add(t.id);
    });
  }

  /// 切换指定任务的选中态（选择模式下点击卡片触发）。
  void _toggleSelect(Task t) {
    setState(() {
      if (_selected.contains(t.id)) {
        _selected.remove(t.id);
      } else {
        _selected.add(t.id);
      }
    });
  }

  /// 退出选择模式并清空选中集合。
  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  /// 批量删除选中任务：先取消提醒调度再直接删除，不提供撤销、不弹提示。
  Future<void> _deleteSelected(TaskStore store) async {
    final removed = store.all.where((t) => _selected.contains(t.id)).toList();
    for (final t in removed) {
      await widget.reminder.cancelTask(t);
      await store.delete(t);
    }
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  /// 滑动删除二次确认：返回 [bool] 决定是否放行删除。
  /// 取消 → 卡片自动回弹不删；确认 → 触发 [TaskCard.onDismissed]（= _deleteWithUndo）。
  Future<bool> _confirmDelete(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定删除该任务？'),
        content: const Text('删除后无法撤销，确定删除该任务？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selected.length} 项' : '今日规划'),
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消',
              onPressed: _exitSelection,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除选中',
              onPressed: _selected.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('删除选中任务'),
                          content: Text(
                            '确定删除选中的 ${_selected.length} 项任务吗？删除后无法撤销。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(true),
                              child: const Text(
                                '删除',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        final store = context.read<TaskStore>();
                        await _deleteSelected(store);
                      }
                    },
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(settings: widget.settings),
                ),
              ),
            ),
        ],
      ),
      body: Consumer<TaskStore>(
        builder: (context, store, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              FilterTabBar(
                filter: _filter,
                onChanged: (f) => setState(() => _filter = f),
                total: store.all.length,
                active: store.all.where(isActionableTask).length,
                conflict: store.all.where((t) => t.hasPendingConflict).length,
                overdue: store.all.where(isOverdueTask).length,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TaskList(
                  key: ValueKey(_filter),
                  filter: _filter,
                  tasks: _sortedFiltered(store),
                  onAdd: _goAdd,
                  onVoice: _goVoice,
                  onTap: _goEdit,
                  onToggle: (t) => _toggle(t, store),
                  onDelete: (t) => _delete(t, store),
                  onResolve: (t) async {
                    await store.resolveOverride(t);
                    await widget.reminder.notifyTaskChanged(t);
                  },
                  selectionMode: _selectionMode,
                  selectedIds: _selected,
                  onLongPress: _enterSelection,
                  onSelect: _toggleSelect,
                  confirmDismiss: (t) => _confirmDelete(t),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: SpeedDial(
        open: _fabOpen,
        onToggle: () => setState(() => _fabOpen = !_fabOpen),
        onAdd: _goAdd,
        onVoice: _goVoice,
      ),
    );
  }
}
