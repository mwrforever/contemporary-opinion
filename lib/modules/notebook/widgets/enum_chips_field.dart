import 'dart:math';

import 'package:flutter/material.dart';

/// 枚举 chip 折叠组件：子项多时最多展示 [maxRows] 行，其余折叠可展开。
///
/// 折叠态用固定高度裁剪 + 底部渐隐 + 「展开全部（N）」按钮；展开态展示全部
/// 并显示「收起」。依赖 [countChipsInRows] 纯函数计算可见数量。
class EnumChipsField extends StatefulWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;
  final int maxRows;

  const EnumChipsField({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.maxRows = 2,
  });

  @override
  State<EnumChipsField> createState() => _EnumChipsFieldState();
}

class _EnumChipsFieldState extends State<EnumChipsField> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final visibleCount = countChipsInRows(
        labels: widget.values,
        maxRows: widget.maxRows,
        maxWidth: constraints.maxWidth,
        style: style,
      );
      final showToggle = visibleCount < widget.values.length;
      final shown =
          _expanded ? widget.values : widget.values.take(visibleCount).toList();
      const rowHeight = 38.0; // chip 高（padding 9*2 + 行高 20）
      const gap = 8.0;
      final chips = [
        for (final v in shown)
          _chip(v, style, scheme, () => widget.onChanged(v)),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              if (_expanded)
                Wrap(spacing: gap, runSpacing: gap, children: chips)
              else
                SizedBox(
                  height: rowHeight * widget.maxRows +
                      gap * (widget.maxRows - 1),
                  child: ClipRect(
                    child: OverflowBox(
                      maxHeight: double.infinity,
                      alignment: Alignment.topCenter,
                      child:
                          Wrap(spacing: gap, runSpacing: gap, children: chips),
                    ),
                  ),
                ),
              if (!_expanded)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 26,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.surface.withValues(alpha: 0),
                            scheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (showToggle)
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(
                _expanded
                    ? '收起'
                    : '展开全部（${widget.values.length - visibleCount}）',
              ),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: const Size(0, 40),
              ),
            ),
        ],
      );
    });
  }

  Widget _chip(
      String label, TextStyle style, ColorScheme scheme, VoidCallback onTap) {
    final active = label == widget.selected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: style.copyWith(
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 模拟换行：返回前 [maxRows] 行能容纳的 chip 数量。
///
/// chip 宽度 = 文本宽度 + 左右 padding；行内间距 [gap]。放不下即换行，
/// 换行数达到 [maxRows] 后停止计数（后续视为被折叠）。
int countChipsInRows({
  required List<String> labels,
  required int maxRows,
  required double maxWidth,
  required TextStyle style,
  double horizontalPadding = 14,
  double gap = 8,
}) {
  if (labels.isEmpty || maxRows <= 0) return 0;
  var rows = 1;
  var count = 0;
  var lineWidth = 0.0;
  for (final label in labels) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + horizontalPadding * 2;
    if (lineWidth > 0 && lineWidth + gap + w > maxWidth) {
      rows++;
      if (rows > maxRows) break;
      lineWidth = 0;
    }
    lineWidth += (lineWidth == 0 ? 0 : gap) + w;
    count++;
  }
  return min(count, labels.length);
}
