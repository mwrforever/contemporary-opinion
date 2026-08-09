import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/aliyun_asr_service.dart';
import '../../../theme/app_theme.dart';

/// 记事本共享组件（依据 UI UX Pro Max + Taste Skill V1）：
/// 发丝边框 + 扩散阴影的卡片层次、标签在上输入在下、单一强调色、完整空/错/加载态。

/// 空状态：图标 + 主文案 + 副文案。
class NotebookEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const NotebookEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppTheme.accent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 标签在上、输入在下的表单字段（Taste V1：labels-above-inputs）。
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

/// 交互式星级评分（0–5）。
class StarsRow extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  const StarsRow({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final active = i < value;
        return GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: active
                  ? AppTheme.warn
                  : scheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        );
      }),
    );
  }
}

/// 语义小标签（发丝边框 + 柔和底色）。
class NotebookChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const NotebookChip({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 语义徽标：按 [tone] 返回浅底深字的小标签。
///
/// tone 取值：ok（成功/已完成/收入）、warn（进行中/提醒/支出）、danger
/// （困难/删除）、其余归 neutral（待定/未开始/未知）。深色模式自动切换
/// 到 AppTheme 深色变体，保证对比度。
NotebookChip semanticChip(
  BuildContext context, {
  required String label,
  required String tone,
}) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final (bg, fg) = switch (tone) {
    'ok' => (AppTheme.okSoft, isDark ? AppTheme.okDark : AppTheme.ok),
    'warn' => (AppTheme.warnSoft, isDark ? AppTheme.warnDark : AppTheme.warn),
    'danger' => (
        AppTheme.dangerSoft,
        isDark ? AppTheme.dangerDark : AppTheme.danger
      ),
    _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
  };
  return NotebookChip(label: label, bg: bg, fg: fg);
}

/// 日期选择字段：点击唤起原生 [showDatePicker]，回填 `yyyy-MM-dd` 字符串。
///
/// 取代手动输入文本，统一日期格式（复用 [add_task_screen] 的 `firstDate` /
/// `lastDate` 区间与 [AppTheme] 输入框风格）。[value] 为当前显示值（空亦可），
/// 选中后通过 [onChanged] 回传格式化字符串。
class DateField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.value;
  }

  @override
  void didUpdateWidget(covariant DateField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ctrl.text = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  DateTime? _parse(String s) {
    try {
      return DateFormat('yyyy-MM-dd').parse(s);
    } on FormatException {
      return null;
    }
  }

  Future<void> _pick() async {
    final initial = _parse(widget.value) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      _ctrl.text = formatted;
      widget.onChanged(formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          readOnly: true,
          onTap: _pick,
          decoration: const InputDecoration(
            hintText: 'yyyy-MM-dd',
            suffixIcon: Icon(Icons.calendar_today_outlined),
          ),
        ),
      ],
    );
  }
}

/// 通用语音录入底部弹层：录音 → 转写 → 解析 → 勾选预览 → 确认保存。
///
/// 泛型 [T] 为各子功能草稿条目类型；预览渲染与保存回调由调用方提供。
class NotebookVoiceSheet<T> extends StatefulWidget {
  final AliyunAsrService asr;
  final Future<List<T>> Function(String) parse;
  final Widget Function(T) itemBuilder;
  final void Function(List<T>) onConfirmed;
  final String title;
  final String hint;

  const NotebookVoiceSheet({
    super.key,
    required this.asr,
    required this.parse,
    required this.itemBuilder,
    required this.onConfirmed,
    required this.title,
    this.hint = '点击话筒，说出你要记录的内容',
  });

  @override
  State<NotebookVoiceSheet<T>> createState() => _NotebookVoiceSheetState<T>();
}

class _NotebookVoiceSheetState<T> extends State<NotebookVoiceSheet<T>> {
  bool _listening = false;
  bool _parsing = false;
  String _partial = '';
  String? _error;
  List<T> _draft = [];
  List<bool> _checked = [];
  bool _aborted = false;

  Future<void> _start() async {
    setState(() {
      _listening = true;
      _partial = '';
      _error = null;
      _draft = [];
      _checked = [];
    });
    try {
      final text = await widget.asr.transcribe(
        onPartial: (t) => setState(() => _partial = t),
      );
      if (_aborted || !mounted) return;
      setState(() {
        _listening = false;
        _parsing = true;
      });
      final items = await widget.parse(text);
      if (_aborted || !mounted) return;
      setState(() {
        _parsing = false;
        _draft = items;
        _checked = List.filled(items.length, true);
        if (items.isEmpty) _error = '没听清，换个说法或手动录入。';
      });
    } catch (e) {
      if (_aborted || !mounted) return;
      setState(() {
        _listening = false;
        _parsing = false;
        _error = '语音识别失败：$e';
      });
    }
  }

  @override
  void dispose() {
    _aborted = true;
    widget.asr.cancel();
    super.dispose();
  }

  void _confirm() {
    final confirmed = <T>[];
    for (var i = 0; i < _draft.length; i++) {
      if (_checked[i]) confirmed.add(_draft[i]);
    }
    widget.onConfirmed(confirmed);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          top: AppTheme.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    if (_listening) widget.asr.cancel();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 录音按钮（录音中点击 = 停止并解析）
            Center(
              child: GestureDetector(
                onTap: _parsing
                    ? null
                    : (_listening ? () => widget.asr.stop() : _start),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _listening ? AppTheme.accentStrong : AppTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.elevation(
                        scheme.brightness == Brightness.dark),
                  ),
                  child: _parsing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Icon(
                          _listening ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 38,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_listening)
              Text('聆听中…点击话筒停止并解析',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: AppTheme.accent)),
            if (_partial.isNotEmpty && !_listening)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                      color: scheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Text(_partial,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.danger)),
              ),
            if (_draft.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('识别到 ${_draft.length} 条，勾选要保存的：',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _draft.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => InkWell(
                  onTap: () => setState(() => _checked[i] = !_checked[i]),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: _checked[i]
                            ? AppTheme.accent.withValues(alpha: 0.5)
                            : scheme.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _checked[i]
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: _checked[i]
                              ? AppTheme.accent
                              : scheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: widget.itemBuilder(_draft[i])),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _confirm,
                child: Text('保存 ${_checked.where((c) => c).length} 条'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 打开通用语音录入弹层。
Future<void> showNotebookVoiceSheet<T>(
  BuildContext context,
  NotebookVoiceSheet<T> sheet,
) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => sheet,
    );

/// 打开记事本编辑抽屉统一外壳。
///
/// 统一 24 圆角、表面底色、安全区与键盘避让，内容单列滚动；标题行与关闭
/// 按钮由本方法渲染，字段与底部操作按钮由 [builder] 提供。局部状态更新
/// 通过 [StateSetter] 触发，与 `showModalBottomSheet` 的 StatefulBuilder 一致。
Future<void> showNotebookEditSheet(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext sheetContext, StateSetter setSheetState)
      builder,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...builder(ctx, setSheetState),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 新增 id（进程内唯一）。
String notebookNewId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${(_counter++).toString()}';
int _counter = 0;

/// 金额展示：¥ + 两位小数（购物/报表共用）。
String formatYuan(num v) => '¥${v.toStringAsFixed(2)}';

/// 金额展示（千分位）：如 ¥1,286.40（汇总卡/报表结余卡使用）。
String formatYuanThousands(num v) {
  final fixed = v.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final intPart = fixed.substring(0, dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '¥$buf${fixed.substring(dot)}';
}
