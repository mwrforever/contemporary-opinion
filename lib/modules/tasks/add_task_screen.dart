import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/task.dart';
import '../../services/reminder_service.dart';
import '../../services/task_store.dart';

/// 新建/编辑任务页（设计稿方向 A 分区表单）。
///
/// 提醒设置支持「指定时间 / 倒计时」两种录入；重复支持自定义星期；
/// 保存时经 [TaskStore.addWithConflictCheck] 做冲突检测（编辑走 recheck）。
class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({
    super.key,
    required this.store,
    required this.reminder,
    this.editTask,
  });

  final TaskStore store;
  final ReminderService reminder;
  final Task? editTask;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  final _resourceController = TextEditingController();
  final _durationController = TextEditingController();
  final _ringController = TextEditingController();

  bool _useCountdown = false;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  int _countdownMinutes = 30;
  int _countdownRepeats = 1;
  RepeatType _repeat = RepeatType.none;
  final Set<int> _weekdays = {};

  bool get _isEdit => widget.editTask != null;

  @override
  void initState() {
    super.initState();
    final t = widget.editTask;
    _title = TextEditingController(text: t?.title ?? '');
    _resourceController.text = t?.resource ?? '';
    // 新建任务资源占用时长默认 1 分钟；编辑时沿用已保存值
    _durationController.text = t != null && t.durationMinutes > 0
        ? '${t.durationMinutes}'
        : (t == null ? '1' : '');
    _ringController.text = t?.ringSeconds?.toString() ?? '';
    if (t?.isDelayed == true) {
      // 倒计时重复任务：编辑时还原为倒计时模式 + 间隔/次数（-1 表示一直重复）
      _useCountdown = true;
      _countdownMinutes = (t!.intervalSeconds ?? 0) ~/ 60;
      _countdownRepeats = t.maxRepeats ?? 1;
    } else if (t?.countdownMinutes != null || t?.countdownSeconds != null) {
      // 一次性倒计时任务：编辑时同样还原为倒计时模式（重复次数保持 1）
      _useCountdown = true;
      final minutes =
          t!.countdownMinutes ?? ((t.intervalSeconds ?? 1800) ~/ 60);
      _countdownMinutes = minutes > 0 ? minutes : 1;
    }
    if (t?.scheduledTime != null) {
      _date = t!.scheduledTime!;
      _time = TimeOfDay.fromDateTime(t.scheduledTime!);
      _repeat = t.repeat;
      _weekdays.addAll(t.customWeekdays);
    } else if (t == null) {
      // 新建默认时间 = 下一分钟：毫秒级过期检测下「当前分钟」已属过去，
      // 默认值直接落在未来，保证打开即存也能通过
      final nextMinute = DateTime.now().add(const Duration(minutes: 1));
      _date = nextMinute;
      _time = TimeOfDay.fromDateTime(nextMinute);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _resourceController.dispose();
    _durationController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  DateTime _scheduledTime() {
    if (_useCountdown) {
      return DateTime.now().add(Duration(minutes: _countdownMinutes));
    }
    return DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final when = _scheduledTime();
    // 毫秒级过期检测：指定时间只要早于当前时刻（含同一分钟内的秒/毫秒）
    // 即不允许保存（倒计时模式由 now+分钟 推导，天然不早于 now）
    if (!_useCountdown && when.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始时间不能早于现在')),
      );
      return;
    }

    final duration = int.tryParse(_durationController.text) ?? 0;
    final ring = int.tryParse(_ringController.text);
    // 重复次数管理重复：1 为单次提醒，>1 按间隔重复，-1 表示一直重复
    final repeats = _useCountdown ? _countdownRepeats : 1;
    final isDelayedCountdown = _useCountdown && repeats != 1;
    final resource =
        _resourceController.text.trim().isEmpty
            ? null
            : _resourceController.text.trim();

    if (_isEdit) {
      final t = widget.editTask!;
      t.title = _title.text.trim();
      t.scheduledTime = when;
      if (_useCountdown) {
        // 倒计时任务不叠加日历重复：由重复次数决定 DELAYED/ONCE
        t.repeat = RepeatType.none;
        t.customWeekdays = const [];
        t.triggerType =
            isDelayedCountdown ? TriggerType.delayed : TriggerType.once;
        t.intervalSeconds = isDelayedCountdown ? _countdownMinutes * 60 : null;
        t.maxRepeats = isDelayedCountdown ? repeats : null;
      } else {
        t.repeat = _repeat;
        t.customWeekdays = _repeat == RepeatType.custom
            ? (_weekdays.toList()..sort())
            : const [];
        t.triggerType =
            _repeat == RepeatType.none ? TriggerType.once : TriggerType.recurring;
        t.intervalSeconds = null;
        t.maxRepeats = null;
      }
      t.resource = resource;
      t.durationMinutes = duration;
      t.ringSeconds = ring;
      await widget.store.recheck(t);
      await _notifyChanged(t);
      _warnIfConflict(t);
    } else {
      final task = Task(
        id: const Uuid().v4(),
        title: _title.text.trim(),
        scheduledTime: when,
        countdownMinutes: _useCountdown ? _countdownMinutes : null,
        triggerType: isDelayedCountdown ? TriggerType.delayed : null,
        intervalSeconds: isDelayedCountdown ? _countdownMinutes * 60 : null,
        maxRepeats: isDelayedCountdown ? repeats : null,
        nextFireTime: isDelayedCountdown ? when : null,
        repeat: _useCountdown ? RepeatType.none : _repeat,
        customWeekdays: _useCountdown
            ? const []
            : (_repeat == RepeatType.custom ? (_weekdays.toList()..sort()) : const []),
        resource: resource,
        durationMinutes: duration,
        ringSeconds: ring,
        createdAt: now,
        notificationId: now.millisecondsSinceEpoch ~/ 1000 % 1000000,
      );
      await widget.store.addWithConflictCheck(task);
      await _notifyChanged(task);
      _warnIfConflict(task);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 冲突任务仍允许保存，但弹 SnackBar 警告：
  /// 该任务已标记「冲突待处理」且暂不执行，需在列表中手动处理（改时间/换资源/确认覆盖）。
  void _warnIfConflict(Task task) {
    if (task.hasPendingConflict && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该任务与既有任务存在资源冲突：已标记「冲突待处理」且暂不执行，'
              '可在任务列表中改时间/换资源或确认覆盖'),
        ),
      );
    }
  }

  /// 提醒编排失败（如通知权限缺失）不阻断保存与关闭页面。
  ///
  /// 任务已落库，后续权限开启后 [ReminderService.scheduleAll] 会补齐调度。
  Future<void> _notifyChanged(Task task) async {
    try {
      await widget.reminder.notifyTaskChanged(task);
    } catch (_) {
      // 调度失败静默，不打断「保存后关闭新增界面」
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑任务' : '新建任务')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('基本信息'),
              TextFormField(
                controller: _title,
                // 荣耀 IME 兼容：autocorrect:true 会映射成 AUTO_CORRECT 标志导致
                // 键盘不弹出（原生 EditText 普通框不带此标志）；enableSuggestions
                // 保持默认 true，避免 NO_SUGGESTIONS 被误判为密码框触发安全键盘。
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '如：明早 9 点开会',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入标题' : null,
              ),
              _sectionTitle('提醒设置'),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('指定时间')),
                  ButtonSegment(value: true, label: Text('倒计时')),
                ],
                selected: {_useCountdown},
                onSelectionChanged: (s) =>
                    setState(() => _useCountdown = s.first),
              ),
              const SizedBox(height: 12),
              if (_useCountdown)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: '$_countdownMinutes',
                      keyboardType: TextInputType.number,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '每隔（分钟）',
                        suffixText: '分钟提醒一次',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) return '请输入大于 0 的分钟数';
                        return null;
                      },
                      onChanged: (v) =>
                          _countdownMinutes = int.tryParse(v) ?? _countdownMinutes,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: '$_countdownRepeats',
                      keyboardType: TextInputType.number,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '重复次数',
                        helperText: '默认 1 次；-1 表示一直重复',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < -1 || n == 0) {
                          return '请输入大于 0 的次数，-1 表示一直重复';
                        }
                        return null;
                      },
                      onChanged: (v) =>
                          _countdownRepeats = int.tryParse(v) ?? _countdownRepeats,
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _readonlyField(
                        label: '日期',
                        value:
                            '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _readonlyField(
                        label: '时间',
                        value:
                            '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
              ],
              if (!_useCountdown) ...[
                _sectionTitle('重复'),
                DropdownButtonFormField<RepeatType>(
                  initialValue: _repeat,
                  items: const [
                    DropdownMenuItem(value: RepeatType.none, child: Text('不重复')),
                    DropdownMenuItem(value: RepeatType.daily, child: Text('每天')),
                    DropdownMenuItem(value: RepeatType.weekly, child: Text('每周')),
                    DropdownMenuItem(
                      value: RepeatType.weekdays,
                      child: Text('工作日'),
                    ),
                    DropdownMenuItem(
                      value: RepeatType.custom,
                      child: Text('自定义星期'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _repeat = v ?? RepeatType.none),
                ),
                if (_repeat == RepeatType.custom) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var w = 1; w <= 7; w++)
                        ChoiceChip(
                          label: Text(
                              '周${['一', '二', '三', '四', '五', '六', '日'][w - 1]}'),
                          selected: _weekdays.contains(w),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _weekdays.add(w);
                            } else {
                              _weekdays.remove(w);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ],
              _sectionTitle('资源与时长'),
              TextFormField(
                controller: _resourceController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '资源（可选）',
                  hintText: '如：会议室A、车',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '时长（分钟，可选）',
                  hintText: '0 表示仅提醒不占时段',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ringController,
                keyboardType: TextInputType.number,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '响铃（秒，可选）',
                  hintText: '留空使用默认',
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(_isEdit ? '保存修改' : '保存任务'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _readonlyField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.chevron_right),
        ),
        child: Text(value, style: TextStyle(color: scheme.onSurface)),
      ),
    );
  }
}
