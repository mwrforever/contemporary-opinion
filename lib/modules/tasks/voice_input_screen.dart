import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../config/aliyun_config.dart';
import '../../models/task.dart';
import '../../services/aliyun_asr_service.dart';
import '../../services/aliyun_schedule_service.dart';
import '../../services/conflict_detector.dart';
import '../../services/nlp_parser.dart';
import '../../services/reminder_service.dart';
import '../../services/task_store.dart';
import '../../services/voice_task_adapter.dart';
import '../../theme/app_theme.dart';

/// 语音规划结果（供任务列表反馈卡使用）。
class VoicePlanResult {
  const VoicePlanResult({
    required this.added,
    required this.conflict,
    required this.skipped,
  });

  final int added;
  final int conflict;
  final int skipped;
}

/// 语音规划页：录音（云端）或文本输入（离线）→ 排期解析 → 逐条冲突检测 →
/// 四态预览 → 确认添加。
///
/// 离线（无云端 Key）：App 不做录音/ASR，用户手写或经系统输入法语音转文字
/// 写入文本框，走本地 [NlpParser]。冲突处理（改时间/换资源/设时间）为手动编辑对话框，
/// 非语音操作。
class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({
    super.key,
    required this.store,
    required this.reminder,
    this.asr,
    this.schedule,
    this.cloudEnabled,
    this.requestMicPermission,
  });

  final TaskStore store;
  final ReminderService reminder;
  final AliyunAsrService? asr;
  final AliyunScheduleService? schedule;

  /// 云端开关（测试注入）；默认取 AliyunConfig 是否配置 Key
  final bool? cloudEnabled;

  /// 麦克风权限请求（测试注入）；默认走 permission_handler
  final Future<bool> Function()? requestMicPermission;

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

enum _Phase { idle, recording, parsing, preview }

/// 预览条目：任务 + 冲突结果 + 是否勾选添加
class _PlanItem {
  _PlanItem({required this.task, required this.result})
      : selected = true {
    // 已过去任务默认跳过不添加
    if (isPast) selected = false;
  }

  final Task task;
  ConflictResult result;
  bool selected;

  bool get isPast =>
      task.scheduledTime != null &&
      task.scheduledTime!.isBefore(DateTime.now());

  bool get isConflict => task.hasPendingConflict;
  bool get isUndated => task.conflictState == ConflictState.undated;
  bool get isWeakOverlap => result.hasTimeConflict && !result.hasResourceConflict;
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  final _textController = TextEditingController();
  late final AliyunAsrService _asr =
      widget.asr ?? AliyunAsrService(apiKey: AliyunConfig.dashscopeApiKey);
  late final AliyunScheduleService _schedule = widget.schedule ??
      AliyunScheduleService(apiKey: AliyunConfig.dashscopeApiKey);
  late final Future<bool> Function() _requestMic =
      widget.requestMicPermission ?? _defaultMicPermission;

  _Phase _phase = _Phase.idle;
  String _transcript = '';
  bool _recording = false;
  List<_PlanItem> _items = [];
  final _baseId = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000;

  bool get _cloudEnabled =>
      widget.cloudEnabled ?? AliyunConfig.dashscopeApiKey.isNotEmpty;

  static Future<bool> _defaultMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int _notificationId(int index) => _baseId + index;

  /// 录音识别：ASR 内部负责录音采集，页面只负责启动/停止
  Future<void> _startRecording() async {
    final granted = await _requestMic();
    if (!granted || !mounted) {
      _toast('需要麦克风权限才能语音规划');
      return;
    }
    setState(() => _phase = _Phase.recording);
    try {
      final text = await _asr.transcribe(onPartial: (t) {
        if (mounted) setState(() => _transcript = t);
      });
      if (!mounted) return;
      _transcript = text;
      setState(() => _phase = _Phase.idle);
      _textController.text = text;
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      _toast('识别失败，请重试或手动输入');
    }
  }

  void _stopRecording() {
    _asr.stop();
  }

  Future<void> _parse() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _toast('请先说或输入要规划的内容');
      return;
    }
    setState(() => _phase = _Phase.parsing);
    final now = DateTime.now();
    List<Task> tasks;
    try {
      final scheduled = await _schedule.schedule(
        text,
        existing: widget.store.all,
        now: now,
      );
      tasks = scheduled.isEmpty
          ? [
              for (final p in NlpParser.parse(text, now: now))
                taskFromParsed(
                  p,
                  id: const Uuid().v4(),
                  notificationId: _notificationId(0),
                  now: now,
                ),
            ]
          : [
              for (var i = 0; i < scheduled.length; i++)
                taskFromScheduled(
                  scheduled[i],
                  id: const Uuid().v4(),
                  notificationId: _notificationId(i),
                  now: now,
                ),
            ];
    } catch (_) {
      // 云端失败 → 本地 NLP 兜底
      tasks = [
        for (final p in NlpParser.parse(text, now: now))
          taskFromParsed(
            p,
            id: const Uuid().v4(),
            notificationId: _notificationId(0),
            now: now,
          ),
      ];
    }

    if (!mounted) return;
    _items = [
      for (final t in tasks)
        _PlanItem(
          task: t,
          result: _detectAndApply(t, now),
        ),
    ];
    setState(() => _phase = _Phase.preview);
  }

  /// 冲突检测并写回候选任务状态（四态判定依据）
  ConflictResult _detectAndApply(Task task, DateTime now) {
    final result =
        ConflictDetector.detect(task, widget.store.all, referenceNow: now);
    ConflictDetector.applyDecision(task, result);
    return result;
  }

  /// 确认覆盖：预览内强制生效
  void _confirmOverride(_PlanItem item) {
    ConflictDetector.confirmOverride(item.task);
    setState(() {});
  }

  /// 改时间/换资源/设时间：手动编辑对话框（非语音操作）
  Future<void> _editItem(_PlanItem item) async {
    final edited = await showDialog<(DateTime, String?)>(
      context: context,
      builder: (ctx) => _EditTaskDialog(task: item.task),
    );
    if (edited == null || !mounted) return;
    item.task.scheduledTime = edited.$1;
    item.task.resource = edited.$2;
    item.task.conflictState = ConflictState.none;
    item.task.effective = true;
    item.result = _detectAndApply(item.task, DateTime.now());
    setState(() {});
  }

  Future<void> _confirm() async {
    var added = 0;
    var conflict = 0;
    var skipped = 0;
    for (final item in _items) {
      if (item.isPast || !item.selected) {
        skipped++;
        continue;
      }
      await widget.store.addWithConflictCheck(item.task);
      await widget.reminder.notifyTaskChanged(item.task);
      added++;
      if (item.task.hasPendingConflict) conflict++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      VoicePlanResult(added: added, conflict: conflict, skipped: skipped),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语音规划')),
      body: switch (_phase) {
        _Phase.preview => _buildPreview(),
        _Phase.recording || _Phase.parsing => _buildWorking(),
        _Phase.idle => _buildInput(),
      },
    );
  }

  /// 输入区：云端显示录音按钮，离线显示文本框
  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_cloudEnabled) ...[
            Center(
              child: IconButton.filled(
                iconSize: 40,
                padding: const EdgeInsets.all(24),
                icon: const Icon(Icons.mic),
                onPressed: _startRecording,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '点击麦克风，说一句口语规划',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '规划内容',
              hintText: '如：明早9点用会议室A开会两小时，半小时后提醒我吃药',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _parse,
              child: const Text('解析'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorking() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _phase == _Phase.recording ? '识别中…（点击下方停止）' : '正在解析排期…',
            style: const TextStyle(fontSize: 14),
          ),
          if (_phase == _Phase.recording) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: _stopRecording,
              child: const Text('停止'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final addedCount =
        _items.where((i) => !i.isPast && i.selected).length;
    final skippedCount = _items.where((i) => i.isPast || !i.selected).length;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _items.length,
            itemBuilder: (context, i) => _PreviewCard(
              item: _items[i],
              onToggle: () => setState(() => _items[i].selected = !_items[i].selected),
              onConfirmOverride: () => _confirmOverride(_items[i]),
              onEdit: () => _editItem(_items[i]),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Text(
                  '将添加 $addedCount 条 · 跳过 $skippedCount 条',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _confirm,
                    child: const Text('确认添加'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 四态预览卡
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.item,
    required this.onToggle,
    required this.onConfirmOverride,
    required this.onEdit,
  });

  final _PlanItem item;
  final VoidCallback onToggle;
  final VoidCallback onConfirmOverride;
  final VoidCallback onEdit;

  String get _timeText {
    final t = item.task.scheduledTime;
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final task = item.task;

    Color? border;
    Color? bg;
    String? tag;
    Color? tagColor;
    String? hint;
    if (item.isConflict) {
      border = AppTheme.danger;
      bg = AppTheme.dangerSoft;
      tag = '冲突待处理';
      tagColor = AppTheme.danger;
    } else if (item.isUndated) {
      border = AppTheme.warn;
      bg = AppTheme.warnSoft;
      tag = '时间待定';
      tagColor = AppTheme.warn;
    } else if (item.isPast) {
      border = AppTheme.danger;
      bg = AppTheme.dangerSoft;
      tag = '已过去';
      tagColor = AppTheme.danger;
    } else if (item.isWeakOverlap) {
      hint = '与既有任务仅时间重叠，正常生效';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg ?? scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: border ?? scheme.outlineVariant,
          width: border != null ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!item.isPast)
            GestureDetector(
              key: ValueKey('plan-check-${task.id}'),
              onTap: onToggle,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: item.selected ? scheme.primary : scheme.outline,
                  ),
                ),
                child: item.selected
                    ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                    : null,
              ),
            ),
          if (!item.isPast) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (tag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tagColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                if (task.scheduledTime != null || task.resource != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 10,
                      children: [
                        if (task.scheduledTime != null)
                          Text(
                            _timeText,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: item.isPast
                                  ? AppTheme.danger
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        if (task.resource != null)
                          Text(
                            task.resource!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.warn,
                      ),
                    ),
                  ),
                if (item.isPast)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '已过期，将跳过不添加',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                if (item.isConflict || item.isUndated) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (item.isConflict) ...[
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: onConfirmOverride,
                          child: const Text(
                            '确认覆盖',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      TextButton(
                        onPressed: onEdit,
                        child: Text(
                          item.isConflict ? '改时间/换资源' : '设时间',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 手动编辑对话框：改时间/换资源/设时间（非语音操作）
class _EditTaskDialog extends StatefulWidget {
  const _EditTaskDialog({required this.task});

  final Task task;

  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  late DateTime _date = widget.task.scheduledTime ?? DateTime.now();
  late TimeOfDay _time =
      widget.task.scheduledTime == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(widget.task.scheduledTime!);
  late final TextEditingController _resource =
      TextEditingController(text: widget.task.resource ?? '');

  @override
  void dispose() {
    _resource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    return AlertDialog(
      title: Text(widget.task.scheduledTime == null ? '设时间' : '改时间/换资源'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('日期'),
            trailing: Text(
              '${_date.year}-${two(_date.month)}-${two(_date.day)}',
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            title: const Text('时间'),
            trailing: Text('${two(_time.hour)}:${two(_time.minute)}'),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
          ),
          TextField(
            controller: _resource,
            decoration: const InputDecoration(labelText: '资源（可选）'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
            _resource.text.trim().isEmpty ? null : _resource.text.trim(),
          )),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
