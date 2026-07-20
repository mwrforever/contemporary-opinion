/// 课程（学习记录以课程为维度统一管理）。
///
/// 设计要点（依据批准的记事本重构方案）：
/// - 每门课程聚合其名下的学习记录 [StudyRecord]，记录直接挂在课程下，避免管理混乱。
/// - 语音录入时 LLM **不输出课程名**，课程由 App 在进入课程子页时选定并绑定。
class NotebookCourse {
  final String id;
  final String title;
  final String source; // 来源/平台，可选
  final String status; // 'want' | 'learning' | 'done'
  final int progress; // 0-100
  final int rating; // 1-5，0 表示未评分
  final String category;
  final String note;
  final List<StudyRecord> records;

  NotebookCourse({
    required this.id,
    required this.title,
    this.source = '',
    this.status = 'want',
    this.progress = 0,
    this.rating = 0,
    this.category = '',
    this.note = '',
    this.records = const [],
  });

  factory NotebookCourse.fromJson(Map<String, dynamic> m) => NotebookCourse(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        source: (m['source'] ?? '') as String,
        status: (m['status'] ?? 'want') as String,
        progress: m['progress'] is num ? (m['progress'] as num).toInt() : 0,
        rating: m['rating'] is num ? (m['rating'] as num).toInt() : 0,
        category: (m['category'] ?? '') as String,
        note: (m['note'] ?? '') as String,
        records: _recordsFrom(m['records']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'status': status,
        'progress': progress,
        'rating': rating,
        'category': category,
        'note': note,
        'records': records.map((r) => r.toJson()).toList(),
      };

  NotebookCourse copyWith({
    String? title,
    String? source,
    String? status,
    int? progress,
    int? rating,
    String? category,
    String? note,
    List<StudyRecord>? records,
  }) =>
      NotebookCourse(
        id: id,
        title: title ?? this.title,
        source: source ?? this.source,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        rating: rating ?? this.rating,
        category: category ?? this.category,
        note: note ?? this.note,
        records: records ?? this.records,
      );

  static List<StudyRecord> _recordsFrom(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => StudyRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }
}

/// 课程下的单条学习记录。
class StudyRecord {
  final String id;
  final String title;
  final String content;
  final int rating; // 1-5，0 表示未评分
  final String note;
  final DateTime createdAt;

  StudyRecord({
    required this.id,
    required this.title,
    this.content = '',
    this.rating = 0,
    this.note = '',
    required this.createdAt,
  });

  factory StudyRecord.fromJson(Map<String, dynamic> m) => StudyRecord(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        rating: m['rating'] is num ? (m['rating'] as num).toInt() : 0,
        note: (m['note'] ?? '') as String,
        createdAt: m['createdAt'] is String
            ? DateTime.tryParse(m['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'rating': rating,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  StudyRecord copyWith({
    String? id,
    String? title,
    String? content,
    int? rating,
    String? note,
    DateTime? createdAt,
  }) =>
      StudyRecord(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        rating: rating ?? this.rating,
        note: note ?? this.note,
        createdAt: createdAt ?? this.createdAt,
      );
}
