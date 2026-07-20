import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notebook_reading.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/speed_dial.dart';
import '../widgets/notebook_shared.dart';

/// 读书清单详情：列表 + 手动录入 + 语音录入。
class ReadingDetail extends StatelessWidget {
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const ReadingDetail({
    super.key,
    required this.asr,
    required this.voice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('读书清单'),
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final items = store.reading;
          if (items.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.menu_book_outlined,
              title: '还没有书单',
              subtitle: '点下方按钮添加，或说"想读《三体》"。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spaceSm),
            itemBuilder: (context, i) {
              final it = items[i];
              return _Row(
                item: it,
                onTap: () => _showEdit(context, it),
                onDelete: () => store.deleteReading(it.id),
              );
            },
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
      builder: (_) => _ReadingAddSheet(
        onSave: (item) => context.read<NotebookStore>().addReading(item),
      ),
    );
  }

  void _showEdit(BuildContext context, NotebookReading item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _ReadingAddSheet(
        item: item,
        onSave: (updated) =>
            context.read<NotebookStore>().updateReading(updated),
      ),
    );
  }

  void _startVoice(BuildContext context) {
    showNotebookVoiceSheet<NotebookReading>(
      context,
      NotebookVoiceSheet<NotebookReading>(
        asr: asr,
        title: '语音录入书籍',
        parse: voice.parseReading,
        itemBuilder: (item) => _Preview(item: item),
        onConfirmed: (items) {
          final store = context.read<NotebookStore>();
          for (final it in items) store.addReading(it);
        },
      ),
    );
  }
}

const _statusLabel = {'want': '想读', 'reading': '在读', 'done': '已读'};

class _Preview extends StatelessWidget {
  final NotebookReading item;
  const _Preview({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        if (item.author.isNotEmpty)
          Text(item.author,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.accent)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final NotebookReading item;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  const _Row({required this.item, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _statusLabel[item.status] ?? '想读';
    final (bg, fg) = switch (item.status) {
      'reading' => (AppTheme.warnSoft, AppTheme.warn),
      'done' => (AppTheme.okSoft, AppTheme.ok),
      _ => (AppTheme.accentSoft, AppTheme.accent),
    };
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.author.isNotEmpty) Text(item.author),
            const SizedBox(height: 4),
            NotebookChip(label: label, bg: bg, fg: fg),
          ],
        ),
        trailing: item.rating > 0
            ? StarsRow(value: item.rating, size: 14)
            : IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.4)),
                onPressed: onDelete,
              ),
      ),
    );
  }
}

class _ReadingAddSheet extends StatefulWidget {
  final void Function(NotebookReading) onSave;
  final NotebookReading? item;
  const _ReadingAddSheet({required this.onSave, this.item});

  @override
  State<_ReadingAddSheet> createState() => _ReadingAddSheetState();
}

class _ReadingAddSheetState extends State<_ReadingAddSheet> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  String _status = 'want';
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    if (it != null) {
      _title.text = it.title;
      _author.text = it.author;
      _category.text = it.category;
      _note.text = it.note;
      _status = it.status;
      _rating = it.rating;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    widget.onSave(NotebookReading(
      id: widget.item?.id ?? notebookNewId(),
      title: title,
      author: _author.text.trim(),
      status: _status,
      rating: _rating,
      category: _category.text.trim(),
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
                  child: Text(widget.item == null ? '添加书籍' : '编辑书籍',
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
                    LabeledField(
                        label: '书名 *', controller: _title, hint: '如 三体'),
                    const SizedBox(height: 12),
                    LabeledField(label: '作者', controller: _author),
                    const SizedBox(height: 12),
                    Text('状态', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'want', label: Text('想读')),
                        ButtonSegment(value: 'reading', label: Text('在读')),
                        ButtonSegment(value: 'done', label: Text('已读')),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) =>
                          setState(() => _status = s.first),
                    ),
                    const SizedBox(height: 12),
                    Text('评分', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    StarsRow(
                        value: _rating,
                        onChanged: (v) => setState(() => _rating = v)),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '分类', controller: _category, hint: '小说/技术'),
                    const SizedBox(height: 12),
                    LabeledField(label: '备注', controller: _note, maxLines: 2),
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
