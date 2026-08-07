/// 默认子购物车 id（空字符串表示「未分组」）。
const String kDefaultCartId = '';

/// 「未分组」子购物车的展示名。
const String kDefaultCartName = '未分组';

/// 子购物车：购物项的逻辑分组容器（独立于购物项存储，外键 cartId 关联）。
///
/// 与 [NotebookShopping] 同为 JSON-map 存储（无 Hive 适配器），复用
/// `NotebookStore` 的统一读写。
class NotebookShoppingCart {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? note;

  NotebookShoppingCart({
    required this.id,
    required this.name,
    required this.createdAt,
    this.note,
  });

  factory NotebookShoppingCart.fromJson(Map<String, dynamic> m) =>
      NotebookShoppingCart(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        createdAt: m['createdAt'] is DateTime
            ? m['createdAt'] as DateTime
            : (DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
                DateTime.now()),
        note: m['note'] is String ? m['note'] as String : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
      };
}

/// 购物清单条目。手动录入为纯表单落库（不接 LLM）；语音走对应 prompt 解析。
///
/// v4 起只保留单一实付金额 [price]（去掉预期/差值设计）；fromJson 仍兼容
/// 旧键读取（实付优先、预期兜底），保证 Hive 存量数据迁移不丢金额。
class NotebookShopping {
  final String id;
  final String item;
  final num price; // 实付金额（单一金额）
  final String category;
  final String note;
  final String cartId; // 归属子购物车 id，默认 '' = 未分组
  final String date; // yyyy-MM-dd，可选；聚合时为空视为录入日（今日）
  final DateTime createdAt; // 创建时间，用于前端展示

  NotebookShopping({
    required this.id,
    required this.item,
    this.price = 0,
    this.category = '',
    this.note = '',
    this.cartId = kDefaultCartId,
    this.date = '',
    required this.createdAt,
  });

  factory NotebookShopping.fromJson(Map<String, dynamic> m) {
    // 兼容旧格式：price 优先，其次实付（snake/camel），最后预期价兜底
    final actual = m['price'] is num
        ? m['price'] as num
        : m['actual_price'] is num
            ? m['actual_price'] as num
            : m['actualPrice'] is num
                ? m['actualPrice'] as num
                : 0;
    final expected = m['expected_price'] is num
        ? m['expected_price'] as num
        : m['expectedPrice'] is num
            ? m['expectedPrice'] as num
            : 0;

    return NotebookShopping(
      id: (m['id'] ?? '') as String,
      item: (m['item'] ?? '') as String,
      price: actual > 0 ? actual : expected,
      category: (m['category'] ?? '') as String,
      note: (m['note'] ?? '') as String,
      cartId: (m['cartId'] ?? kDefaultCartId) as String,
      date: (m['date'] ?? '') as String,
      createdAt: m['createdAt'] is DateTime
          ? m['createdAt'] as DateTime
          : (DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
              DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'item': item,
        'price': price,
        'category': category,
        'note': note,
        'cartId': cartId,
        'date': date,
        'createdAt': createdAt.toIso8601String(),
      };
}
