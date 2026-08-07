import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/dictionary.dart';
import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../widgets/notebook_shared.dart';

/// 报表周期粒度（天 / 月 / 年，无按周）。
enum ShoppingPeriod { day, month, year }

/// 周期起点：按粒度截断（天=当天 0 点，月=1 日，年=1 月 1 日）。
DateTime periodStart(DateTime d, ShoppingPeriod p) => switch (p) {
      ShoppingPeriod.day => DateTime(d.year, d.month, d.day),
      ShoppingPeriod.month => DateTime(d.year, d.month, 1),
      ShoppingPeriod.year => DateTime(d.year, 1, 1),
    };

/// 平移 [delta] 个周期（Dart 自动处理月/年进位溢出）。
DateTime shiftPeriod(DateTime d, ShoppingPeriod p, int delta) => switch (p) {
      ShoppingPeriod.day => DateTime(d.year, d.month, d.day + delta),
      ShoppingPeriod.month => DateTime(d.year, d.month + delta, 1),
      ShoppingPeriod.year => DateTime(d.year + delta, 1, 1),
    };

/// 是否为当前周期（用于禁用「下一周期」按钮与选择器未来项）。
bool isCurrentPeriod(DateTime anchor, ShoppingPeriod p, {DateTime? now}) =>
    periodStart(anchor, p) == periodStart(now ?? DateTime.now(), p);

/// 周期标签：按天 yyyy年M月d日 / 按月 yyyy年M月 / 按年 yyyy年。
String periodLabel(DateTime anchor, ShoppingPeriod p) => switch (p) {
      ShoppingPeriod.day => DateFormat('yyyy年M月d日').format(anchor),
      ShoppingPeriod.month => DateFormat('yyyy年M月').format(anchor),
      ShoppingPeriod.year => DateFormat('yyyy年').format(anchor),
    };

/// 分类占比切片（聚合 + 降序 + 配色）。
class CategorySlice {
  final String label;
  final num value;
  final double percent;
  final Color color;
  const CategorySlice({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
  });
}

/// 把购物项按 [anchor] 所在周期过滤，按分类聚合 price 并降序。
List<CategorySlice> buildCategorySlices(
  List<NotebookShopping> items,
  DateTime anchor,
  ShoppingPeriod p, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final start = periodStart(anchor, p);
  final end = shiftPeriod(start, p, 1);
  final sums = <String, num>{};
  for (final it in items) {
    final ds =
        it.date.isEmpty ? DateFormat('yyyy-MM-dd').format(today) : it.date;
    final dt = DateTime.tryParse(ds);
    if (dt == null || dt.isBefore(start) || !dt.isBefore(end)) continue;
    // 空串或非枚举值统一归入「其他」（枚举单选口径）
    final raw = it.category.trim();
    final cat = (raw.isEmpty || !kShoppingItemTypes.contains(raw))
        ? '其他'
        : raw;
    sums[cat] = (sums[cat] ?? 0) + it.price;
  }
  final total = sums.values.fold<num>(0, (a, b) => a + b);
  final entries = sums.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in entries)
      CategorySlice(
        label: e.key,
        value: e.value,
        percent: total == 0 ? 0 : e.value / total,
        color: shoppingCategoryColor(e.key),
      ),
  ];
}

/// 分类固定调色板（暖平面语义色 + 中性扩展，未知分类落「其他」灰）。
const List<Color> _categoryPalette = [
  AppTheme.accent,
  AppTheme.warn,
  AppTheme.ok,
  AppTheme.danger,
  Color(0xFF8A8D85), // neutral
  Color(0xFF5B7FA6), // 蓝灰
  Color(0xFF8A6FAE), // 紫灰
  Color(0xFFB08A5B), // 棕
];

/// 分类 → 固定配色（与 [kShoppingItemTypes] 顺序对齐循环）。
Color shoppingCategoryColor(String category) {
  if (category == '其他' || category.isEmpty) return _categoryPalette[4];
  const names = [
    '生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居',
    '美妆个护', '母婴', '运动户外', '书籍文具', '药品保健',
  ];
  final i = names.indexOf(category);
  return _categoryPalette[i >= 0 ? i % _categoryPalette.length : 4];
}

/// 环形饼图 painter：按 percent 画扇区，中心挖孔。
class DonutPainter extends CustomPainter {
  final List<CategorySlice> slices;
  final Color holeColor;
  const DonutPainter(this.slices, {required this.holeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final holeRect = Rect.fromCircle(
      center: rect.center,
      radius: size.shortestSide * 0.23,
    );
    var start = -3.14159 / 2; // 12 点方向起
    for (final s in slices) {
      final sweep = s.percent * 2 * 3.14159;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = s.color);
      start += sweep;
    }
    canvas.drawCircle(
        rect.center, holeRect.width / 2, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(covariant DonutPainter old) =>
      old.slices != slices || old.holeColor != holeColor;
}

/// 购物消费趋势报表页：分类占比饼图 + 按天/月/年 + 单一时间单位选择 + 禁未来。
///
/// 默认选中当前时间所在周期；切换粒度回到当前周期；右箭头在当前周期时禁用，
/// 选择器也不可选未来。
class ShoppingTrendScreen extends StatefulWidget {
  final NotebookStore store;
  const ShoppingTrendScreen({super.key, required this.store});

  @override
  State<ShoppingTrendScreen> createState() => _ShoppingTrendScreenState();
}

class _ShoppingTrendScreenState extends State<ShoppingTrendScreen> {
  ShoppingPeriod _p = ShoppingPeriod.month;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    _anchor = periodStart(DateTime.now(), _p);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => mounted ? setState(() {}) : null;

  /// 按当前粒度弹对应选择器（天=系统日历；月/年=自绘弹层），禁选未来。
  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    DateTime? picked;
    switch (_p) {
      case ShoppingPeriod.day:
        picked = await showDatePicker(
          context: context,
          initialDate: _anchor,
          firstDate: DateTime(2000),
          lastDate: now,
        );
      case ShoppingPeriod.month:
        picked = await showMonthPickerSheet(
          context,
          initial: _anchor,
          latest: periodStart(now, ShoppingPeriod.month),
        );
      case ShoppingPeriod.year:
        picked = await showYearPickerSheet(
          context,
          initial: _anchor,
          latest: periodStart(now, ShoppingPeriod.year),
        );
    }
    // picked 被 setState 闭包捕获，Dart 不做提升，这里显式非空断言
    if (picked != null) setState(() => _anchor = periodStart(picked!, _p));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slices = buildCategorySlices(widget.store.shopping, _anchor, _p);
    final total = slices.fold<num>(0, (s, x) => s + x.value);
    final itemCount =
        widget.store.shopping.where((it) => _inPeriod(it, _anchor, _p)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('购物消费趋势')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ShoppingPeriod>(
            segments: const [
              ButtonSegment(value: ShoppingPeriod.day, label: Text('按天')),
              ButtonSegment(value: ShoppingPeriod.month, label: Text('按月')),
              ButtonSegment(value: ShoppingPeriod.year, label: Text('按年')),
            ],
            selected: {_p},
            onSelectionChanged: (s) => setState(() {
              _p = s.first;
              _anchor = periodStart(DateTime.now(), _p);
            }),
          ),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(
              onPressed: () =>
                  setState(() => _anchor = shiftPeriod(_anchor, _p, -1)),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: '上一周期',
            ),
            Expanded(
              child: TextButton(
                onPressed: _pickPeriod,
                child: Text(
                  periodLabel(_anchor, _p),
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              // 当前周期禁用「下一周期」，禁止进入未来统计
              onPressed: isCurrentPeriod(_anchor, _p)
                  ? null
                  : () =>
                      setState(() => _anchor = shiftPeriod(_anchor, _p, 1)),
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: '下一周期',
            ),
          ]),
          const SizedBox(height: 6),
          _summaryCard(context, total, itemCount, slices.length),
          const SizedBox(height: 14),
          if (slices.isEmpty)
            const NotebookEmptyState(
              icon: Icons.pie_chart_outline,
              title: '这一时期还没有数据',
              subtitle: '换个时间区间，或先记录一些条目。',
            )
          else
            _donutCard(context, slices, total, itemCount),
        ],
      ),
    );
  }

  /// 条目是否落在锚点所在周期（空 date 视为今日）。
  bool _inPeriod(NotebookShopping it, DateTime anchor, ShoppingPeriod p) {
    final today = DateTime.now();
    final ds =
        it.date.isEmpty ? DateFormat('yyyy-MM-dd').format(today) : it.date;
    final dt = DateTime.tryParse(ds);
    if (dt == null) return false;
    final start = periodStart(anchor, p);
    final end = shiftPeriod(start, p, 1);
    return !dt.isBefore(start) && dt.isBefore(end);
  }

  Widget _summaryCard(
      BuildContext context, num total, int itemCount, int catCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(children: [
        Text(formatYuan(total),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(width: 6),
        Text('本周期总花费',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const Spacer(),
        _sumItem('$itemCount', '条目'),
        const SizedBox(width: 18),
        _sumItem('$catCount', '分类'),
      ]),
    );
  }

  Widget _sumItem(String v, String k) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(v,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(k,
              style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _donutCard(BuildContext context, List<CategorySlice> slices, num total,
      int itemCount) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(children: [
        SizedBox(
          width: 216,
          height: 216,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: const Size(216, 216),
              painter: DonutPainter(slices, holeColor: scheme.surface),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(formatYuan(total),
                  style:
                      const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('$itemCount 项',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: s.color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text(formatYuan(s.value),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: Text('${(s.percent * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// 月份选择底部弹层：12 个月网格 + 年份左右切换；未来月份禁用。
Future<DateTime?> showMonthPickerSheet(
  BuildContext context, {
  required DateTime initial,
  required DateTime latest,
}) {
  var year = initial.year;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final latestMonth = year == latest.year ? latest.month : 12;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text('选择月份',
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: () => setSheetState(() => year--),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('$year 年',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: year >= latest.year
                    ? null
                    : () => setSheetState(() => year++),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  _pickerCell(
                    ctx,
                    '$m 月',
                    year < latest.year || m <= latestMonth,
                    () => Navigator.of(ctx).pop(DateTime(year, m)),
                  ),
              ],
            ),
          ]),
        );
      },
    ),
  );
}

/// 年份选择底部弹层：当前年往前 20 年网格（未来年份不出现）。
Future<DateTime?> showYearPickerSheet(
  BuildContext context, {
  required DateTime initial,
  required DateTime latest,
}) {
  final years = [for (var y = latest.year; y >= latest.year - 19; y--) y];
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('选择年份',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ]),
          const SizedBox(height: 8),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final y in years)
                _pickerCell(ctx, '$y 年', true,
                    () => Navigator.of(ctx).pop(DateTime(y))),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 选择器网格单元：可点/禁用两态。
Widget _pickerCell(
    BuildContext context, String label, bool enabled, VoidCallback onTap) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? scheme.surfaceContainerHighest
            : scheme.surface.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
