import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/dictionary.dart';
import '../../../models/notebook_ledger.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/speed_dial.dart';
import '../widgets/notebook_report.dart';
import '../widgets/notebook_shared.dart';

/// 收支账本详情：列表 + 手动录入 + 语音录入。
class LedgerDetail extends StatelessWidget {
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const LedgerDetail({
    super.key,
    required this.asr,
    required this.voice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收支账本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: '报表',
            onPressed: () => _showReport(context),
          ),
        ],
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final items = store.ledger;
          if (items.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: '还没有收支记录',
              subtitle: '点下方按钮记一笔，或用语音说"午餐花了 30"。',
            );
          }
          num income = 0, expense = 0;
          for (final it in items) {
            if (it.isIncome) income += it.amount;
            else expense += it.amount;
          }
          return Column(
            children: [
              _Summary(income: income, expense: expense),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppTheme.spaceLg),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppTheme.spaceSm),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return _Row(
                      item: it,
                      onTap: () => _showEdit(context, it),
                      onDelete: () => store.deleteLedger(it.id),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: SpeedDialFab(
        onAdd: () => _showAdd(context),
        onVoice: () => _startVoice(context),
      ),
    );
  }

  void _showAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _LedgerAddSheet(
        onSave: (item) => context.read<NotebookStore>().addLedger(item),
      ),
    );
  }

  void _showEdit(BuildContext context, NotebookLedger item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _LedgerAddSheet(
        item: item,
        onSave: (updated) =>
            context.read<NotebookStore>().updateLedger(updated),
      ),
    );
  }

  void _startVoice(BuildContext context) {
    showNotebookVoiceSheet<NotebookLedger>(
      context,
      NotebookVoiceSheet<NotebookLedger>(
        asr: asr,
        title: '语音录入收支',
        parse: voice.parseLedger,
        itemBuilder: (item) => _Preview(item: item),
        onConfirmed: (items) {
          final store = context.read<NotebookStore>();
          for (final it in items) store.addLedger(it);
        },
      ),
    );
  }

  void _showReport(BuildContext context) {
    final store = context.read<NotebookStore>();
    final data = store.ledger.map((e) => ReportDatum(
          date: e.date.isEmpty
              ? DateFormat('yyyy-MM-dd').format(DateTime.now())
              : e.date,
          value: e.amount,
          kind: e.isIncome ? 'income' : 'expense',
        )).toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportScreen(
        data: data,
        unit: '¥',
        title: '收支报表',
      ),
    ));
  }
}

class _Summary extends StatelessWidget {
  final num income;
  final num expense;
  const _Summary({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(AppTheme.spaceLg),
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: '收入', value: '¥$income', color: AppTheme.ok),
          _Stat(label: '支出', value: '¥$expense', color: AppTheme.danger),
          _Stat(
            label: '结余',
            value: '¥${(income - expense)}',
            color: scheme.onSurface,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color.withValues(alpha: 0.7))),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: color)),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  final NotebookLedger item;
  const _Preview({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        Text(
          '${item.isIncome ? '收入' : '支出'} ¥${item.amount}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: item.isIncome ? AppTheme.ok : AppTheme.danger,
              ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final NotebookLedger item;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  const _Row({required this.item, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          item.isIncome
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded,
          color: item.isIncome ? AppTheme.ok : AppTheme.danger,
        ),
        title: Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: item.date.isNotEmpty
            ? Text(item.date,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5)))
            : (item.category.isNotEmpty ? Text(item.category) : null),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item.isIncome ? '+' : '-'}¥${item.amount}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: item.isIncome ? AppTheme.ok : AppTheme.danger,
                  ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.4)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerAddSheet extends StatefulWidget {
  final void Function(NotebookLedger) onSave;
  final NotebookLedger? item;
  const _LedgerAddSheet({required this.onSave, this.item});

  @override
  State<_LedgerAddSheet> createState() => _LedgerAddSheetState();
}

class _LedgerAddSheetState extends State<_LedgerAddSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _category = '';
  final _note = TextEditingController();
  String _dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  bool _income = false;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    if (it != null) {
      _title.text = it.title;
      _amount.text = it.amount.toString();
      _category = it.category;
      _dateStr = it.date.isNotEmpty ? it.date : _dateStr;
      _income = it.isIncome;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    widget.onSave(NotebookLedger(
      id: widget.item?.id ?? notebookNewId(),
      title: title,
      kind: _income ? 'income' : 'expense',
      amount: num.tryParse(_amount.text) ?? 0,
      category: _category,
      date: _dateStr,
      note: _note.text.trim(),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          top: AppTheme.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spaceLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.item == null ? '记一笔' : '编辑记录',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('支出')),
                        ButtonSegment(value: true, label: Text('收入')),
                      ],
                      selected: {_income},
                      onSelectionChanged: (s) =>
                          setState(() => _income = s.first),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '摘要 *', controller: _title, hint: '如 午餐'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: LabeledField(
                                label: '金额 *',
                                controller: _amount,
                                hint: '0',
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: DateField(
                                label: '日期',
                                value: _dateStr,
                                onChanged: (v) =>
                                    setState(() => _dateStr = v))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('分类',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kBillingTypes
                          .map((type) => ChoiceChip(
                                label: Text(type),
                                selected: _category == type,
                                onSelected: (_) =>
                                    setState(() => _category = type),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '备注', controller: _note, maxLines: 2),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: _save, child: const Text('保存')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
