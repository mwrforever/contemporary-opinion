/// 菜谱收藏条目。手动录入为纯表单落库（不接 LLM）；语音走对应 prompt 解析。
class NotebookRecipe {
  final String id;
  final String name;
  final String category;
  final List<String> ingredients;
  final List<String> steps;
  final String difficulty; // 'easy' | 'medium' | 'hard' | ''
  final int rating; // 1-5，0 表示未评分
  final String note;

  NotebookRecipe({
    required this.id,
    required this.name,
    this.category = '',
    this.ingredients = const [],
    this.steps = const [],
    this.difficulty = '',
    this.rating = 0,
    this.note = '',
  });

  factory NotebookRecipe.fromJson(Map<String, dynamic> m) => NotebookRecipe(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        category: (m['category'] ?? '') as String,
        ingredients: _asStringList(m['ingredients']),
        steps: _asStringList(m['steps']),
        difficulty: (m['difficulty'] ?? '') as String,
        rating: m['rating'] is num ? (m['rating'] as num).toInt() : 0,
        note: (m['note'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'ingredients': ingredients,
        'steps': steps,
        'difficulty': difficulty,
        'rating': rating,
        'note': note,
      };

  static List<String> _asStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }
}
