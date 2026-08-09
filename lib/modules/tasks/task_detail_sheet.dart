import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../services/reminder_service.dart';
import '../../services/task_store.dart';
import '../../theme/app_theme.dart';

/// 任务详情抽屉（V2）：可编辑表单 + 冲突原因卡 + 单一「完成」按钮。
///
/// 冒烟整改口径：
/// - 列表只做状态标记，详情与冲突处理入口都在本抽屉（点击记录打开）；
/// - 字段直接点击修改，完成后保存并自动返回（所有保存操作同理）；
/// - 冲突任务额外展示原因卡：「确认覆盖 / 改时间换资源」。
class TaskDetailSheet extends StatefulWidget {
  const TaskDetailSheet({
    super.key,
    required this.store,
    required this.reminder,
    required this.task,
  });

  final TaskStore store;
  final ReminderService reminder;
  final Task task;

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  late DateTime _date = widget.task.scheduledTime ?? DateTime.now();
  late TimeOfDay _time = widget.task.scheduledTime == null
      ? TimeOfDay.now()
      : TimeOfDay.fromDateTime(widget.task.scheduledTime!);
  late int _duration = widget.task.durationMinutes;
  late String _resource = widget.task.resource ?? '';
  late String _ring = widget.task.ringSeconds?.toString() ?? '';
  // 倒计时间隔默认取任务已存值；一次性倒计时（interval 为空）回退到
  // 创建时的分钟数，避免编辑保存时凭空引入 30 分钟间隔。
  late int _intervalMinutes =
      (widget.task.intervalSeconds ??
              ((widget.task.countdownMinutes ?? 30) * 60)) ~/
          60;
  // 重复次数默认 1：一次性倒计时任务仅保存不改动时保持一次性。
  late int _maxRepeats = widget.task.maxRepeats ?? 1;
  late final TextEditingController _resourceCtrl =
      TextEditingController(text: _resource);
  late final TextEditingController _ringCtrl =
      TextEditingController(text: _ring);

  /// 是否倒计时来源任务（含一次性倒计时）：详情中展示间隔/次数调节。
  bool get _isCountdownLike =>
      widget.task.isDelayed ||
      widget.task.countdownMinutes != null ||
      widget.task.countdownSeconds != null;
  bool get _isConflict => widget.task.hasPendingConflict;

  @override
  void dispose() {
    _resourceCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  String get _timeLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${_date.month}月${_date.day}日 ${two(_time.hour)}:${two(_time.minute)}';
  }

  Future<void> _pickTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    final tp = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (tp != null) setState(() => _time = tp);
  }

  Future<void> _pickDuration() async {
    final ctrl = TextEditingController(text: '$_duration');
    final value = await _textDialog('时长', '分钟（0 表示仅提醒不占时段）', ctrl);
    if (value != null) {
      setState(() => _duration = int.tryParse(value) ?? 0);
    }
  }

  Future<void> _pickResource() async {
    final value = await _textDialog('资源', '如：会议室A、车', _resourceCtrl);
    if (value != null) setState(() => _resource = value);
  }

  Future<void> _pickRing() async {
    final value = await _textDialog('响铃', '秒，留空使用默认', _ringCtrl);
    if (value != null) setState(() => _ring = value);
  }

  Future<String?> _textDialog(
    String title,
    String hint,
    TextEditingController controller,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          autocorrect: false,
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return value;
  }

  /// 确认覆盖：冲突任务强制生效。
  Future<void> _confirmOverride() async {
    await widget.store.resolveOverride(widget.task);
    await widget.reminder.notifyTaskChanged(widget.task);
    if (mounted) Navigator.of(context).pop();
  }

  /// 保存字段修改并自动返回。
  Future<void> _save() async {
    final t = widget.task;
    t.scheduledTime = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    t.durationMinutes = _duration;
    t.resource = _resource.isEmpty ? null : _resource;
    t.ringSeconds = int.tryParse(_ring);
    if (_isCountdownLike) {
      // 倒计时任务：重复次数 ≠ 1（含 -1 一直重复）转 DELAYED，
      // 为 1 时退化为一次性 ONCE
      final delayed = _maxRepeats != 1;
      t.triggerType = delayed ? TriggerType.delayed : TriggerType.once;
      t.intervalSeconds = delayed ? _intervalMinutes * 60 : null;
      t.maxRepeats = delayed ? _maxRepeats : null;
    }
    await widget.store.recheck(t);
    await widget.reminder.notifyTaskChanged(t);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: 26 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '任务详情',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _isConflict
                              ? AppTheme.dangerSoft
                              : scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _isConflict
                              ? Icons.warning_amber_rounded
                              : Icons.outlined_flag,
                          color: _isConflict ? AppTheme.danger : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.task.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isConflict ? '冲突待处理 · 暂不生效' : '正常生效',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: _isConflict
                                    ? AppTheme.danger
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isConflict) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.danger),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 15, color: AppTheme.danger),
                              const SizedBox(width: 6),
                              const Text(
                                '冲突原因',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '与既有任务时段重叠且占用同一资源，暂不生效。'
                            '可确认覆盖，或改时间/换资源后重新检测。',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.55,
                              color: AppTheme.danger,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.danger,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                ),
                                onPressed: _confirmOverride,
                                child: const Text(
                                  '确认覆盖',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: _pickTime,
                                child: const Text(
                                  '改时间/换资源',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _field(
                    label: '时间',
                    value: _duration > 0 ? '$_timeLabel · $_duration 分钟' : _timeLabel,
                    onTap: _pickTime,
                  ),
                  _field(label: '时长', value: '$_duration 分钟', onTap: _pickDuration),
                  _field(label: '资源', value: _resource.isEmpty ? '未设置' : _resource, onTap: _pickResource),
                  _field(label: '响铃', value: _ring.isEmpty ? '默认' : '$_ring 秒', onTap: _pickRing),
                  if (_isCountdownLike) ...[
                    _stepperField(
                      label: '每隔多久提醒一次',
                      value: '$_intervalMinutes 分钟',
                      onMinus: () => setState(
                        () => _intervalMinutes =
                            (_intervalMinutes - 1).clamp(1, 10080),
                      ),
                      onPlus: () => setState(
                        () => _intervalMinutes =
                            (_intervalMinutes + 1).clamp(1, 10080),
                      ),
                    ),
                    _stepperField(
                      label: '重复次数',
                      value: _maxRepeats == -1
                          ? '一直重复（已完成 ${widget.task.repeatCount} 次）'
                          : '$_maxRepeats 次（已完成 ${widget.task.repeatCount} 次）',
                      onMinus: () => setState(() {
                        // 从 1 递减直接跳到 -1（一直重复），跳过非法值 0
                        _maxRepeats = _maxRepeats == 1 ? -1 : _maxRepeats - 1;
                      }),
                      onPlus: () => setState(() {
                        // 从 -1 递增回到 1，之后按 1 步进
                        _maxRepeats = _maxRepeats == -1 ? 1 : _maxRepeats + 1;
                      }),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepperField({
    required String label,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, size: 22),
              onPressed: onMinus,
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, size: 22),
              onPressed: onPlus,
            ),
          ],
        ),
      ),
    );
  }
}
