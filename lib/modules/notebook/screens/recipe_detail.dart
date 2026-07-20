import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notebook_recipe.dart';
import '../../../services/aliyun_asr_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/notebook_shared.dart';
import '../../../widgets/speed_dial.dart';

/// 菜谱收藏详情：列表 + 手动录入 + 语音录入。
class RecipeDetail extends StatelessWidget {
  final AliyunAsrService asr;
  final NotebookVoiceService voice;

  const RecipeDetail({
    super.key,
    required this.asr,
    required this.voice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('菜谱收藏'),
      ),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final items = store.recipes;
          if (items.isEmpty) {
            return const NotebookEmptyState(
              icon: Icons.restaurant_menu_outlined,
              title: '还没有菜谱',
              subtitle: '点下方按钮添加，或说"番茄炒蛋，简单，鸡蛋和西红柿"。',
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
                onDelete: () => store.deleteRecipe(it.id),
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
      builder: (_) => _RecipeAddSheet(
        onSave: (item) => context.read<NotebookStore>().addRecipe(item),
      ),
    );
  }

  void _showEdit(BuildContext context, NotebookRecipe item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _RecipeAddSheet(
        item: item,
        onSave: (updated) =>
            context.read<NotebookStore>().updateRecipe(updated),
      ),
    );
  }

  void _startVoice(BuildContext context) {
    showNotebookVoiceSheet<NotebookRecipe>(
      context,
      NotebookVoiceSheet<NotebookRecipe>(
        asr: asr,
        title: '语音录入菜谱',
        parse: voice.parseRecipe,
        itemBuilder: (item) => _Preview(item: item),
        onConfirmed: (items) {
          final store = context.read<NotebookStore>();
          for (final it in items) store.addRecipe(it);
        },
      ),
    );
  }
}

const _difficultyLabel = {
  'easy': '简单',
  'medium': '中等',
  'hard': '困难',
};

class _Preview extends StatelessWidget {
  final NotebookRecipe item;
  const _Preview({required this.item});

  @override
  Widget build(BuildContext context) {
    final d = _difficultyLabel[item.difficulty] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.name, style: Theme.of(context).textTheme.titleMedium),
        if (d.isNotEmpty)
          Text(d,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.accent)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final NotebookRecipe item;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  const _Row(
      {required this.item, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = _difficultyLabel[item.difficulty];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        boxShadow: AppTheme.elevation(scheme.brightness == Brightness.dark),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(item.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.ingredients.isNotEmpty)
              Text('${item.ingredients.length} 种食材',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5))),
            if (d != null) ...[
              const SizedBox(height: 4),
              NotebookChip(label: d, bg: AppTheme.accentSoft, fg: AppTheme.accent),
            ],
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

class _RecipeAddSheet extends StatefulWidget {
  final void Function(NotebookRecipe) onSave;
  final NotebookRecipe? item;
  const _RecipeAddSheet({required this.onSave, this.item});

  @override
  State<_RecipeAddSheet> createState() => _RecipeAddSheetState();
}

class _RecipeAddSheetState extends State<_RecipeAddSheet> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();
  final _note = TextEditingController();
  String _difficulty = '';
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    if (it != null) {
      _name.text = it.name;
      _category.text = it.category;
      _ingredients.text = it.ingredients.join('\n');
      _steps.text = it.steps.join('\n');
      _note.text = it.note;
      _difficulty = it.difficulty;
      _rating = it.rating;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _note.dispose();
    super.dispose();
  }

  static List<String> _split(String s) => s
      .split(RegExp(r'[\n,]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onSave(NotebookRecipe(
      id: widget.item?.id ?? notebookNewId(),
      name: name,
      category: _category.text.trim(),
      ingredients: _split(_ingredients.text),
      steps: _split(_steps.text),
      difficulty: _difficulty,
      rating: _rating,
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
                  child: Text(
                      widget.item == null ? '添加菜谱' : '编辑菜谱',
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
                        label: '菜名 *', controller: _name, hint: '如 番茄炒蛋'),
                    const SizedBox(height: 12),
                    LabeledField(
                        label: '分类/菜系',
                        controller: _category,
                        hint: '川菜/家常'),
                    const SizedBox(height: 12),
                    LabeledField(
                      label: '食材（每行或逗号分隔）',
                      controller: _ingredients,
                      maxLines: 3,
                      hint: '鸡蛋\n西红柿',
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      label: '步骤（每行或逗号分隔）',
                      controller: _steps,
                      maxLines: 3,
                      hint: '热锅\n下蛋',
                    ),
                    const SizedBox(height: 12),
                    Text('难度', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '', label: Text('未设')),
                        ButtonSegment(value: 'easy', label: Text('简单')),
                        ButtonSegment(value: 'medium', label: Text('中等')),
                        ButtonSegment(value: 'hard', label: Text('困难')),
                      ],
                      selected: {_difficulty},
                      onSelectionChanged: (s) =>
                          setState(() => _difficulty = s.first),
                    ),
                    const SizedBox(height: 12),
                    Text('喜欢度',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    StarsRow(
                        value: _rating,
                        onChanged: (v) => setState(() => _rating = v)),
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
