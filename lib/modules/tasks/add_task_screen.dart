import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/task.dart';
import '../../services/reminder_service.dart';
import '../../services/task_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_label.dart';
import '../../widgets/section.dart';
import '../../services/settings_service.dart';

/// 任务录入：手动分区表单。
///
/// 由 `lib/screens/add_task_screen.dart` 迁移至本模块，逻辑不变，仅将私有的
/// `_Section` / `_FieldLabel` 替换为共享组件 [Section] / [FieldLabel]。
class AddTaskScreen extends StatefulWidget {
  final ReminderService reminder;
  final SettingsService settings;
  final Task? task;

  const AddTaskScreen({
    super.key,
    required this.reminder,
    required this.settings,
    this.task,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _resourceCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _ringCtrl = TextEditingController();

  bool _countdownMode = false;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  RepeatType _repeat = RepeatType.none;
  List<int> _customWeekdays = const [];

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t != null) {
      _titleCtrl.text = t.title;
      _repeat = t.repeat;
      _customWeekdays = List<int>.from(t.customWeekdays);
      _resourceCtrl.text = t.resource ?? '';
      _durationCtrl.text = t.durationMinutes.toString();
      _ringCtrl.text =
          (t.ringSeconds ?? widget.settings.ringSecondsDefault).toString();
      if (t.countdownMinutes != null) {
        _countdownMode = true;
        _minutesCtrl.text = t.countdownMinutes.toString();
      } else if (t.scheduledTime != null) {
        _date = t.scheduledTime!;
        _time = TimeOfDay.fromDateTime(t.scheduledTime!);
      }
    } else {
      _durationCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _minutesCtrl.dispose();
    _resourceCtrl.dispose();
    _durationCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  DateTime? _buildScheduledTime() {
    if (_countdownMode) {
      final mins = int.tryParse(_minutesCtrl.text);
      if (mins == null || mins <= 0) return null;
      return DateTime.now().add(Duration(minutes: mins));
    }
    return DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final store = context.read<TaskStore>();
    final scheduled = _buildScheduledTime();
    final countdown = _countdownMode
        ? (int.tryParse(_minutesCtrl.text) ?? 0)
        : null;
    final duration = int.tryParse(_durationCtrl.text) ?? 0;
    final ringRaw = int.tryParse(_ringCtrl.text.trim());
    final resource = _resourceCtrl.text.trim().isEmpty
        ? null
        : _resourceCtrl.text.trim();

    final task = widget.task ??
        Task(
          id: const Uuid().v4(),
          title: title,
          createdAt: DateTime.now(),
          notificationId:
              DateTime.now().microsecondsSinceEpoch % 2147483647,
          countdownMinutes: countdown,
        );

    task.title = title;
    task.scheduledTime = scheduled;
    task.repeat = _repeat;
    task.customWeekdays =
        _repeat == RepeatType.custom ? _customWeekdays : const [];
    task.durationMinutes = duration;
    task.ringSeconds = (ringRaw != null && ringRaw > 0) ? ringRaw : null;
    task.resource = resource;
    if (widget.task == null) {
      task.source = TaskSource.manual;
    }

    if (widget.task == null) {
      // 新建：自动冲突检测，冲突任务默认不生效
      await store.addWithConflictCheck(task);
    } else {
      // 编辑：改时间/换资源后重检冲突
      await store.recheck(task);
    }
    // 仅对已生效任务调度提醒（冲突待处理任务不提醒，直至解决）
    if (task.effective) {
      await widget.reminder.notifyTaskChanged(task);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑任务' : '新建任务'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Section(
              title: '基本信息',
              children: [
                const FieldLabel('任务内容'),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    hintText: '例如：下午3点开会 / 吃药',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请填写任务内容' : null,
                ),
              ],
            ),
            Section(
              title: '提醒设置',
              children: [
                const FieldLabel('提醒方式'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('指定时间')),
                    ButtonSegment(value: true, label: Text('倒计时')),
                  ],
                  selected: {_countdownMode},
                  onSelectionChanged: (s) =>
                      setState(() => _countdownMode = s.first),
                ),
                const SizedBox(height: 16),
                if (_countdownMode)
                  TextFormField(
                    controller: _minutesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '分钟数，例如 30',
                      suffixText: '分钟后提醒',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0) return '请输入有效分钟数';
                      return null;
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(DateFormat('yyyy/MM/dd').format(_date)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickTime,
                          icon: const Icon(Icons.access_time_outlined),
                          label: Text(_time.format(context)),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                const FieldLabel('重复'),
                DropdownButtonFormField<RepeatType>(
                  initialValue: _repeat,
                  decoration: const InputDecoration(),
                  items: const [
                    DropdownMenuItem(
                        value: RepeatType.none, child: Text('不重复')),
                    DropdownMenuItem(
                        value: RepeatType.daily, child: Text('每天')),
                    DropdownMenuItem(
                        value: RepeatType.weekly,
                        child: Text('每周（按设定日）')),
                    DropdownMenuItem(
                        value: RepeatType.weekdays, child: Text('工作日')),
                    DropdownMenuItem(
                        value: RepeatType.custom, child: Text('自定义星期')),
                  ],
                  onChanged: (v) =>
                      setState(() => _repeat = v ?? RepeatType.none),
                ),
                if (_repeat == RepeatType.custom) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in const [
                        (1, '一'),
                        (2, '二'),
                        (3, '三'),
                        (4, '四'),
                        (5, '五'),
                        (6, '六'),
                        (7, '日'),
                      ])
                        ChoiceChip(
                          label: Text('周${e.$2}'),
                          selected: _customWeekdays.contains(e.$1),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _customWeekdays = [..._customWeekdays, e.$1]..sort();
                            } else {
                              _customWeekdays = _customWeekdays
                                  .where((w) => w != e.$1)
                                  .toList();
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            Section(
              title: '资源与时长',
              children: [
                const FieldLabel('所需资源（可选）'),
                TextFormField(
                  controller: _resourceCtrl,
                  decoration: const InputDecoration(
                    hintText: '如 会议室A / 车 / 张经理（用于资源占用冲突检测）',
                  ),
                ),
                const SizedBox(height: 24),
                const FieldLabel('任务时长（分钟）'),
                TextFormField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '默认 0（仅提醒，不占时段）',
                    suffixText: '分钟',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null) return '请输入有效分钟数';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const FieldLabel('响铃时长（秒）'),
                TextFormField(
                  controller: _ringCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '留空则使用全局默认',
                    suffixText: '秒',
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null; // 留空 = 用全局默认
                    final n = int.tryParse(s);
                    if (n == null || n <= 0) return '请输入有效秒数';
                    return null;
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isEdit && widget.task?.hasPendingConflict == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final store = context.read<TaskStore>();
                    await store.resolveOverride(widget.task!);
                    await widget.reminder.notifyTaskChanged(widget.task!);
                    if (mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('确认覆盖冲突并生效'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            FilledButton(
              onPressed: _save,
              child: Text(_isEdit ? '保存修改' : '创建提醒'),
            ),
            if (_repeat == RepeatType.custom && _customWeekdays.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '自定义重复需至少选择一个星期',
                  style: TextStyle(color: AppTheme.warn, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
