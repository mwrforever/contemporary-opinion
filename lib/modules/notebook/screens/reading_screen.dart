import 'package:flutter/material.dart';

import '../../../models/notebook_reading.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_shared.dart';

/// 读书清单页（设计稿 scr-reading / scr-reading-edit）。
///
/// 列表行=状态徽标（在读黄/读完绿/想读灰）+ 书名 + 作者 + 分类 + 星级；
/// 新增/编辑全部走底部抽屉，状态枚举单选（想读/在读/读完，沿用取值
/// want/reading/done，规格 C3/C4）。
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  static const _statusValues = ['want', 'reading', 'done'];
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

  /// 打开添加/编辑书目底部抽屉（规格 C1）。
  Future<void> _edit(NotebookReading? initial) async {
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    final authorCtrl = TextEditingController(text: initial?.author ?? '');
    final categoryCtrl = TextEditingController(text: initial?.category ?? '');
    final noteCtrl = TextEditingController(text: initial?.note ?? '');
    var status = initial?.status ?? 'want';
    if (!_statusValues.contains(status)) status = 'want';
    var rating = initial?.rating ?? 0;
    String? error;

    await showNotebookEditSheet(
      context,
      title: initial == null ? '添加书目' : '编辑书目',
      builder: (ctx, setSheetState) => [
        TextField(
          autocorrect: false,
          controller: titleCtrl,
          decoration: InputDecoration(labelText: '书名', errorText: error),
        ),
        const SizedBox(height: 12),
        TextField(
          autocorrect: false,
          controller: authorCtrl,
          decoration: const InputDecoration(labelText: '作者（可选）'),
        ),
        const SizedBox(height: 12),
        Text('状态', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 8),
        EnumChipsField(
          values: _statusValues
              .map((v) => _statusLabels[v] ?? v)
              .toList(growable: false),
          selected: _statusLabels[status] ?? status,
          onChanged: (label) => setSheetState(() {
            status = _statusValues.firstWhere(
              (v) => (_statusLabels[v] ?? v) == label,
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          autocorrect: false,
          controller: categoryCtrl,
          decoration: const InputDecoration(labelText: '分类（可选）'),
        ),
        const SizedBox(height: 12),
        Text('评分（可选）', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 6),
        StarsRow(value: rating, onChanged: (v) => setSheetState(() => rating = v)),
        const SizedBox(height: 12),
        TextField(
          autocorrect: false,
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            hintText: '如：第三章读到一半',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            final title = titleCtrl.text.trim();
            if (title.isEmpty) {
              setSheetState(() => error = '请输入书名');
              return;
            }
            final entity = NotebookReading(
              id: initial?.id ?? notebookNewId(),
              title: title,
              author: authorCtrl.text.trim(),
              status: status,
              rating: rating,
              category: categoryCtrl.text.trim(),
              note: noteCtrl.text.trim(),
            );
            if (initial == null) {
              widget.store.addReading(entity);
            } else {
              widget.store.updateReading(entity);
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
                '删除书目',
                '删除「${initial.title}」？',
                '删除',
              );
              if (ok) {
                await widget.store.deleteReading(initial.id);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ],
    );
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
            _ReadingRow(item: item, onTap: () => _edit(item)),
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

/// 读书列表行：状态徽标 + 书名 + 作者/分类 + 星级 + 右箭头。
class _ReadingRow extends StatelessWidget {
  final NotebookReading item;
  final VoidCallback onTap;

  const _ReadingRow({required this.item, required this.onTap});

  /// 状态徽标配色：想读灰 / 在读黄 / 读完绿。
  String get _tone => switch (item.status) {
        'reading' => 'warn',
        'done' => 'ok',
        _ => 'neutral',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(Icons.menu_book_outlined,
                  size: 22, color: scheme.onSurfaceVariant),
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
                        label: _statusLabel(item.status),
                        tone: _tone,
                      ),
                      if (item.author.isNotEmpty)
                        Text(
                          item.author,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      if (item.category.isNotEmpty)
                        Text(
                          '· ${item.category}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      if (item.rating > 0)
                        StarsRow(value: item.rating, size: 13),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'reading' => '在读',
        'done' => '读完',
        _ => '想读',
      };
}
