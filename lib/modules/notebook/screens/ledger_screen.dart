import 'package:flutter/material.dart';

import '../../../models/notebook_ledger.dart';
import '../../../services/notebook_store.dart';
import '../../../widgets/confirm_dialog.dart';

/// 收支账本页：收入/支出/结余汇总 + 明细增删改。
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

  Future<void> _edit(NotebookLedger? initial) async {
    final title = TextEditingController(text: initial?.title ?? '');
    final amount = TextEditingController(text: initial?.amount.toString() ?? '');
    final category = TextEditingController(text: initial?.category ?? '');
    var kind = initial?.kind ?? 'expense';
    final result = await showDialog<NotebookLedger>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(initial == null ? '记一笔' : '编辑账目'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('支出')),
                    ButtonSegment(value: 'income', label: Text('收入')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => kind = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '金额'),
                ),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: '分类'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                NotebookLedger(
                  id: initial?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title.text.trim(),
                  kind: kind,
                  amount: num.tryParse(amount.text) ?? 0,
                  category: category.text.trim(),
                  date: '',
                  note: '',
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (initial == null) {
      await widget.store.addLedger(result);
    } else {
      await widget.store.updateLedger(result);
    }
  }

  Future<void> _delete(NotebookLedger item) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除账目',
      '删除「${item.title}」？',
      '删除',
    );
    if (ok) await widget.store.deleteLedger(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.ledger;
    final income = list.where((l) => l.kind == 'income').fold<num>(0, (s, l) => s + l.amount);
    final expense = list.where((l) => l.kind == 'expense').fold<num>(0, (s, l) => s + l.amount);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('收支账本')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('结余 ¥${income - expense}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text('收入 ¥$income  ·  支出 ¥$expense', style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          for (final item in list)
            ListTile(
              title: Text(item.title),
              subtitle: Text('${item.category}${item.date.isEmpty ? '' : ' · ${item.date}'}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.kind == 'income' ? '+' : '-'} ¥${item.amount}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: item.kind == 'income' ? const Color(0xFF3F9D6B) : const Color(0xFFC0492F),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(item),
                  ),
                ],
              ),
              onTap: () => _edit(item),
            ),
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
}
