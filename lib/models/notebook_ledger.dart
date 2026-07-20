/// 收支账本条目。手动录入为纯表单落库（不接 LLM）；语音走对应 prompt 解析。
class NotebookLedger {
  final String id;
  final String title;
  final String kind; // 'income' | 'expense'
  final num amount;
  final String category;
  final String date; // yyyy-MM-dd，可选
  final String note;

  NotebookLedger({
    required this.id,
    required this.title,
    this.kind = 'expense',
    this.amount = 0,
    this.category = '',
    this.date = '',
    this.note = '',
  });

  bool get isIncome => kind == 'income';

  factory NotebookLedger.fromJson(Map<String, dynamic> m) => NotebookLedger(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        kind: (m['type'] ?? m['kind'] ?? 'expense') as String,
        amount: m['amount'] is num ? m['amount'] as num : 0,
        category: (m['category'] ?? '') as String,
        date: (m['date'] ?? '') as String,
        note: (m['note'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'amount': amount,
        'category': category,
        'date': date,
        'note': note,
      };
}
