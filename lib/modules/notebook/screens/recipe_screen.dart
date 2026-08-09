import 'package:flutter/material.dart';

import '../../../models/notebook_recipe.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_shared.dart';

/// 菜谱收藏页（设计稿 scr-recipe / scr-recipe-edit）。
///
/// 列表行=分类徽标 + 菜名 + 难度徽标（简单绿/中等黄/困难红）+ 配料/步骤数
/// + 星级；新增/编辑全部走底部抽屉，难度枚举单选（简单/中等/困难，沿用
/// 取值 easy/medium/hard，规格 C3/C4/C7）。
class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  static const _difficultyValues = ['easy', 'medium', 'hard'];

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

  /// 打开收藏/编辑菜谱底部抽屉（规格 C1/C7）。
  Future<void> _edit(NotebookRecipe? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final categoryCtrl = TextEditingController(text: initial?.category ?? '');
    final ingredientsCtrl = TextEditingController(
      text: (initial?.ingredients ?? const []).join('\n'),
    );
    final stepsCtrl = TextEditingController(
      text: (initial?.steps ?? const []).join('\n'),
    );
    final noteCtrl = TextEditingController(text: initial?.note ?? '');
    var difficulty = initial?.difficulty ?? 'medium';
    if (!_difficultyValues.contains(difficulty)) difficulty = 'medium';
    var rating = initial?.rating ?? 0;
    String? error;

    await showNotebookEditSheet(
      context,
      title: initial == null ? '收藏菜谱' : '编辑菜谱',
      builder: (ctx, setSheetState) => [
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(labelText: '菜名', errorText: error),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: categoryCtrl,
          decoration: const InputDecoration(labelText: '分类（可选）'),
        ),
        const SizedBox(height: 12),
        Text('难度', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 8),
        EnumChipsField(
          values: _difficultyValues
              .map((v) => recipeDifficultyLabel(v))
              .toList(growable: false),
          selected: recipeDifficultyLabel(difficulty),
          onChanged: (label) => setSheetState(() {
            difficulty = _difficultyValues.firstWhere(
              (v) => recipeDifficultyLabel(v) == label,
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: ingredientsCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '配料（每行一项）',
            hintText: '如：嫩豆腐 400g',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: stepsCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '步骤（每行一步）',
            hintText: '如：1. 豆腐切块焯水',
          ),
        ),
        const SizedBox(height: 12),
        Text('评分（可选）', style: Theme.of(ctx).textTheme.labelMedium),
        const SizedBox(height: 6),
        StarsRow(value: rating, onChanged: (v) => setSheetState(() => rating = v)),
        const SizedBox(height: 12),
        TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            hintText: '如：豆瓣酱选郫县的更香',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              setSheetState(() => error = '请输入菜名');
              return;
            }
            final entity = NotebookRecipe(
              id: initial?.id ?? notebookNewId(),
              name: name,
              category: categoryCtrl.text.trim(),
              ingredients: _lines(ingredientsCtrl.text),
              steps: _lines(stepsCtrl.text),
              difficulty: difficulty,
              rating: rating,
              note: noteCtrl.text.trim(),
            );
            if (initial == null) {
              widget.store.addRecipe(entity);
            } else {
              widget.store.updateRecipe(entity);
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
                '删除菜谱',
                '删除「${initial.name}」？',
                '删除',
              );
              if (ok) {
                await widget.store.deleteRecipe(initial.id);
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
      appBar: AppBar(title: const Text('菜谱收藏')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final item in widget.store.recipes)
            _RecipeRow(item: item, onTap: () => _edit(item)),
          if (widget.store.recipes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('还没有菜谱，点右下角收藏')),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// 菜谱列表行：分类徽标 + 菜名 + 难度徽标 + 配料/步骤数 + 星级。
class _RecipeRow extends StatelessWidget {
  final NotebookRecipe item;
  final VoidCallback onTap;

  const _RecipeRow({required this.item, required this.onTap});

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
              child: Icon(Icons.restaurant_outlined,
                  size: 22, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
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
                      if (item.category.isNotEmpty)
                        NotebookChip(
                          label: item.category,
                          bg: scheme.surfaceContainerHighest,
                          fg: scheme.onSurfaceVariant,
                        ),
                      semanticChip(
                        context,
                        label: recipeDifficultyLabel(item.difficulty),
                        tone: recipeDifficultyTone(item.difficulty),
                      ),
                      Text(
                        '${item.ingredients.length} 配料 · ${item.steps.length} 步',
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
            if (item.rating > 0) ...[
              const SizedBox(width: 8),
              StarsRow(value: item.rating, size: 13),
            ],
          ],
        ),
      ),
    );
  }
}

/// 菜谱难度中文文案（简单/中等/困难）。
String recipeDifficultyLabel(String difficulty) => switch (difficulty) {
      'easy' => '简单',
      'hard' => '困难',
      _ => '中等',
    };

/// 菜谱难度徽标配色：简单绿 / 中等黄 / 困难红。
String recipeDifficultyTone(String difficulty) => switch (difficulty) {
      'easy' => 'ok',
      'hard' => 'danger',
      _ => 'warn',
    };

/// 多行文本按行拆分并去空（配料/步骤每行一项）。
List<String> _lines(String text) => text
    .split('\n')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();
