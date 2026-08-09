import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/dictionary.dart';
import '../../../models/notebook_ledger.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_report.dart';
import '../widgets/notebook_shared.dart';

/// 收支账本页（设计稿 scr-ledger / scr-ledger-edit）。
///
/// 顶部汇总卡（结余/收入/支出）+ 明细行徽标化（收入绿/支出黄 + 消费类型
/// chip + 日期 + 金额红绿）；新增/编辑全部走底部抽屉，消费类型为支出 9 项
/// / 收入 6 项枚举联动（规格 C2/C6/C8）。
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// 打开记账/编辑账目底部抽屉（规格 C1/C2）。
  Future<void> _edit(NotebookLedger? initial) async {
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    final amountCtrl = TextEditingController(
      text: initial == null ? '' : _trimAmount(initial.amount),
    );
    final noteCtrl = TextEditingController(text: initial?.note ?? '');
    // 收支分段与消费类型枚举联动；旧数据分类不在枚举内时归一为首项
    var kind = initial?.kind ?? 'expense';
    var category = initial?.category ?? '';
    final defaultTypes = kind == 'expense' ? kExpenseTypes : kIncomeTypes;
    if (!defaultTypes.contains(category)) category = defaultTypes.first;
    var date = initial?.date ?? '';
    String? error;

    await showNotebookEditSheet(
      context,
      title: initial == null ? '记一笔' : '编辑账目',
      builder: (ctx, setSheetState) {
        final types = kind == 'expense' ? kExpenseTypes : kIncomeTypes;
        return [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('支出')),
              ButtonSegment(value: 'income', label: Text('收入')),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setSheetState(() {
              kind = s.first;
              // 切换到另一侧后，选中项不在新枚举里则重置为该侧首项
              final nextTypes =
                  kind == 'expense' ? kExpenseTypes : kIncomeTypes;
              if (!nextTypes.contains(category)) category = nextTypes.first;
              error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            autocorrect: false,
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          const SizedBox(height: 12),
          TextField(
            autocorrect: false,
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '金额',
              prefixText: '¥ ',
              errorText: error,
            ),
          ),
          const SizedBox(height: 12),
          Text('消费类型', style: Theme.of(ctx).textTheme.labelMedium),
          const SizedBox(height: 8),
          EnumChipsField(
            values: types,
            selected: category,
            onChanged: (v) => setSheetState(() => category = v),
          ),
          const SizedBox(height: 12),
          DateField(
            label: '日期（可选）',
            value: date,
            onChanged: (v) => setSheetState(() => date = v),
          ),
          const SizedBox(height: 12),
          TextField(
            autocorrect: false,
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              hintText: '如：楼下新开的川菜馆',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              final amount = num.tryParse(amountCtrl.text.trim());
              if (title.isEmpty) {
                setSheetState(() => error = '请输入标题');
                return;
              }
              if (amount == null || amount < 0) {
                setSheetState(() => error = '请输入有效金额（不小于 0）');
                return;
              }
              final entity = NotebookLedger(
                id: initial?.id ?? notebookNewId(),
                title: title,
                kind: kind,
                amount: amount,
                category: category,
                date: date,
                note: noteCtrl.text.trim(),
              );
              if (initial == null) {
                widget.store.addLedger(entity);
              } else {
                widget.store.updateLedger(entity);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
          if (initial != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                final ok = await ConfirmDialog.show(
                  ctx,
                  '删除账目',
                  '删除「${initial.title}」？',
                  '删除',
                );
                if (ok) {
                  await widget.store.deleteLedger(initial.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          ],
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.ledger;
    final income =
        list.where((l) => l.isIncome).fold<num>(0, (s, l) => s + l.amount);
    final expense =
        list.where((l) => !l.isIncome).fold<num>(0, (s, l) => s + l.amount);
    return Scaffold(
      appBar: AppBar(
        title: const Text('收支账本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: '收支报表',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReportScreen(
                  title: '收支报表',
                  unit: '¥',
                  data: [
                    for (final l in widget.store.ledger)
                      ReportDatum(date: l.date, value: l.amount, kind: l.kind),
                  ],
                  header: _reportHeader(context),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(
            balance: income - expense,
            income: income,
            expense: expense,
          ),
          const SizedBox(height: 8),
          for (final item in list) _LedgerRow(item: item, onTap: () => _edit(item)),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有账目，点右下角记一笔')),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// 收支报表结余总览卡 + 图例（规格 C9：本月结余/收入/支出）。
  Widget _reportHeader(BuildContext context) {
    final now = DateTime.now();
    final ym = DateFormat('yyyy-MM').format(now);
    num income = 0, expense = 0;
    for (final l in widget.store.ledger) {
      final ds = l.date.isEmpty ? DateFormat('yyyy-MM-dd').format(now) : l.date;
      if (!ds.startsWith(ym)) continue;
      if (l.isIncome) {
        income += l.amount;
      } else {
        expense += l.amount;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          balance: income - expense,
          income: income,
          expense: expense,
          label: '本月结余',
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(context, AppTheme.ok, '收入'),
            const SizedBox(width: 18),
            _legendDot(context, AppTheme.danger, '支出'),
          ],
        ),
      ],
    );
  }

  /// 图例：色点 + 文案（收入绿/支出红）。
  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 汇总卡：结余大数 + 收入/支出两列（设计稿 sum-card）。
class _SummaryCard extends StatelessWidget {
  final num balance;
  final num income;
  final num expense;
  final String label;

  const _SummaryCard({
    required this.balance,
    required this.income,
    required this.expense,
    this.label = '结余',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatYuanThousands(balance),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _sumValue(context, '收入', income, AppTheme.ok),
              const SizedBox(width: 24),
              _sumValue(context, '支出', expense, AppTheme.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sumValue(
      BuildContext context, String label, num value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? color.withValues(alpha: 0.9) : color;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatYuanThousands(value),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 明细行：类型徽标 + 消费类型 chip + 日期 + 金额（收入绿/支出黄，规格 C8）。
class _LedgerRow extends StatelessWidget {
  final NotebookLedger item;
  final VoidCallback onTap;

  const _LedgerRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = item.isIncome;
    final tone = isIncome ? 'ok' : 'warn';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isIncome ? AppTheme.okSoft : AppTheme.warnSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                isIncome
                    ? Icons.add_circle_outline_rounded
                    : Icons.campaign_outlined,
                size: 22,
                color: isIncome ? AppTheme.ok : AppTheme.warn,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      semanticChip(
                        context,
                        label: isIncome ? '收入' : '支出',
                        tone: tone,
                      ),
                      if (item.category.isNotEmpty)
                        NotebookChip(
                          label: item.category,
                          bg: scheme.surfaceContainerHighest,
                          fg: scheme.onSurfaceVariant,
                        ),
                      if (item.date.isNotEmpty)
                        Text(
                          _shortDate(item.date),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isIncome ? '+' : '-'}${formatYuanThousands(item.amount)}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isIncome ? AppTheme.ok : AppTheme.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// yyyy-MM-dd → MM-dd（明细行紧凑日期展示）。
  String _shortDate(String date) {
    final dt = DateTime.tryParse(date);
    return dt == null ? date : DateFormat('MM-dd').format(dt);
  }
}

/// 金额回填：整数不带小数点，小数保留两位（与购物抽屉口径一致）。
String _trimAmount(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
