import 'package:flutter/material.dart';

import '../../../models/notebook_recipe.dart';
import '../../../services/notebook_store.dart';
import '../../../widgets/confirm_dialog.dart';

/// 菜谱收藏页：菜名/分类/难度/配料/步骤/评分，增删改。
class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, required this.store});

  final NotebookStore store;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  static const _difficultyLabels = {'easy': '简单', 'medium': '中等', 'hard': '困难'};

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

  Future<void> _edit(NotebookRecipe? initial) async {
    final name = TextEditingController(text: initial?.name ?? '');
    final category = TextEditingController(text: initial?.category ?? '');
    final ingredients =
        TextEditingController(text: (initial?.ingredients ?? const []).join('\n'));
    final steps = TextEditingController(text: (initial?.steps ?? const []).join('\n'));
    var difficulty = initial?.difficulty ?? 'medium';
    var rating = initial?.rating ?? 0;
    final result = await showDialog<NotebookRecipe>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(initial == null ? '收藏菜谱' : '编辑菜谱'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '菜名'),
                ),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: '分类'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: difficulty,
                  items: [
                    for (final e in _difficultyLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => difficulty = v ?? 'medium'),
                ),
                TextField(
                  controller: ingredients,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '配料（每行一个）'),
                ),
                TextField(
                  controller: steps,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '步骤（每行一步）'),
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                NotebookRecipe(
                  id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name.text.trim(),
                  category: category.text.trim(),
                  ingredients: ingredients.text
                      .split('\n')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                  steps: steps.text
                      .split('\n')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                  difficulty: difficulty,
                  rating: rating,
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
      await widget.store.addRecipe(result);
    } else {
      await widget.store.updateRecipe(result);
    }
  }

  Future<void> _delete(NotebookRecipe item) async {
    final ok = await ConfirmDialog.show(
      context,
      '删除菜谱',
      '删除「${item.name}」？',
      '删除',
    );
    if (ok) await widget.store.deleteRecipe(item.id);
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
            ListTile(
              title: Text(item.name),
              subtitle: Text(
                '${item.category}${item.category.isEmpty ? '' : ' · '}'
                '${_difficultyLabels[item.difficulty] ?? item.difficulty}'
                '${item.rating > 0 ? ' · ★${item.rating}' : ''}'
                ' · ${item.ingredients.length} 配料',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(item),
              ),
              onTap: () => _edit(item),
            ),
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
