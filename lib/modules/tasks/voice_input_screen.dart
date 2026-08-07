import 'dart:async';
import 'dart:math' as math;

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

/// 语音规划浮层（V2）：同页底部弹出，不跳转新页面。
///
/// 冒烟整改口径：
/// - 可先打字，录音转写内容**追加到光标处**，不覆盖已输入内容；
/// - 录音不跳页：在浮层内完成；停止键为单层环 + 红方块；
/// - 排期结果同浮层展示：冲突条目红色标记，点条目可改时间/换资源；
/// - 逐条保存，单条失败不中断其余任务（修复「多任务只保存一个」）。
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

class _VoiceInputScreenState extends State<VoiceInputScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  late final AliyunAsrService _asr =
      widget.asr ?? AliyunAsrService(apiKey: AliyunConfig.dashscopeApiKey);
  late final AliyunScheduleService _schedule = widget.schedule ??
      AliyunScheduleService(apiKey: AliyunConfig.dashscopeApiKey);
  late final Future<bool> Function() _requestMic =
      widget.requestMicPermission ?? _defaultMicPermission;

  late final AnimationController _wave;

  _Phase _phase = _Phase.idle;
  List<_PlanItem> _items = [];
  final _baseId = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000;

  /// 录音插入锚点：开始录音时的光标位置
  int _insertOffset = 0;

  /// 当前录音转写片段（用于替换更新，实现追加在光标处）
  String _pending = '';

  static Future<bool> _defaultMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  void dispose() {
    _wave.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 立即创建（不能惰性初始化：dispose 阶段首次访问会触发崩溃）；
    // 仅在录音期间循环，避免空闲态持续调度帧导致界面/测试无法收敛
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  int _notificationId(int index) => _baseId + index;

  /// 录音识别：ASR 内部负责录音采集，页面只负责启动/停止；
  /// 转写片段实时插入光标处（不覆盖已有文字）。
  Future<void> _startRecording() async {
    final granted = await _requestMic();
    if (!granted || !mounted) {
      _toast('需要麦克风权限才能语音规划');
      return;
    }
    setState(() {
      _phase = _Phase.recording;
      _insertOffset = _textController.selection.isValid
          ? _textController.selection.baseOffset
          : _textController.text.length;
      _pending = '';
    });
    _wave.repeat();
    try {
      final text = await _asr.transcribe(onPartial: (t) {
        if (!mounted) return;
        setState(() => _applyPartial(t));
      });
      if (!mounted) return;
      setState(() {
        _applyPartial(text);
        _pending = '';
        _phase = _Phase.idle;
      });
      _stopWave();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pending = '';
        _phase = _Phase.idle;
      });
      _stopWave();
      _toast('识别失败，请重试或手动输入');
    }
  }

  /// 停止音波动画并复位（录音结束调用）。
  void _stopWave() {
    _wave.stop();
    _wave.value = 0;
  }

  /// 把转写文本 [text] 替换到光标锚点处的当前片段（追加语义）。
  void _applyPartial(String text) {
    final c = _textController;
    final base = _insertOffset.clamp(0, c.text.length);
    final end = (base + _pending.length).clamp(0, c.text.length);
    c.text = c.text.replaceRange(base, end, text);
    _pending = text;
    c.selection = TextSelection.collapsed(offset: base + text.length);
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

  /// 确认添加：逐条入库，单条异常不中断其余（修复多任务只保存一个）。
  Future<void> _confirm() async {
    var added = 0;
    var conflict = 0;
    var skipped = 0;
    for (final item in _items) {
      if (item.isPast || !item.selected) {
        skipped++;
        continue;
      }
      try {
        await widget.store.addWithConflictCheck(item.task);
        await widget.reminder.notifyTaskChanged(item.task);
        added++;
        if (item.task.hasPendingConflict) conflict++;
      } catch (_) {
        // 单条保存失败跳过，不中断后续任务
      }
    }
    if (!mounted) return;
    _stopWave();
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: switch (_phase) {
            _Phase.preview => _buildPreview(scheme),
            _Phase.recording || _Phase.parsing => _buildWorking(scheme),
            _Phase.idle => _buildInput(scheme),
          },
        ),
      ),
    );
  }

  Widget _sheetHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        if (trailing != null) trailing,
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// 输入区：可打字 + 录音追加到光标处
  Widget _buildInput(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader('语音规划'),
        TextField(
          controller: _textController,
          maxLines: 3,
          minLines: 2,
          decoration: InputDecoration(
            hintText: '输入或直接录音，录音内容将插入光标处…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.mic_none, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '点一下麦克风，说一句口语规划（同页录音，不跳转）',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              Icon(Icons.hearing_outlined,
                  size: 44, color: scheme.outlineVariant),
              const SizedBox(height: 14),
              GestureDetector(
                key: const ValueKey('voice-start'),
                onTap: _startRecording,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.42),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(Icons.mic, size: 38, color: scheme.onPrimary),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '轻触开始录音',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _parse,
                child: const Text('解析当前内容'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 录音中 / 解析中
  Widget _buildWorking(ColorScheme scheme) {
    final recording = _phase == _Phase.recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader(
          '语音规划',
          trailing: recording
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warnSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '识别中…',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.warn,
                    ),
                  ),
                )
              : null,
        ),
        TextField(
          controller: _textController,
          maxLines: 3,
          minLines: 2,
          enabled: false,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: recording
              ? Column(
                  children: [
                    _EarWaves(animation: _wave, color: scheme.primary),
                    const SizedBox(height: 12),
                    // 停止键：单层环 + 红方块（无双层环）
                    GestureDetector(
                      key: const ValueKey('voice-stop'),
                      onTap: _stopRecording,
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.primary, width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x29101315),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '正在聆听… 点击红色方块停止',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(),
                ),
        ),
      ],
    );
  }

  /// 排期结果预览：冲突条目红色标记，点条目改时间/换资源
  Widget _buildPreview(ColorScheme scheme) {
    final addedCount = _items.where((i) => !i.isPast && i.selected).length;
    final skippedCount = _items.where((i) => i.isPast || !i.selected).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader('排期结果'),
        Text(
          '识别出 ${_items.length} 条 · 已检查冲突',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.42,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++)
                  _PreviewCard(
                    item: _items[i],
                    onToggle: () =>
                        setState(() => _items[i].selected = !_items[i].selected),
                    onConfirmOverride: () => _confirmOverride(_items[i]),
                    onEdit: () => _editItem(_items[i]),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '将添加 $addedCount 条 · 跳过 $skippedCount 条',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(onPressed: _confirm, child: const Text('确认添加')),
        ),
      ],
    );
  }
}

/// 耳朵 + 音波动效（从两侧汇入耳朵，振幅随时间变化）。
class _EarWaves extends StatelessWidget {
  const _EarWaves({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 66,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 左侧音波：3 条弧线从左侧汇入
              for (var i = 0; i < 3; i++)
                Positioned(
                  right: 58,
                  top: 14 + i * 4,
                  child: _arc(
                    left: true,
                    opacity: (math.sin((t * math.pi * 2) - i * 0.7) + 1) / 2,
                    dx: -10 * math.sin(t * math.pi * 2 - i),
                    height: 20 + i * 9,
                  ),
                ),
              // 右侧音波：3 条弧线从右侧汇入
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: 58,
                  top: 16 + i * 4,
                  child: _arc(
                    left: false,
                    opacity: (math.sin((t * math.pi * 2) + 0.4 - i * 0.7) + 1) / 2,
                    dx: 10 * math.sin(t * math.pi * 2 - i),
                    height: 22 + i * 9,
                  ),
                ),
              Icon(Icons.hearing_outlined, size: 44, color: color),
            ],
          );
        },
      ),
    );
  }

  Widget _arc({
    required bool left,
    required double opacity,
    required double dx,
    required double height,
  }) {
    return Transform.translate(
      offset: Offset(dx.toDouble(), 0),
      child: Opacity(
        opacity: opacity.clamp(0.1, 1.0),
        child: Container(
          width: 58,
          height: height,
          decoration: BoxDecoration(
            border: Border(
              left: left ? BorderSide(color: color, width: 2.5) : BorderSide.none,
              right: left ? BorderSide.none : BorderSide(color: color, width: 2.5),
            ),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

/// 预览卡：冲突/待定/已过去标记 + 操作
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg ?? scheme.surface,
        borderRadius: BorderRadius.circular(16),
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
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: item.selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: item.selected ? scheme.primary : scheme.outline,
                  ),
                ),
                child: item.selected
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
            ),
          if (!item.isPast) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
                    padding: const EdgeInsets.only(top: 5),
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
                    padding: const EdgeInsets.only(top: 5),
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
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '已过期，将跳过不添加',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                if (item.isConflict || item.isUndated) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.isConflict) ...[
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: onConfirmOverride,
                          child: const Text(
                            '确认覆盖',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      TextButton(
                        onPressed: onEdit,
                        child: Text(
                          item.isConflict ? '改时间/换资源' : '设时间',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: item.isConflict
                                ? AppTheme.danger
                                : scheme.primary,
                          ),
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
