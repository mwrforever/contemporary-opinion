import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/task.dart';
import '../../prompts/prompt_loader.dart';
import '../../services/aliyun_asr_service.dart';
import '../../services/aliyun_schedule_service.dart';
import '../../services/conflict_detector.dart';
import '../../services/reminder_service.dart';
import '../../services/task_store.dart';
import '../../modules/notebook/widgets/notebook_shared.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in.dart';

/// 语音规划页：录音 → 转写 → 大模型解析排期 → 冲突检测 → 预览确认。
///
/// 由 `lib/screens/voice_input_screen.dart` 迁移至本模块，逻辑不变；任务提示词
/// 已拆分为「设定时间的任务」([PromptLoader.tasksScheduledId]) 与「延时任务」
/// ([PromptLoader.tasksDelayId]) 两份，由 [AliyunScheduleService] 按口语意图选用。
class VoiceInputScreen extends StatefulWidget {
  final TaskStore store;
  final ReminderService reminder;
  final AliyunAsrService asr;
  final AliyunScheduleService schedule;

  const VoiceInputScreen({
    super.key,
    required this.store,
    required this.reminder,
    required this.asr,
    required this.schedule,
  });

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  var _state = _VoiceState.idle;
  String _transcript = '';
  String _error = '';
  List<Task> _candidates = [];
  List<ConflictResult> _conflicts = [];
  final Set<int> _selected = {};
  bool _aborted = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _aborted = true;
    widget.asr.cancel();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_state == _VoiceState.listening) {
      widget.asr.stop();
      return;
    }
    setState(() {
      _state = _VoiceState.listening;
      _transcript = '';
      _error = '';
    });
    try {
      final text = await widget.asr.transcribe(
        onPartial: (t) => setState(() => _transcript = t),
      );
      if (_aborted || !mounted) return;
      _transcript = text;
      await _buildSchedule(text);
    } catch (e) {
      if (_aborted || !mounted) return;
      setState(() {
        _state = _VoiceState.error;
        _error = '语音识别失败：$e';
      });
    }
  }

  /// 用排期模型把转写文本转为结构化任务，并就地做冲突检测。
  Future<void> _buildSchedule(String text) async {
    final raw = text.trim();
    if (raw.isEmpty) {
      setState(() => _state = _VoiceState.empty);
      return;
    }
    // 取任务语音提示词（打包资源即视为已批准，无运行时审批态）。
    // 任务提示词已拆分为「设定时间的任务」与「延时任务」两份，任一可用即可进入解析。
    final prompt = PromptLoader.byId(PromptLoader.tasksScheduledId) ??
        PromptLoader.byId(PromptLoader.tasksDelayId);
    if (prompt == null) {
      setState(() {
        _state = _VoiceState.error;
        _error = '任务语音提示词未找到，无法调用云端模型。';
      });
      return;
    }

    setState(() => _state = _VoiceState.processing);
    final scheduled = await widget.schedule.schedule(
      raw,
      existing: widget.store.all,
    );

    final existing = widget.store.all;
    final candidates = <Task>[];
    final conflicts = <ConflictResult>[];
    for (final st in scheduled) {
      final task = st.toTask(
        id: const Uuid().v4(),
        notificationId: DateTime.now().microsecondsSinceEpoch % 2147483647,
        createdAt: DateTime.now(),
      );
      final result = ConflictDetector.detect(task, existing);
      ConflictDetector.applyDecision(task, result);
      candidates.add(task);
      conflicts.add(result);
    }

    setState(() {
      _candidates = candidates;
      _conflicts = conflicts;
      _selected.clear();
      for (var i = 0; i < candidates.length; i++) {
        _selected.add(i);
      }
      _state = candidates.isEmpty ? _VoiceState.empty : _VoiceState.preview;
    });
  }

  /// 重新计算某候选任务的冲突（改时间/换资源后）。
  void _recompute(int index) {
    final task = _candidates[index];
    final result = ConflictDetector.detect(task, widget.store.all);
    ConflictDetector.applyDecision(task, result);
    setState(() => _conflicts[index] = result);
  }

  Future<void> _confirm() async {
    final chosen = _selected.toList();
    if (chosen.isEmpty) return;
    for (final i in chosen) {
      final task = _candidates[i];
      // addWithConflictCheck 会再次检测并写回 conflictState/effective
      await widget.store.addWithConflictCheck(task);
      // 仅对已生效（无冲突）任务调度提醒；冲突待处理任务默认不生效
      if (task.effective) {
        await widget.reminder.notifyTaskChanged(task);
      }
    }
    if (mounted) {
      final conflictCount = _candidates.where((c) => !c.effective).length;
      // 成功反馈不再用屏内 SnackBar（pop 后即不可见），改为回传结果，
      // 由 TasksTab 用 TaskFeedbackCard 统一展示。
      Navigator.of(context).pop({
        'added': chosen.length,
        'conflict': conflictCount,
      });
    }
  }

  /// 用户「确认覆盖」：强制该冲突任务生效。
  void _override(int index) {
    final task = _candidates[index];
    ConflictDetector.confirmOverride(task);
    setState(() => _conflicts[index] = const ConflictResult());
  }

  /// 改时间：重选日期+时刻后重检冲突。
  Future<void> _changeTime(int index) async {
    final task = _candidates[index];
    final initial = task.scheduledTime ?? DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null) return;
    // ignore: use_build_context_synchronously
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      task.scheduledTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    _recompute(index);
  }

  /// 换资源：重填资源名后重检冲突。
  Future<void> _changeResource(int index) async {
    final task = _candidates[index];
    final ctrl = TextEditingController(text: task.resource ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更换资源'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '如 会议室A / 车 / 张经理'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => task.resource =
          ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
      _recompute(index);
    }
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '待安排';
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay
        ? DateFormat('今天 HH:mm').format(t)
        : DateFormat('MM/dd HH:mm').format(t);
  }

  String _repeatText(Task t) {
    switch (t.repeat) {
      case RepeatType.daily:
        return '每天';
      case RepeatType.weekly:
        return '每周';
      case RepeatType.weekdays:
        return '工作日';
      case RepeatType.custom:
        final names = ['一', '二', '三', '四', '五', '六', '日'];
        final s = t.customWeekdays.map((w) => names[w - 1]).join('');
        return '每周$s';
      case RepeatType.none:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('语音规划'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _Body(
                state: _state,
                transcript: _transcript,
                error: _error,
                candidates: _candidates,
                conflicts: _conflicts,
                selected: _selected,
                onToggle: (i) => setState(() {
                  if (_selected.contains(i)) {
                    _selected.remove(i);
                  } else {
                    _selected.add(i);
                  }
                }),
                onOverride: _override,
                onChangeTime: _changeTime,
                onChangeResource: _changeResource,
                formatTime: _formatTime,
                repeatText: _repeatText,
                onRerecord: () => setState(() {
                  _state = _VoiceState.idle;
                  _transcript = '';
                  _candidates = [];
                  _conflicts = [];
                  _selected.clear();
                }),
              ),
            ),
          ),
          _BottomBar(
            state: _state,
            listening: _state == _VoiceState.listening,
            onMic: _toggleRecording,
            onConfirm: _confirm,
            selectedCount: _selected.length,
            accent: scheme.primary,
          ),
        ],
      ),
    );
  }
}

enum _VoiceState { idle, listening, processing, preview, empty, error }

class _Body extends StatelessWidget {
  final _VoiceState state;
  final String transcript;
  final String error;
  final List<Task> candidates;
  final List<ConflictResult> conflicts;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onOverride;
  final ValueChanged<int> onChangeTime;
  final ValueChanged<int> onChangeResource;
  final String Function(DateTime?) formatTime;
  final String Function(Task) repeatText;
  final VoidCallback onRerecord;

  const _Body({
    required this.state,
    required this.transcript,
    required this.error,
    required this.candidates,
    required this.conflicts,
    required this.selected,
    required this.onToggle,
    required this.onOverride,
    required this.onChangeTime,
    required this.onChangeResource,
    required this.formatTime,
    required this.repeatText,
    required this.onRerecord,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _VoiceState.processing) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 40),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('正在用大模型解析排期…')),
        ],
      );
    }
    if (state == _VoiceState.error) {
      return _CenterHint(
        icon: Icons.error_outline,
        color: AppTheme.danger,
        text: error,
      );
    }
    if (state == _VoiceState.listening) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulsingDot(color: AppTheme.danger),
              const SizedBox(width: 10),
              Text('正在聆听…',
                  style: TextStyle(
                      color: AppTheme.danger, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            transcript.isEmpty
                ? '请说出你要做的事，例如"下午3点开会，30分钟后吃药"'
                : transcript,
            style: const TextStyle(fontSize: 18, height: 1.5),
          ),
        ],
      );
    }
    if (state == _VoiceState.empty) {
      return const _CenterHint(
        icon: Icons.search_off_outlined,
        text: '没听清具体安排，换个说法试试？',
      );
    }
    if (state == _VoiceState.preview) {
      final conflictCount = candidates.where((c) => !c.effective).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('原始内容',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5))),
          const SizedBox(height: 6),
          Text(transcript, style: const TextStyle(fontSize: 15, height: 1.5)),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('解析出 ${candidates.length} 项',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              if (conflictCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$conflictCount 项待处理·未生效',
                      style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
              const Spacer(),
              TextButton(onPressed: onRerecord, child: const Text('重新录制')),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < candidates.length; i++)
            FadeIn(
              delay: Duration(milliseconds: i * 50),
              child: _PreviewTile(
                task: candidates[i],
                conflict: conflicts[i],
                checked: selected.contains(i),
                onChanged: () => onToggle(i),
                timeText: formatTime(candidates[i].scheduledTime),
                repeatText: repeatText(candidates[i]),
                onOverride: () => onOverride(i),
                onChangeTime: () => onChangeTime(i),
                onChangeResource: () => onChangeResource(i),
              ),
            ),
        ],
      );
    }
    return const _CenterHint(
      icon: Icons.mic_outlined,
      text: '点击下方麦克风，说出今天的安排',
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final Task task;
  final ConflictResult conflict;
  final bool checked;
  final VoidCallback onChanged;
  final String timeText;
  final String repeatText;
  final VoidCallback onOverride;
  final VoidCallback onChangeTime;
  final VoidCallback onChangeResource;

  const _PreviewTile({
    required this.task,
    required this.conflict,
    required this.checked,
    required this.onChanged,
    required this.timeText,
    required this.repeatText,
    required this.onOverride,
    required this.onChangeTime,
    required this.onChangeResource,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUndated = task.conflictState == ConflictState.undated;
    final isConflict = !task.effective && !isUndated;
    final timeOnlyWarn = task.effective && conflict.hasTimeConflict;
    final borderColor = isConflict
        ? AppTheme.danger
        : (isUndated
            ? AppTheme.warn
            : (timeOnlyWarn
                ? AppTheme.warn.withValues(alpha: 0.5)
                : scheme.onSurface.withValues(alpha: 0.08)));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
      color: isConflict
          ? AppTheme.danger.withValues(alpha: 0.04)
          : (isUndated
              ? AppTheme.warn.withValues(alpha: 0.04)
              : scheme.surface),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
            color: borderColor, width: isConflict ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: checked,
            onChanged: (_) => onChanged(),
            title: Text(task.title,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: (isConflict || isUndated)
                        ? (isConflict ? AppTheme.danger : AppTheme.warn)
                        : scheme.onSurface)),
            subtitle: Row(
              children: [
                // 主时间：延时任务显示倒计时，设定任务显示绝对时刻
                if (task.countdownSeconds != null) ...[
                  Icon(Icons.timer_outlined,
                      size: 14, color: isConflict ? AppTheme.danger : AppTheme.warn),
                  const SizedBox(width: 4),
                  Text('${task.countdownSeconds}秒后提醒',
                      style: TextStyle(
                          color: isConflict ? AppTheme.danger : AppTheme.warn,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ] else ...[
                  Icon(Icons.schedule_outlined,
                      size: 14,
                      color: isConflict
                          ? AppTheme.danger
                          : (isUndated ? AppTheme.warn : scheme.primary)),
                  const SizedBox(width: 4),
                  Text(timeText,
                      style: TextStyle(
                          color: isConflict
                              ? AppTheme.danger
                              : (isUndated ? AppTheme.warn : scheme.primary),
                          fontSize: 13)),
                ],
                if (repeatText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(repeatText,
                      style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 13)),
                ],
                if (task.resource != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(task.resource!,
                        style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 11)),
                  ),
                ],
                // 任务时长：默认 0（仅提醒）时不展示，避免噪声
                if (task.durationMinutes > 0) ...[
                  const SizedBox(width: 8),
                  NotebookChip(
                    label: '${task.durationMinutes}分钟',
                    bg: AppTheme.accentSoft,
                    fg: AppTheme.accent,
                  ),
                ],
                if (task.ringSeconds != null) ...[
                  const SizedBox(width: 8),
                  NotebookChip(
                    label: '响铃${task.ringSeconds}秒',
                    bg: AppTheme.accentSoft,
                    fg: AppTheme.accent,
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  '创建 ${DateFormat('MM/dd HH:mm').format(task.createdAt)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius)),
          ),
          if (isConflict) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 15, color: AppTheme.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(conflict.summarize(),
                            style: TextStyle(
                                color: AppTheme.danger, fontSize: 12.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onOverride,
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('确认覆盖'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: BorderSide(
                              color: AppTheme.danger.withValues(alpha: 0.5)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: onChangeTime,
                        icon: const Icon(Icons.schedule, size: 16),
                        label: const Text('改时间'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onChangeResource,
                        icon: const Icon(Icons.inventory_2_outlined, size: 16),
                        label: const Text('换资源'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (isUndated) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.schedule_outlined, size: 15, color: AppTheme.warn),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '时间待定 · 未生效，设置时间后才会提醒',
                      style: TextStyle(color: AppTheme.warn, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: onChangeTime,
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('改时间'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.warn,
                      side: BorderSide(color: AppTheme.warn.withValues(alpha: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (timeOnlyWarn) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: AppTheme.warn),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '时间与其他任务重叠，但资源不冲突，已正常生效',
                        style: TextStyle(
                            color: AppTheme.warn, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CenterHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _CenterHint({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color ?? scheme.onSurface.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, color: scheme.onSurface.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);
  late final Animation<double> _a =
      Tween(begin: 0.3, end: 1.0).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  final _VoiceState state;
  final bool listening;
  final VoidCallback onMic;
  final VoidCallback onConfirm;
  final int selectedCount;
  final Color accent;

  const _BottomBar({
    required this.state,
    required this.listening,
    required this.onMic,
    required this.onConfirm,
    required this.selectedCount,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.06)),
        ),
      ),
      child: state == _VoiceState.preview
          ? FilledButton.icon(
              onPressed: selectedCount > 0 ? onConfirm : null,
              icon: const Icon(Icons.check),
              label: Text('确认添加（$selectedCount）'),
            )
          : state == _VoiceState.processing
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onMic,
                        icon: Icon(listening ? Icons.stop : Icons.mic),
                        label: Text(listening ? '停止并解析' : '开始说话'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
