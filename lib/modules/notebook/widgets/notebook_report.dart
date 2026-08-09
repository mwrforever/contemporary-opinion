import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../widgets/notebook_shared.dart';

/// 报表粒度。
enum ReportGranularity {
  day,
  month,
  year,
}

/// 报表输入原子。
///
/// - 购物：传 [date] + [value]（实付/预期价），[kind] 留 null（主序列）。
/// - 账本：传 [date] + [value]（金额）+ [kind] = 'income' | 'expense'（双序列堆叠）。
class ReportDatum {
  final String date; // yyyy-MM-dd；为空在聚合时视为今日
  final num value;
  final String? kind; // null=购物主序列；'income'/'expense'=账本

  const ReportDatum({required this.date, required this.value, this.kind});
}

/// 单根柱桶（恒 6 个）：主序列 [value]/[color]，账本可选副序列
/// [secondaryValue]/[secondaryColor]（收入/支出堆叠）。
class StatsBucket {
  final String label;
  final num value;
  final Color color;
  final num? secondaryValue;
  final Color? secondaryColor;

  const StatsBucket({
    required this.label,
    required this.value,
    required this.color,
    this.secondaryValue,
    this.secondaryColor,
  });
}

/// 周期起点（按粒度截断到 日/月/年 起点）。
DateTime _periodStart(DateTime d, ReportGranularity g) {
  switch (g) {
    case ReportGranularity.day:
      return DateTime(d.year, d.month, d.day);
    case ReportGranularity.month:
      return DateTime(d.year, d.month, 1);
    case ReportGranularity.year:
      return DateTime(d.year, 1, 1);
  }
}

/// 按粒度平移 [delta] 个周期（Dart 自动处理月/年进位溢出）。
DateTime _shiftPeriod(DateTime d, ReportGranularity g, int delta) {
  switch (g) {
    case ReportGranularity.day:
      return DateTime(d.year, d.month, d.day + delta);
    case ReportGranularity.month:
      return DateTime(d.year, d.month + delta, 1);
    case ReportGranularity.year:
      return DateTime(d.year + delta, 1, 1);
  }
}

/// 周期 key：day→yyyy-MM-dd / month→yyyy-MM / year→yyyy。
String _periodKey(DateTime d, ReportGranularity g) {
  switch (g) {
    case ReportGranularity.day:
      return DateFormat('yyyy-MM-dd').format(d);
    case ReportGranularity.month:
      return DateFormat('yyyy-MM').format(d);
    case ReportGranularity.year:
      return DateFormat('yyyy').format(d);
  }
}

/// 轴标签：day→M/d / month→M月 / year→yyyy。
String _periodLabel(DateTime d, ReportGranularity g) {
  switch (g) {
    case ReportGranularity.day:
      return DateFormat('M/d').format(d);
    case ReportGranularity.month:
      return DateFormat('M月').format(d);
    case ReportGranularity.year:
      return DateFormat('yyyy').format(d);
  }
}

/// 纯函数：把 [data] 切片为**恒 6 个** [StatsBucket]，对齐 [anchor] 所在周期。
///
/// 桶区间 = [anchor-5, … , anchor]（按粒度递推）；遍历 [data] 时先 fill 空
/// [date] 为今日，再按周期 key 累加到对应桶：购物→主序列、账本收入→主序列
/// (ok)、支出→副序列 (danger)。
List<StatsBucket> buildStatsBuckets(
  List<ReportDatum> data,
  ReportGranularity g,
  DateTime anchor,
) {
  final isLedger = data.any((d) => d.kind != null);
  final periodStarts = <DateTime>[];
  final base = _periodStart(anchor, g);
  for (int i = 5; i >= 0; i--) {
    periodStarts.add(_shiftPeriod(base, g, -i));
  }

  final values = List<num>.filled(6, 0);
  final secondaries = List<num>.filled(6, 0);
  final today = DateTime.now();
  for (final d in data) {
    final dateStr =
        d.date.isEmpty ? DateFormat('yyyy-MM-dd').format(today) : d.date;
    final dt = DateFormat('yyyy-MM-dd').tryParse(dateStr);
    if (dt == null) continue;
    final key = _periodKey(dt, g);
    for (int i = 0; i < 6; i++) {
      if (_periodKey(periodStarts[i], g) == key) {
        if (d.kind == 'income') {
          values[i] += d.value;
        } else if (d.kind == 'expense') {
          secondaries[i] += d.value;
        } else {
          // 购物 / 默认主序列
          values[i] += d.value;
        }
        break;
      }
    }
  }

  return [
    for (int i = 0; i < 6; i++)
      StatsBucket(
        label: _periodLabel(periodStarts[i], g),
        value: values[i],
        color: isLedger ? AppTheme.ok : AppTheme.accent,
        secondaryValue: secondaries[i],
        secondaryColor: isLedger ? AppTheme.danger : null,
      ),
  ];
}

String _formatValue(num v, String unit) {
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return '$unit$s';
}

/// 自绘柱状图（6 根 Container，无图表库）。购物单序列、账本收入/支出堆叠。
///
/// [buckets] 恒 6；[unit] 为数值单位前缀（如 '¥'）；[title]/[header] 可选。
class StatsReport extends StatelessWidget {
  final List<StatsBucket> buckets;
  final String unit;
  final String? title;
  final Widget? header;

  const StatsReport({
    super.key,
    required this.buckets,
    required this.unit,
    this.title,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    num maxVal = 0;
    for (final b in buckets) {
      final t = b.value + (b.secondaryValue ?? 0);
      if (t > maxVal) maxVal = t;
    }

    if (maxVal <= 0) {
      return const NotebookEmptyState(
        icon: Icons.bar_chart_outlined,
        title: '这一时期还没有数据',
        subtitle: '换个时间区间，或先记录一些条目。',
      );
    }

    const maxH = 160.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
        if (header != null) header!,
        Container(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.08)),
            boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
          ),
          child: SizedBox(
            height: maxH + 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: buckets.map((b) {
                final total = (b.value + (b.secondaryValue ?? 0)).toDouble();
                final h = (total / maxVal * maxH).toDouble();
                final valH = (b.value / maxVal * maxH).toDouble();
                final secH =
                    ((b.secondaryValue ?? 0) / maxVal * maxH).toDouble();
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatValue(total, unit),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          children: [
                            if (secH > 0)
                              Container(
                                  height: secH,
                                  color: b.secondaryColor ?? b.color),
                            Container(height: valH, color: b.color),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        b.label,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                                color:
                                    scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 带区间切换（上一区间 / 下一区间）与粒度选择（日/月/年）的报表页。
///
/// 内部维护 [anchor] 与 [ReportGranularity]，每次变更重新调用
/// [buildStatsBuckets] 并渲染 [StatsReport]。
class ReportScreen extends StatefulWidget {
  final List<ReportDatum> data;
  final String unit;
  final String? title;
  final Widget? header;
  final ReportGranularity initialGranularity;

  const ReportScreen({
    super.key,
    required this.data,
    required this.unit,
    this.title,
    this.header,
    this.initialGranularity = ReportGranularity.month,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late ReportGranularity _g;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _g = widget.initialGranularity;
    _anchor = _periodStart(DateTime.now(), _g);
  }

  void _prev() => setState(() => _anchor = _shiftPeriod(_anchor, _g, -1));
  void _next() => setState(() => _anchor = _shiftPeriod(_anchor, _g, 1));
  bool get _isCurrent => _periodStart(DateTime.now(), _g) == _anchor;
  void _setGranularity(ReportGranularity g) => setState(() {
        _g = g;
        _anchor = _periodStart(DateTime.now(), g);
      });

  @override
  Widget build(BuildContext context) {
    final buckets = buildStatsBuckets(widget.data, _g, _anchor);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '报表')),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                    onPressed: _prev,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一区间'),
                const Spacer(),
                SegmentedButton<ReportGranularity>(
                  segments: const [
                    ButtonSegment(
                        value: ReportGranularity.day, label: Text('日')),
                    ButtonSegment(
                        value: ReportGranularity.month, label: Text('月')),
                    ButtonSegment(
                        value: ReportGranularity.year, label: Text('年')),
                  ],
                  selected: {_g},
                  onSelectionChanged: (s) => _setGranularity(s.first),
                ),
                const Spacer(),
                IconButton(
                    // 当前周期禁止进入未来区间（规格 C9）
                    onPressed: _isCurrent ? null : _next,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一区间'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: StatsReport(
                  buckets: buckets,
                  unit: widget.unit,
                  title: widget.title,
                  header: widget.header,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
