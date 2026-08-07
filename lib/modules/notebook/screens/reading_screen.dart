import 'package:flutter/material.dart';

import '../../../models/notebook_reading.dart';
import '../../../services/notebook_store.dart';
import '../../../widgets/confirm_dialog.dart';

/// 读书清单页：书名/作者/状态/评分，增删改。
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  static const _statusLabels = {'want': '想读', 'reading': '在读', 'done': '读完'};

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

  Future<void> _edit(NotebookReading? initial) async {
    final title = TextEditingController(text: initial?.title ?? '');
    final author = TextEditingController(text: initial?.author ?? '');
    final category = TextEditingController(text: initial?.category ?? '');
    var status = initial?.status ?? 'want';
    var rating = initial?.rating ?? 0;
    final result = await showDialog<NotebookReading>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(initial == null ? '添加书目' : '编辑书目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '书名'),
              ),
              TextField(
                controller: author,
                decoration: const InputDecoration(labelText: '作者'),
              ),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: [
                  for (final e in _statusLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => status = v ?? 'want'),
              ),
              TextField(
                controller: category,
                decoration: const InputDecoration(labelText: '分类'),
              ),
              Row(
                children: [
                  const Text('评分：'),
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        i <= rating ? Icons.star : Icons.star_border,
                        color: const Color(0xFFC9782B),
                      ),
                      onPressed: () => setState(() => rating = i),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                NotebookReading(
                  id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title.text.trim(),
                  author: author.text.trim(),
                  status: status,
                  rating: rating,
                  category: category.text.trim(),
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
      await widget.store.addReading(result);
    } else {
      await widget.store.updateReading(result);
    }
  }

  Future<void> _delete(NotebookReading item) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除书目',
      '删除「${item.title}」？',
      '删除',
    );
    if (ok) await widget.store.deleteReading(item.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('读书清单')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final item in widget.store.reading)
            ListTile(
              title: Text(item.title),
              subtitle: Text(
                '${item.author} · ${_statusLabels[item.status] ?? item.status}'
                '${item.category.isEmpty ? '' : ' · ${item.category}'}'
                '${item.rating > 0 ? ' · ★${item.rating}' : ''}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(item),
              ),
              onTap: () => _edit(item),
            ),
          if (widget.store.reading.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有书目，点右下角添加')),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
