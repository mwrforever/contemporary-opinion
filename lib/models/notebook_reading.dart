/// 读书清单条目。手动录入为纯表单落库（不接 LLM）；语音走对应 prompt 解析。
class NotebookReading {
  final String id;
  final String title;
  final String author;
  final String status; // 'want' | 'reading' | 'done'
  final int rating; // 1-5，0 表示未评分
  final String category;
  final String note;

  NotebookReading({
    required this.id,
    required this.title,
    this.author = '',
    this.status = 'want',
    this.rating = 0,
    this.category = '',
    this.note = '',
  });

  factory NotebookReading.fromJson(Map<String, dynamic> m) => NotebookReading(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        author: (m['author'] ?? '') as String,
        status: (m['status'] ?? 'want') as String,
        rating: m['rating'] is num ? (m['rating'] as num).toInt() : 0,
        category: (m['category'] ?? '') as String,
        note: (m['note'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'status': status,
        'rating': rating,
        'category': category,
        'note': note,
      };
}
