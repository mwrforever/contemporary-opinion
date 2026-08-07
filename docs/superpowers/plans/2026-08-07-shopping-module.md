# 购物清单模块整改 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按已批准规格（`docs/superpowers/specs/2026-08-06-shopping-module-design.md`，C1–C8 全确认）完成购物清单模块整改：表结构 v4 迁移（去预期价、price 单金额）、购物车列表→子页层级重构、抽屉式新增/编辑（枚举折叠 + 日期选择器）、分类占比饼图报表（按天/月/年、禁未来）。

**Architecture:** 数据层（SQLite v4 重建 shopping_items + 模型/DAO 收敛 price）先行并全绿；随后 UI 层按「车列表 → 子页 → 两个抽屉」顺序搭建，全部走底部弹层；报表独立新屏（ShoppingTrendScreen）自绘环形饼图，保留现有 ReportScreen 给收支账本继续使用。纯函数（枚举计数、周期聚合、饼图扇区）与 widget 分层测试。

**Tech Stack:** Flutter 3.44.8 / Dart 3.12，sqflite（v4 迁移），intl 0.20.3（DateFormat），flutter_test + sqflite_common_ffi（FFI 内存库测试），Provider（NotebookStore）。

## Global Constraints

- 全项目中文注释/日志/文档；UTF-8 无 BOM；LF 行尾。
- 遵守根 `AGENTS.md`：类/方法/参数/返回值/异常中文注释；核心功能（数据迁移、DAO、报表聚合）测试 100% 覆盖，其余 ≥80%；无死代码；本次改动使旧测试失效的直接删除。
- 设计语言锁定方向 A 温暖平面 token（`AppTheme`）；图标统一 Material 线性图标，禁止 emoji。
- 枚举与日期一律走选择器/枚举组件，禁止手打输入。
- 只提交本次改动文件；不碰工作区他人未提交改动（`.gitignore`、`lib/services/audio_capture_io.dart`、`test/pcm_resampler_test.dart`、linux/macos/windows 平台文件等）。
- 全部 flutter 命令在项目根 `D:\code\project\contemporary-opinion\contemporary-opinion` 执行。

---

### Task 1: 数据层 v4 —— 表结构迁移 + 模型收敛 + DAO 对齐

**Files:**
- Modify: `lib/data/database_helper.dart`（`_dbVersion`、`_onUpgrade`、`_upgradeV4`、`_createNotebookTables` 的 shopping_items 建表语句）
- Modify: `lib/models/notebook_shopping.dart`
- Modify: `lib/data/daos/notebook_daos.dart`（ShoppingDao 的 insertItem/updateItem/listItems）
- Modify: `lib/services/notebook_store.dart`（无需逻辑改动，仅确认编译；`cartsOf`/CRUD 不变）
- Modify: `test/data/database_helper_test.dart`
- Modify: `test/notebook_daos_test.dart`
- Modify: `test/notebook_store_test.dart`
- Modify: `test/legacy_notebook_migration_test.dart`
- Test: `test/shopping_v4_migration_test.dart`（新建，v3→v4 迁移验证）

**Interfaces:**
- Consumes: 现有 `NotebookStore`/`ShoppingDao` API（签名不变，仅字段变化）。
- Produces:
  - `NotebookShopping` 构造：`NotebookShopping({required String id, required String item, num price = 0, String category = '', String note = '', String cartId = kDefaultCartId, String date = '', required DateTime createdAt})`
  - `NotebookShopping.price`（num，替代 expectedPrice/actualPrice）
  - `NotebookShopping.fromJson` 兼容旧键：`price` 优先读 `price`/`actual_price`/`actualPrice`，兜底 `expected_price`/`expectedPrice`
  - `NotebookShopping.toJson` 输出：`{'id','item','price','category','note','cartId','date','createdAt'}`
  - shopping_items 表 v4 列：`id, user_id, cart_id, item, price REAL NOT NULL DEFAULT 0, category TEXT, note TEXT, date TEXT, created_at TEXT`（无 expected_price）

- [ ] **Step 1: 写迁移失败测试（先红）**

新建 `test/shopping_v4_migration_test.dart`：

```dart
// v3 → v4 购物表迁移测试：去 expected_price、actual_price 改名 price、实付优先/预期兜底
import 'dart:io';

import 'package:daily_planner/data/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shopping_v4_test_');
    dbPath = '${tempDir.path}${Platform.pathSeparator}migration.db';
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await tempDir.delete(recursive: true);
  });

  // 手工构造 v3 库（version=3，onCreate 复刻旧 shopping_items 结构）
  Future<Database> createV3Db() async {
    return databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              created_at TEXT NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE shopping_carts(
              id TEXT PRIMARY KEY,
              user_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              note TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )''');
          await db.execute('''
            CREATE TABLE shopping_items(
              id TEXT PRIMARY KEY,
              user_id INTEGER NOT NULL,
              cart_id TEXT,
              item TEXT NOT NULL,
              expected_price REAL,
              actual_price REAL,
              category TEXT,
              note TEXT,
              date TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
              FOREIGN KEY(cart_id) REFERENCES shopping_carts(id) ON DELETE SET NULL
            )''');
        },
      ),
    );
  }

  test('v3 库升级到 v4：shopping_items 去 expected_price、actual_price 改名 price、实付优先兜底预期', () async {
    final raw = await createV3Db();
    await raw.insert('users', {
      'username': 'u1',
      'password_hash': 'h',
      'created_at': '2026-08-01T00:00:00',
    });
    // 实付 > 0：迁移后 price = 实付
    await raw.insert('shopping_items', {
      'id': 'i1', 'user_id': 1, 'cart_id': null, 'item': '牛奶',
      'expected_price': 10, 'actual_price': 9.5, 'category': '生鲜食品',
      'note': '', 'date': '2026-08-06', 'created_at': '2026-08-06T00:00:00',
    });
    // 实付 = 0 且预期 > 0：迁移后 price = 预期（兜底）
    await raw.insert('shopping_items', {
      'id': 'i2', 'user_id': 1, 'cart_id': null, 'item': '苹果',
      'expected_price': 5, 'actual_price': 0, 'category': '生鲜食品',
      'note': '', 'date': '', 'created_at': '2026-08-06T00:00:00',
    });
    await raw.close();

    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(dbPath);
    final db = await DatabaseHelper.instance.database;

    final cols = (await db.rawQuery('PRAGMA table_info(shopping_items)'))
        .map((c) => c['name'])
        .toList();
    expect(cols, contains('price'));
    expect(cols, isNot(contains('expected_price')));
    expect(cols, isNot(contains('actual_price')));

    final rows = await db.query('shopping_items', orderBy: 'id ASC');
    expect(rows[0]['price'], 9.5);
    expect(rows[1]['price'], 5);
  });
}
```

运行：`flutter test test/shopping_v4_migration_test.dart -v`
Expected: FAIL（当前仍是 v3 结构，无 price 列）

- [ ] **Step 2: 改 `lib/data/database_helper.dart`**

```dart
  static const _dbVersion = 4;
```

`_onUpgrade` 末尾追加：

```dart
    if (oldVersion < 4) {
      await _upgradeV4(db);
    }
```

新增方法（紧邻 `_upgradeV3`）：

```dart
  /// v4 迁移：购物项去掉「预期价」，实付列改名 price（单一金额）。
  ///
  /// SQLite 删列需重建表：建新表 → 映射拷贝（实付优先，实付为 0 时以预期
  /// 价兜底，避免丢失旧数据唯一金额信息）→ 删旧表 → 改名。
  Future<void> _upgradeV4(Database db) async {
    await db.execute('''
      CREATE TABLE shopping_items_v4(
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        cart_id TEXT,
        item TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        category TEXT,
        note TEXT,
        date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(cart_id) REFERENCES shopping_carts(id) ON DELETE SET NULL
      )''');
    await db.execute('''
      INSERT INTO shopping_items_v4(id, user_id, cart_id, item, price, category, note, date, created_at)
      SELECT id, user_id, cart_id, item,
             CASE WHEN actual_price > 0 THEN actual_price ELSE expected_price END,
             category, note, date, created_at
      FROM shopping_items''');
    await db.execute('DROP TABLE shopping_items');
    await db.execute('ALTER TABLE shopping_items_v4 RENAME TO shopping_items');
  }
```

`_createNotebookTables` 中 shopping_items 建表语句替换为 v4 结构（列同上，无 expected_price/actual_price，改为 `price REAL NOT NULL DEFAULT 0`）。

- [ ] **Step 3: 改 `lib/models/notebook_shopping.dart`**

类级注释补充「v4 起单一实付金额 price」。构造与 fromJson/toJson：

```dart
class NotebookShopping {
  final String id;
  final String item;
  final num price; // 实付金额（v4 起单一金额，去掉预期/差值）
  final String category;
  final String note;
  final String cartId;
  final String date;
  final DateTime createdAt;

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
```

- [ ] **Step 4: 改 `lib/data/daos/notebook_daos.dart` ShoppingDao**

`insertItem` 列替换：

```dart
      'price': item.price,
```

（删除 `'expected_price': item.expectedPrice, 'actual_price': item.actualPrice,` 两行）

`updateItem` 的 map 同理只保留 `'price': item.price`。

`listItems` 的 fromJson map 改为：

```dart
          'price': r['price'],
```

（删除 `'expectedPrice': r['expected_price'], 'actualPrice': r['actual_price'],`）

- [ ] **Step 5: 更新既有测试（数据层）**

`test/notebook_daos_test.dart` ShoppingDao 组：所有 `expectedPrice: X, actualPrice: Y` 替换为 `price: Y`；断言 `updated.expectedPrice` 改 `updated.price`。

`test/notebook_store_test.dart` 购物用例：`expectedPrice: 10, actualPrice: 9.5` → `price: 9.5`。

`test/legacy_notebook_migration_test.dart`：购物项 Hive 数据改为手写旧格式 map（模拟存量旧数据），验证 fromJson 兜底：

```dart
    await items.put(
      'i1',
      {
        'id': 'i1',
        'item': '牛奶',
        'expected_price': 10,
        'actual_price': 9.5,
        'category': '生鲜食品',
        'note': '',
        'cartId': 'c1',
        'date': '2026-08-05',
        'createdAt': '2026-08-01T00:00:00',
      },
    );
```

迁移断言后追加一行验证 price 落库：

```dart
    final migrated = (await db.query('shopping_items', where: 'user_id = 1')).single;
    expect(migrated['price'], 9.5);
```

`test/data/database_helper_test.dart`：`shopping_items 删除购物车后 cart_id 置空` 用例的 insert 去掉 expected_price/actual_price 改传 `'price': 9.5`；新增断言 `PRAGMA table_info(shopping_items)` 含 price、不含 expected_price。

- [ ] **Step 6: 跑全量数据层测试**

Run: `flutter test test/shopping_v4_migration_test.dart test/notebook_daos_test.dart test/notebook_store_test.dart test/legacy_notebook_migration_test.dart test/data/database_helper_test.dart -v`
Expected: 全 PASS

- [ ] **Step 7: Commit**

```bash
git add lib/data/database_helper.dart lib/models/notebook_shopping.dart lib/data/daos/notebook_daos.dart test/ && git commit -m "feat: 购物表结构v4迁移（去预期价、price单金额）+ 模型DAO对齐"
```

---

### Task 2: 购物项类型枚举 + 枚举折叠组件（两行裁剪可展开）

**Files:**
- Modify: `lib/models/dictionary.dart`
- Create: `lib/modules/notebook/widgets/enum_chips_field.dart`
- Test: `test/enum_chips_field_test.dart`（新建）

**Interfaces:**
- Consumes: `AppTheme`（radiusSm/spaceSm），Material。
- Produces:
  - `const List<String> kShoppingItemTypes`（dictionary.dart）
  - `int countChipsInRows({required List<String> labels, required int maxRows, required double maxWidth, required TextStyle style, double horizontalPadding = 14, double gap = 8})`：纯函数，模拟换行返回前 maxRows 行可容纳的 chip 数
  - `class EnumChipsField extends StatefulWidget { final List<String> values; final String selected; final ValueChanged<String> onChanged; final int maxRows; }`

- [ ] **Step 1: 写失败测试**

`test/enum_chips_field_test.dart`：

```dart
import 'package:daily_planner/modules/notebook/widgets/enum_chips_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

void main() {
  group('countChipsInRows - 模拟换行计数', () {
    test('空列表返回 0', () {
      expect(countChipsInRows(labels: [], maxRows: 2, maxWidth: 318, style: _style), 0);
    });

    test('一行放得下时返回全部', () {
      expect(countChipsInRows(labels: ['短', '更短'], maxRows: 2, maxWidth: 318, style: _style), 2);
    });

    test('两行裁剪：300px 下 11 项购物枚举返回 6（第 7 项起换到第三行被折叠）', () {
      final labels = ['生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居', '美妆个护', '母婴', '运动户外', '书籍文具', '药品保健', '其他'];
      expect(countChipsInRows(labels: labels, maxRows: 2, maxWidth: 300, style: _style), 6);
    });

    test('maxRows=1 时只返回第一行数量', () {
      final labels = ['生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居'];
      expect(countChipsInRows(labels: labels, maxRows: 1, maxWidth: 300, style: _style), 3);
    });
  });

  testWidgets('EnumChipsField 折叠态显示展开按钮，点击展开后收起', (tester) async {
    final values = ['生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居', '美妆个护', '母婴', '运动户外', '书籍文具', '药品保健', '其他'];
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 318,
          child: EnumChipsField(
            values: values,
            selected: '生鲜食品',
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    ));
    expect(find.textContaining('展开全部'), findsOneWidget);
    // 点击未折叠的「日用品」触发回调
    await tester.tap(find.text('日用品'));
    expect(picked, '日用品');
    // 展开
    await tester.tap(find.textContaining('展开全部'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('药品保健'), findsOneWidget);
  });
}
```

运行：`flutter test test/enum_chips_field_test.dart -v`
Expected: FAIL（文件不存在 / countChipsInRows 未定义）

- [ ] **Step 2: `lib/models/dictionary.dart` 追加购物项类型枚举**

```dart
/// 购物项类型（单选，默认「其他」；与语音解析共用一套取值）。
const List<String> kShoppingItemTypes = <String>[
  '生鲜食品',
  '日用品',
  '服饰鞋包',
  '数码家电',
  '家居',
  '美妆个护',
  '母婴',
  '运动户外',
  '书籍文具',
  '药品保健',
  '其他',
];
```

- [ ] **Step 3: 实现 `lib/modules/notebook/widgets/enum_chips_field.dart`**

```dart
import 'dart:math';

import 'package:flutter/material.dart';

/// 枚举 chip 折叠组件：子项多时最多展示 [maxRows] 行，其余折叠可展开。
///
/// 折叠态用固定高度裁剪 + 底部渐隐 + 「展开全部（N）」按钮；展开态展示全部
/// 并显示「收起」。依赖 [countChipsInRows] 纯函数计算可见数量。
class EnumChipsField extends StatefulWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;
  final int maxRows;

  const EnumChipsField({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.maxRows = 2,
  });

  @override
  State<EnumChipsField> createState() => _EnumChipsFieldState();
}

class _EnumChipsFieldState extends State<EnumChipsField> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final visibleCount = countChipsInRows(
        labels: widget.values,
        maxRows: widget.maxRows,
        maxWidth: constraints.maxWidth,
        style: style,
      );
      final showToggle = visibleCount < widget.values.length;
      final shown = _expanded ? widget.values : widget.values.take(visibleCount).toList();
      const rowHeight = 38.0; // chip 高（padding 9*2 + 行高 20）
      const gap = 8.0;
      final chips = [
        for (final v in shown)
          _chip(v, style, scheme, () => widget.onChanged(v)),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              if (_expanded)
                Wrap(spacing: gap, runSpacing: gap, children: chips)
              else
                SizedBox(
                  height: rowHeight * widget.maxRows + gap * (widget.maxRows - 1),
                  child: ClipRect(
                    child: OverflowBox(
                      maxHeight: double.infinity,
                      alignment: Alignment.topCenter,
                      child: Wrap(spacing: gap, runSpacing: gap, children: chips),
                    ),
                  ),
                ),
              if (!_expanded)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 26,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [scheme.surface.withValues(alpha: 0), scheme.surface],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (showToggle)
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(
                _expanded ? '收起' : '展开全部（${widget.values.length - visibleCount}）',
              ),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: const Size(0, 40),
              ),
            ),
        ],
      );
    });
  }

  Widget _chip(String label, TextStyle style, ColorScheme scheme, VoidCallback onTap) {
    final active = label == widget.selected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: style.copyWith(
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 模拟换行：返回前 [maxRows] 行能容纳的 chip 数量。
///
/// chip 宽度 = 文本宽度 + 左右 padding；行内间距 [gap]。放不下即换行，
/// 换行数达到 [maxRows] 后停止计数（后续视为被折叠）。
int countChipsInRows({
  required List<String> labels,
  required int maxRows,
  required double maxWidth,
  required TextStyle style,
  double horizontalPadding = 14,
  double gap = 8,
}) {
  if (labels.isEmpty || maxRows <= 0) return 0;
  var rows = 1;
  var count = 0;
  var lineWidth = 0.0;
  for (final label in labels) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + horizontalPadding * 2;
    if (lineWidth > 0 && lineWidth + gap + w > maxWidth) {
      rows++;
      if (rows > maxRows) break;
      lineWidth = 0;
    }
    lineWidth += (lineWidth == 0 ? 0 : gap) + w;
    count++;
  }
  return min(count, labels.length);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/enum_chips_field_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/dictionary.dart lib/modules/notebook/widgets/enum_chips_field.dart test/enum_chips_field_test.dart && git commit -m "feat: 购物项类型枚举字典 + 枚举折叠组件（两行裁剪可展开）"
```

---

### Task 3: 购物项抽屉（枚举折叠 + 金额 + 日期选择器）

**Files:**
- Create: `lib/modules/notebook/widgets/shopping_item_sheet.dart`
- Modify: `test/notebook_ui_test.dart`

**Interfaces:**
- Consumes: `EnumChipsField`（Task 2）、`DateField`、`ConfirmDialog`、`NotebookStore`、`kShoppingItemTypes`。
- Produces: `Future<void> showShoppingItemSheet(BuildContext context, {required NotebookStore store, required String cartId, NotebookShopping? item})`（Task 4 的子页 FAB 与条目点击均依赖此接口）

- [ ] **Step 1: 写失败测试（追加到 `test/notebook_ui_test.dart`，宿主按钮方式独立验证）**

```dart
  testWidgets('购物项抽屉：金额/类型/日期保存、折叠展开、金额非法拦截', (tester) async {
    await pump(tester, Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                showShoppingItemSheet(context, store: store, cartId: 'c1'),
            child: const Text('打开抽屉'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    // 枚举折叠态：展开按钮存在
    expect(find.textContaining('展开全部'), findsOneWidget);
    // 输入名称与金额
    await tester.enterText(find.byType(TextField).at(0), '三文鱼');
    await tester.enterText(find.byType(TextField).at(1), '36');
    // 选择类型（默认选中「其他」，先展开再点「生鲜食品」）
    await tester.tap(find.textContaining('展开全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生鲜食品'));
    // 日期字段点击会弹系统选择器，跳过（DateField 已有独立测试）
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final saved = store.shopping.single;
    expect(saved.item, '三文鱼');
    expect(saved.price, 36);
    expect(saved.category, '生鲜食品');
    // 非法金额：负数拦截，不新增
    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '酸奶');
    await tester.enterText(find.byType(TextField).at(1), '-5');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.shopping, hasLength(1));
    expect(find.textContaining('金额'), findsWidgets); // 就近错误提示
  });
```

运行：`flutter test test/notebook_ui_test.dart -v`
Expected: FAIL（showShoppingItemSheet 不存在）

- [ ] **Step 2: 实现 `shopping_item_sheet.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../models/dictionary.dart';
import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../../widgets/confirm_dialog.dart';
import '../widgets/enum_chips_field.dart';
import '../widgets/notebook_shared.dart';

/// 购物项新建/编辑底部抽屉：物品名 + 实付金额 + 类型枚举（折叠）+ 日期选择器 + 备注。
///
/// 金额非法（空/负数）时就近提示不保存；编辑态底部追加「删除」。
Future<void> showShoppingItemSheet(
  BuildContext context, {
  required NotebookStore store,
  required String cartId,
  NotebookShopping? item,
}) async {
  final nameCtrl = TextEditingController(text: item?.item ?? '');
  final priceCtrl =
      TextEditingController(text: item == null ? '' : _trimPrice(item!.price));
  final noteCtrl = TextEditingController(text: item?.note ?? '');
  var category = item?.category ?? '其他';
  var date = item?.date ?? '';
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 14,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(item == null ? '添加购物项' : '编辑购物项',
                    style: Theme.of(ctx).textTheme.titleLarge)),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '物品名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '实付金额',
                  prefixText: '¥ ',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              Text('类型', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              EnumChipsField(
                values: kShoppingItemTypes,
                selected: category,
                onChanged: (v) => setSheetState(() => category = v),
              ),
              const SizedBox(height: 12),
              DateField(
                label: '日期（可选）',
                value: date,
                onChanged: (v) => setSheetState(() => date = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '如：超市买的 · 已付现金',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final price = num.tryParse(priceCtrl.text.trim());
                  if (name.isEmpty) {
                    setSheetState(() => error = '请输入物品名称');
                    return;
                  }
                  if (price == null || price < 0) {
                    setSheetState(() => error = '请输入有效金额（不小于 0）');
                    return;
                  }
                  final entity = NotebookShopping(
                    id: item?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    item: name,
                    price: price,
                    category: category,
                    note: noteCtrl.text.trim(),
                    cartId: cartId,
                    date: date,
                    createdAt: item?.createdAt ?? DateTime.now(),
                  );
                  if (item == null) {
                    store.addShopping(entity);
                  } else {
                    store.updateShopping(entity);
                  }
                  Navigator.of(ctx).pop();
                },
                child: const Text('保存'),
              ),
              if (item != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      ctx, '删除购物项', '删除「${item!.item}」？', '删除',
                    );
                    if (ok) {
                      await store.deleteShopping(item!.id);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    }
                  },
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(ctx).colorScheme.error),
                  child: const Text('删除'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// 金额回填：整数不带小数点，小数保留两位。
String _trimPrice(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
```

- [ ] **Step 3: 跑测试**

Run: `flutter test test/notebook_ui_test.dart test/enum_chips_field_test.dart -v`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/modules/notebook/widgets/shopping_item_sheet.dart test/notebook_ui_test.dart && git commit -m "feat: 购物项抽屉（枚举折叠/金额校验/日期选择器）"
```

---

### Task 4: 购物车列表屏重构（车列表 → 子页）+ 购物车抽屉

**Files:**
- Rewrite: `lib/modules/notebook/screens/shopping_screen.dart`
- Create: `lib/modules/notebook/screens/shopping_cart_detail_screen.dart`
- Create: `lib/modules/notebook/widgets/shopping_cart_sheet.dart`
- Modify: `lib/modules/notebook/widgets/notebook_shared.dart`（追加 `formatYuan` 纯函数）
- Modify: `test/notebook_ui_test.dart`（购物用例重写 + 新增）

**Interfaces:**
- Consumes: `NotebookStore`（shoppingCarts/shopping/cartsOf/addCart/updateCart/deleteCart），`NotebookEmptyState`、`ConfirmDialog`、`DateField` 等既有组件。
- Produces:
  - `String formatYuan(num v)` → `'¥${v.toStringAsFixed(2)}'`（notebook_shared.dart）
  - `String defaultCartTitle(DateTime d)` → `DateFormat('yyyy年MM月dd日').format(d)`（放 shopping_cart_sheet.dart，导出便于测试）
  - `Future<void> showShoppingCartSheet(BuildContext context, {required NotebookStore store, NotebookShoppingCart? cart})`
  - `class ShoppingCartDetailScreen extends StatefulWidget { final NotebookStore store; final String cartId; }`
  - `ShoppingScreen` 新结构：AppBar（标题 + `Icons.insert_chart_outlined` 报表入口）、车列表行（单行）、「未分组」行（有数据才显示）、FAB 新建、空态

- [ ] **Step 1: 写失败 widget 测试（重写 `test/notebook_ui_test.dart` 购物用例）**

在既有 `购物：新建购物车与添加购物项` 用例位置替换为：

```dart
  testWidgets('购物车列表：单行记录、新建抽屉默认日期标题、点行进子页', (tester) async {
    await store.addCart(NotebookShoppingCart(
      id: 'c1', name: '周末生鲜大采购', note: null, createdAt: DateTime(2026, 8, 5, 10),
    ));
    await store.addShopping(NotebookShopping(
      id: 'i1', item: '牛奶', price: 9.5, category: '生鲜食品',
      note: '', cartId: 'c1', date: '2026-08-05', createdAt: DateTime(2026, 8, 5, 10),
    ));
    await pump(tester, ShoppingScreen(store: store));
    // 车行单行元信息：实付 ¥9.50 · 1 项
    expect(find.text('周末生鲜大采购'), findsOneWidget);
    expect(find.textContaining('¥9.50'), findsOneWidget);
    // 新建购物车抽屉：标题默认今天 yyyy年MM月dd日
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日'), findsWidgets);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    // 点车行进子页
    await tester.tap(find.text('周末生鲜大采购'));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingCartDetailScreen), findsOneWidget);
    expect(find.text('牛奶'), findsOneWidget);
  });

  testWidgets('购物车抽屉：编辑标题保存、删除购物车回收未分组', (tester) async {
    await store.addCart(NotebookShoppingCart(
      id: 'c1', name: '旧标题', note: null, createdAt: DateTime(2026, 8, 5, 10),
    ));
    await store.addShopping(NotebookShopping(
      id: 'i1', item: '苹果', price: 5, category: '生鲜食品',
      note: '', cartId: 'c1', date: '', createdAt: DateTime(2026, 8, 5, 10),
    ));
    await pump(tester, ShoppingScreen(store: store));
    // 进入子页 → 编辑抽屉
    await tester.tap(find.text('旧标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新标题');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.shoppingCarts.single.name, '新标题');
    // 再次编辑 → 删除购物车
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除购物车'));
    await tester.pumpAndSettle();
    expect(store.shoppingCarts, isEmpty);
    expect(store.shopping.single.cartId, '');
  });
```

`购物报表入口打开并渲染` 用例改为断言新报表屏（Task 5 交付前暂改为 tap 后 `find.byType(ShoppingTrendScreen)` 会失败——将该用例移动到 Task 5 再改，本任务先删除该用例并在 Task 5 恢复；或在 Task 5 Step 3 一并更新）。

运行：`flutter test test/notebook_ui_test.dart -v`
Expected: FAIL（ShoppingScreen 尚无抽屉/子页，编译或断言失败）

- [ ] **Step 2: `notebook_shared.dart` 追加金额格式化**

```dart
/// 金额展示：¥ + 两位小数（购物/报表共用）。
String formatYuan(num v) => '¥${v.toStringAsFixed(2)}';
```

- [ ] **Step 3: 实现 `shopping_cart_sheet.dart`（新建/编辑购物车抽屉）**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../../widgets/confirm_dialog.dart';

/// 购物车新建/编辑底部抽屉。
///
/// 新建时标题默认当天 yyyy年MM月dd日；点日历图标唤起日期选择器，选中后标题
/// 联动为该日期；编辑态底部追加「删除购物车」危险按钮（删除前二次确认，
/// 其下购物项由外键 SET NULL 回收为未分组）。
Future<void> showShoppingCartSheet(
  BuildContext context, {
  required NotebookStore store,
  NotebookShoppingCart? cart,
}) async {
  final created = cart ?? NotebookShoppingCart(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    name: defaultCartTitle(DateTime.now()),
    createdAt: DateTime.now(),
  );
  final controller = TextEditingController(text: created.name);
  final noteController = TextEditingController(text: created.note ?? '');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 14,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(cart == null ? '新建购物车' : '编辑购物车',
                  style: Theme.of(ctx).textTheme.titleLarge)),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTitleField(ctx, controller),
          const SizedBox(height: 8),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(labelText: '备注（可选）', hintText: '如：楼下超市 · 手机支付'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final updated = NotebookShoppingCart(
                id: created.id,
                name: name,
                note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                createdAt: created.createdAt,
              );
              if (cart == null) {
                store.addCart(updated);
              } else {
                store.updateCart(updated);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
          if (cart != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                final ok = await ConfirmDialog.show(
                  ctx, '删除购物车',
                  '删除「${cart!.name}」，其下购物项将回收为未分组', '删除',
                );
                if (ok) {
                  await store.deleteCart(cart!.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }
              },
              style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('删除购物车'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 标题字段：文本框 + 日历图标（日期选择器联动标题）。
Widget _buildTitleField(BuildContext context, TextEditingController controller) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: '标题',
      suffixIcon: IconButton(
        icon: const Icon(Icons.calendar_today_outlined),
        tooltip: '选日期',
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (picked != null) {
            controller.text = defaultCartTitle(picked);
          }
        },
      ),
    ),
  );
}

/// 购物车默认标题：yyyy年MM月dd日。
String defaultCartTitle(DateTime d) => DateFormat('yyyy年MM月dd日').format(d);
```

注意：id 与 `notebook_shared.dart` 的 `notebookNewId()` 风格对齐，用 `DateTime.now().microsecondsSinceEpoch.toString()`；抽屉保存/关闭后不 pop 外层页面（列表页监听 store 自动刷新，子页监听 store 实时更新），由调用方决定是否返回。

- [ ] **Step 4: 实现 `shopping_cart_detail_screen.dart`（子页）**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../widgets/notebook_shared.dart';
import '../widgets/shopping_cart_sheet.dart';
import '../widgets/shopping_item_sheet.dart';

/// 子购物车子页：返回 + 车名 + 编辑入口 + 汇总卡 + 购物项列表。
///
/// 购物车可能被编辑（名称变化），故本页监听 store，按 [cartId] 实时取最新车。
class ShoppingCartDetailScreen extends StatefulWidget {
  final NotebookStore store;
  final String cartId;

  const ShoppingCartDetailScreen({
    super.key,
    required this.store,
    required this.cartId,
  });

  @override
  State<ShoppingCartDetailScreen> createState() => _ShoppingCartDetailScreenState();
}

class _ShoppingCartDetailScreenState extends State<ShoppingCartDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final carts = widget.store.shoppingCarts.where((c) => c.id == widget.cartId).toList();
    if (carts.isEmpty) {
      // 购物车已被删除：回退到列表
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    final cart = carts.first;
    final items = widget.store.cartsOf(cart.id);
    final total = items.fold<num>(0, (s, i) => s + i.price);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(cart.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑购物车',
            onPressed: () => showShoppingCartSheet(context, store: widget.store, cart: cart),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showShoppingItemSheet(context, store: widget.store, cartId: cart.id),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(context, total, items.length, cart.createdAt),
          const SizedBox(height: 18),
          Text('购物项（${items.length}）', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final it in items) _itemTile(context, it),
          if (items.isEmpty)
            const NotebookEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: '这个购物车还没有条目',
              subtitle: '点右下角 + 添加购物项',
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, num total, int count, DateTime createdAt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Text(formatYuan(total),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const Spacer(),
          _sumItem('$count', '条目'),
          const SizedBox(width: 18),
          _sumItem(DateFormat('M月d日').format(createdAt), '创建'),
        ],
      ),
    );
  }

  Widget _sumItem(String v, String k) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(k, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _itemTile(BuildContext context, NotebookShopping it) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.shopping_bag_outlined, size: 20),
        ),
        title: Text(it.item, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${it.category.isEmpty ? '未分类' : it.category} · ${it.date.isEmpty ? '未记录日期' : it.date}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(formatYuan(it.price),
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        onTap: () => showShoppingItemSheet(context, store: widget.store, cartId: it.cartId, item: it),
      ),
    );
  }
}
```

- [ ] **Step 5: 重写 `shopping_screen.dart`（车列表）**

`ShoppingScreen` 的 build 替换为以下结构（保留 StatefulWidget + store 监听；AppBar 报表入口 push ShoppingTrendScreen；列表按 createdAt 降序）：

```dart
  @override
  Widget build(BuildContext context) {
    final carts = [...widget.store.shoppingCarts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ungrouped = widget.store.shopping.where((i) => i.cartId.isEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('购物清单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insert_chart_outlined),
            tooltip: '消费趋势',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ShoppingTrendScreen(store: widget.store)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showShoppingCartSheet(context, store: widget.store),
        child: const Icon(Icons.add),
      ),
      body: carts.isEmpty && ungrouped.isEmpty
          ? const NotebookEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: '还没有购物车',
              subtitle: '点右下角新建购物车，标题默认当天日期',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final cart in carts) _cartRow(context, cart),
                if (ungrouped.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _cartRow(context, _ungroupedPseudo(cartId: '', ungrouped: ungrouped)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.info_outline, size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('删除购物车后，其下购物项自动回收至此「未分组」',
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                ],
              ],
            ),
    );
  }
```

`_cartRow` 完整实现（单行标题 + 单行 meta + chevron，整行进子页；`[items]` 用于聚合实付/条数，未分组伪行传入 ungrouped 列表并显示「零散记录」）：

```dart
  Widget _cartRow(BuildContext context, NotebookShoppingCart cart,
      List<NotebookShopping> items) {
    final total = items.fold<num>(0, (s, i) => s + i.price);
    final metaTime =
        cart.id.isEmpty ? '零散记录' : DateFormat('M月d日').format(cart.createdAt);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShoppingCartDetailScreen(
            store: widget.store,
            cartId: cart.id,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cart.id.isEmpty
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              cart.id.isEmpty
                  ? Icons.folder_outlined
                  : Icons.shopping_bag_outlined,
              size: 20,
              color: cart.id.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cart.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  '实付 ${formatYuan(total)} · ${items.length} 项 · $metaTime',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  /// 未分组伪车行：items 为未分组购物项。
  Widget _ungroupedPseudoRow(
      BuildContext context, List<NotebookShopping> ungrouped) {
    return _cartRow(
      context,
      NotebookShoppingCart(
        id: '',
        name: '未分组',
        createdAt: DateTime(2000),
        note: null,
      ),
      ungrouped,
    );
  }
```

列表 children 中未分组部分改为 `_ungroupedPseudoRow(context, ungrouped)`（替代原 `_ungroupedPseudo(cartId: '', ungrouped: ungrouped)` 调用）。

文件顶部补 import：`package:intl/intl.dart`（DateFormat）、`../../../models/notebook_shopping.dart`（NotebookShoppingCart）、`../widgets/notebook_shared.dart`（formatYuan/NotebookEmptyState）、`../widgets/shopping_cart_sheet.dart`、`../widgets/shopping_item_sheet.dart`（showShoppingItemSheet）、`shopping_cart_detail_screen.dart`、`shopping_trend_screen.dart`。

- [ ] **Step 6: 跑测试**

Run: `flutter test test/notebook_ui_test.dart test/date_field_test.dart -v`
Expected: 购物相关用例 PASS（报表入口用例本任务暂删，Task 5 恢复）

- [ ] **Step 7: Commit**

```bash
git add lib/modules/notebook/ test/notebook_ui_test.dart && git commit -m "feat: 购物车列表重构（单行车列表+子页）+ 新建/编辑购物车抽屉"
```

---


### Task 5: 购物消费趋势报表（分类占比饼图 + 天/月/年 + 禁未来）

**Files:**
- Create: `lib/modules/notebook/screens/shopping_trend_screen.dart`
- Modify: `test/notebook_ui_test.dart`（恢复报表入口用例）
- Test: `test/shopping_trend_test.dart`（新建，纯函数 + widget）

**Interfaces:**
- Consumes: `NotebookStore.shopping`（price/category/date）、`formatYuan`、`NotebookEmptyState`、`AppTheme`。
- Produces:
  - `enum ShoppingPeriod { day, month, year }`
  - `DateTime periodStart(DateTime d, ShoppingPeriod p)`
  - `DateTime shiftPeriod(DateTime d, ShoppingPeriod p, int delta)`
  - `bool isCurrentPeriod(DateTime anchor, ShoppingPeriod p, {DateTime? now})`
  - `String periodLabel(DateTime anchor, ShoppingPeriod p)`（day `yyyy年M月d日` / month `yyyy年M月` / year `yyyy年`）
  - `class CategorySlice { final String label; final num value; final double percent; final Color color; }`
  - `List<CategorySlice> buildCategorySlices(List<NotebookShopping> items, DateTime anchor, ShoppingPeriod p, {DateTime? now})`
  - `Color shoppingCategoryColor(String category)`
  - `class ShoppingTrendScreen extends StatefulWidget { final NotebookStore store; }`

- [ ] **Step 1: 写失败测试 `test/shopping_trend_test.dart`**

```dart
// 购物消费趋势报表测试：周期聚合、禁未来、饼图扇区、UI 渲染
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/modules/notebook/screens/shopping_trend_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_notebook_store.dart';

NotebookShopping _item(String id, String category, num price, String date) =>
    NotebookShopping(
      id: id, item: id, price: price, category: category,
      note: '', cartId: '', date: date, createdAt: DateTime(2026, 8, 1),
    );

void main() {
  group('buildCategorySlices - 周期聚合', () {
    test('按月：只统计锚点所在月，按分类聚合且降序', () {
      final anchor = DateTime(2026, 8, 1);
      final items = [
        _item('a', '生鲜食品', 100, '2026-08-05'),
        _item('b', '日用品', 50, '2026-08-06'),
        _item('c', '生鲜食品', 30, '2026-08-07'),
        _item('d', '生鲜食品', 999, '2026-07-31'), // 上月，排除
      ];
      final slices = buildCategorySlices(items, anchor, ShoppingPeriod.month);
      expect(slices[0].label, '生鲜食品');
      expect(slices[0].value, 130);
      expect(slices[0].percent, closeTo(130 / 180, 0.0001));
      expect(slices[1].label, '日用品');
      expect(slices[1].value, 50);
    });

    test('空 date 视为今日；空/未知分类归入「其他」', () {
      final now = DateTime.now();
      final anchor = periodStart(now, ShoppingPeriod.month);
      final items = [
        _item('a', '', 20, ''), // 今日 + 无分类
        _item('b', '不存在分类', 10, ''),
      ];
      final slices = buildCategorySlices(items, anchor, ShoppingPeriod.month, now: now);
      expect(slices, hasLength(1));
      expect(slices.single.label, '其他');
      expect(slices.single.value, 30);
    });

    test('周期为空返回空列表', () {
      final slices = buildCategorySlices([], DateTime(2026, 8, 1), ShoppingPeriod.month);
      expect(slices, isEmpty);
    });
  });

  group('周期导航与禁未来', () {
    test('isCurrentPeriod：今天/本月/今年为当前周期', () {
      final now = DateTime(2026, 8, 6, 15);
      expect(isCurrentPeriod(DateTime(2026, 8, 6), ShoppingPeriod.day, now: now), isTrue);
      expect(isCurrentPeriod(DateTime(2026, 8, 1), ShoppingPeriod.month, now: now), isTrue);
      expect(isCurrentPeriod(DateTime(2026, 1, 1), ShoppingPeriod.year, now: now), isTrue);
    });

    test('shiftPeriod 越过当前周期时（下个月）isCurrentPeriod 为 false → UI 禁用右箭头', () {
      final now = DateTime(2026, 8, 6);
      final next = shiftPeriod(periodStart(now, ShoppingPeriod.month), ShoppingPeriod.month, 1);
      expect(isCurrentPeriod(next, ShoppingPeriod.month, now: now), isFalse);
    });
  });

  testWidgets('报表 UI：图例渲染、按月切换、右箭头禁用、空态', (tester) async {
    final store = FakeNotebookStore();
    await store.addShopping(_item('a', '生鲜食品', 100, '2026-08-05'));
    await store.addShopping(_item('b', '日用品', 50, '2026-08-06'));
    await tester.pumpWidget(MaterialApp(home: ShoppingTrendScreen(store: store)));
    expect(find.text('生鲜食品'), findsWidgets);
    expect(find.text('¥100.00'), findsWidgets);
    // 右箭头禁用（当前月）
    final nextBtn = tester.widget<IconButton>(find.byTooltip('下一周期'));
    expect(nextBtn.onPressed, isNull);
    // 切到按天，字段标签变化
    await tester.tap(find.text('按天'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月${now.day}日'), findsOneWidget);
  });
}
```

运行：`flutter test test/shopping_trend_test.dart -v`
Expected: FAIL

- [ ] **Step 2: 实现 `shopping_trend_screen.dart`**

核心（完整文件）：

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/notebook_shopping.dart';
import '../../../services/notebook_store.dart';
import '../../../theme/app_theme.dart';
import '../widgets/notebook_shared.dart';

/// 报表周期粒度（天 / 月 / 年，无按周）。
enum ShoppingPeriod { day, month, year }

/// 周期起点：按粒度截断（天=当天 0 点，月=1 日，年=1 月 1 日）。
DateTime periodStart(DateTime d, ShoppingPeriod p) => switch (p) {
      ShoppingPeriod.day => DateTime(d.year, d.month, d.day),
      ShoppingPeriod.month => DateTime(d.year, d.month, 1),
      ShoppingPeriod.year => DateTime(d.year, 1, 1),
    };

/// 平移 [delta] 个周期（Dart 自动处理月/年进位溢出）。
DateTime shiftPeriod(DateTime d, ShoppingPeriod p, int delta) => switch (p) {
      ShoppingPeriod.day => DateTime(d.year, d.month, d.day + delta),
      ShoppingPeriod.month => DateTime(d.year, d.month + delta, 1),
      ShoppingPeriod.year => DateTime(d.year + delta, 1, 1),
    };

/// 是否为当前周期（用于禁用「下一周期」按钮与选择器未来项）。
bool isCurrentPeriod(DateTime anchor, ShoppingPeriod p, {DateTime? now}) =>
    periodStart(anchor, p) == periodStart(now ?? DateTime.now(), p);

/// 周期标签：按天 yyyy年M月d日 / 按月 yyyy年M月 / 按年 yyyy年。
String periodLabel(DateTime anchor, ShoppingPeriod p) => switch (p) {
      ShoppingPeriod.day => DateFormat('yyyy年M月d日').format(anchor),
      ShoppingPeriod.month => DateFormat('yyyy年M月').format(anchor),
      ShoppingPeriod.year => DateFormat('yyyy年').format(anchor),
    };

/// 分类占比切片（聚合 + 降序 + 配色）。
class CategorySlice {
  final String label;
  final num value;
  final double percent;
  final Color color;
  const CategorySlice({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
  });
}

/// 把购物项按 [anchor] 所在周期过滤，按分类聚合 price 并降序。
List<CategorySlice> buildCategorySlices(
  List<NotebookShopping> items,
  DateTime anchor,
  ShoppingPeriod p, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final start = periodStart(anchor, p);
  final end = shiftPeriod(start, p, 1);
  final sums = <String, num>{};
  for (final it in items) {
    final ds = it.date.isEmpty ? DateFormat('yyyy-MM-dd').format(today) : it.date;
    final dt = DateTime.tryParse(ds);
    if (dt == null || dt.isBefore(start) || !dt.isBefore(end)) continue;
    final cat = it.category.trim().isEmpty ? '其他' : it.category.trim();
    sums[cat] = (sums[cat] ?? 0) + it.price;
  }
  final total = sums.values.fold<num>(0, (a, b) => a + b);
  final entries = sums.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in entries)
      CategorySlice(
        label: e.key,
        value: e.value,
        percent: total == 0 ? 0 : e.value / total,
        color: shoppingCategoryColor(e.key),
      ),
  ];
}

/// 分类固定调色板（暖平面语义色 + 中性扩展，未知分类落「其他」灰）。
const List<Color> _categoryPalette = [
  AppTheme.accent,
  AppTheme.warn,
  AppTheme.ok,
  AppTheme.danger,
  Color(0xFF8A8D85), // neutral
  Color(0xFF5B7FA6), // 蓝灰
  Color(0xFF8A6FAE), // 紫灰
  Color(0xFFB08A5B), // 棕
];

Color shoppingCategoryColor(String category) {
  if (category == '其他' || category.isEmpty) return _categoryPalette[4];
  const names = ['生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居', '美妆个护', '母婴', '运动户外', '书籍文具', '药品保健'];
  final i = names.indexOf(category);
  return _categoryPalette[i >= 0 ? i % _categoryPalette.length : 4];
}

/// 环形饼图 painter：按 percent 画扇区，中心挖孔。
class DonutPainter extends CustomPainter {
  final List<CategorySlice> slices;
  final Color holeColor;
  const DonutPainter(this.slices, {required this.holeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final holeRect = Rect.fromCircle(
      center: rect.center,
      radius: size.shortestSide * 0.23,
    );
    var start = -3.14159 / 2; // 12 点方向起
    for (final s in slices) {
      final sweep = s.percent * 2 * 3.14159;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = s.color);
      start += sweep;
    }
    canvas.drawCircle(rect.center, holeRect.width / 2, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(covariant DonutPainter old) =>
      old.slices != slices || old.holeColor != holeColor;
}
```

继续在同一文件追加：

```dart
/// 购物消费趋势报表页：分类占比饼图 + 按天/月/年 + 单一时间单位选择 + 禁未来。
///
/// 默认选中当前时间所在周期；切换粒度回到当前周期；右箭头在当前周期时禁用，
/// 选择器也不可选未来。
class ShoppingTrendScreen extends StatefulWidget {
  final NotebookStore store;
  const ShoppingTrendScreen({super.key, required this.store});

  @override
  State<ShoppingTrendScreen> createState() => _ShoppingTrendScreenState();
}

class _ShoppingTrendScreenState extends State<ShoppingTrendScreen> {
  ShoppingPeriod _p = ShoppingPeriod.month;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    _anchor = periodStart(DateTime.now(), _p);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => mounted ? setState(() {}) : null;

  /// 按当前粒度弹对应选择器（天=系统日历；月/年=自绘弹层），禁选未来。
  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    DateTime? picked;
    switch (_p) {
      case ShoppingPeriod.day:
        picked = await showDatePicker(
          context: context,
          initialDate: _anchor,
          firstDate: DateTime(2000),
          lastDate: now,
        );
      case ShoppingPeriod.month:
        picked = await showMonthPickerSheet(
          context: context,
          initial: _anchor,
          latest: periodStart(now, ShoppingPeriod.month),
        );
      case ShoppingPeriod.year:
        picked = await showYearPickerSheet(
          context: context,
          initial: _anchor,
          latest: periodStart(now, ShoppingPeriod.year),
        );
    }
    if (picked != null) setState(() => _anchor = periodStart(picked, _p));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slices = buildCategorySlices(widget.store.shopping, _anchor, _p);
    final total = slices.fold<num>(0, (s, x) => s + x.value);
    final itemCount =
        widget.store.shopping.where((it) => _inPeriod(it, _anchor, _p)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('购物消费趋势')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ShoppingPeriod>(
            segments: const [
              ButtonSegment(value: ShoppingPeriod.day, label: Text('按天')),
              ButtonSegment(value: ShoppingPeriod.month, label: Text('按月')),
              ButtonSegment(value: ShoppingPeriod.year, label: Text('按年')),
            ],
            selected: {_p},
            onSelectionChanged: (s) => setState(() {
              _p = s.first;
              _anchor = periodStart(DateTime.now(), _p);
            }),
          ),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(
              onPressed: () =>
                  setState(() => _anchor = shiftPeriod(_anchor, _p, -1)),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: '上一周期',
            ),
            Expanded(
              child: TextButton(
                onPressed: _pickPeriod,
                child: Text(
                  periodLabel(_anchor),
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              // 当前周期禁用「下一周期」，禁止进入未来统计
              onPressed: isCurrentPeriod(_anchor, _p)
                  ? null
                  : () =>
                      setState(() => _anchor = shiftPeriod(_anchor, _p, 1)),
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: '下一周期',
            ),
          ]),
          const SizedBox(height: 6),
          _summaryCard(context, total, itemCount, slices.length),
          const SizedBox(height: 14),
          if (slices.isEmpty)
            const NotebookEmptyState(
              icon: Icons.pie_chart_outline,
              title: '这一时期还没有数据',
              subtitle: '换个时间区间，或先记录一些条目。',
            )
          else
            _donutCard(context, slices, total, itemCount),
        ],
      ),
    );
  }

  /// 条目是否落在锚点所在周期（空 date 视为今日）。
  bool _inPeriod(NotebookShopping it, DateTime anchor, ShoppingPeriod p) {
    final today = DateTime.now();
    final ds =
        it.date.isEmpty ? DateFormat('yyyy-MM-dd').format(today) : it.date;
    final dt = DateTime.tryParse(ds);
    if (dt == null) return false;
    final start = periodStart(anchor, p);
    final end = shiftPeriod(start, p, 1);
    return !dt.isBefore(start) && dt.isBefore(end);
  }

  Widget _summaryCard(
      BuildContext context, num total, int itemCount, int catCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(children: [
        Text(formatYuan(total),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(width: 6),
        Text('本周期总花费',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const Spacer(),
        _sumItem('$itemCount', '条目'),
        const SizedBox(width: 18),
        _sumItem('$catCount', '分类'),
      ]),
    );
  }

  Widget _sumItem(String v, String k) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(v,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(k,
              style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _donutCard(BuildContext context, List<CategorySlice> slices, num total,
      int itemCount) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(children: [
        SizedBox(
          width: 216,
          height: 216,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: const Size(216, 216),
              painter: DonutPainter(slices, holeColor: scheme.surface),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(formatYuan(total),
                  style:
                      const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('$itemCount 项',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: s.color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text(formatYuan(s.value),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: Text('${(s.percent * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// 月份选择底部弹层：12 个月网格 + 年份左右切换；未来月份禁用。
Future<DateTime?> showMonthPickerSheet(
  BuildContext context, {
  required DateTime initial,
  required DateTime latest,
}) {
  var year = initial.year;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final latestMonth = year == latest.year ? latest.month : 12;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text('选择月份',
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: () => setSheetState(() => year--),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('$year 年',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed:
                    year >= latest.year ? null : () => setSheetState(() => year++),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  _pickerCell(
                    ctx,
                    '$m 月',
                    year < latest.year || m <= latestMonth,
                    () => Navigator.of(ctx).pop(DateTime(year, m)),
                  ),
              ],
            ),
          ]),
        );
      },
    ),
  );
}

/// 年份选择底部弹层：当前年往前 20 年网格（未来年份不出现）。
Future<DateTime?> showYearPickerSheet(
  BuildContext context, {
  required DateTime initial,
  required DateTime latest,
}) {
  final years = [for (var y = latest.year; y >= latest.year - 19; y--) y];
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('选择年份',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ]),
          const SizedBox(height: 8),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final y in years)
                _pickerCell(ctx, '$y 年', true,
                    () => Navigator.of(ctx).pop(DateTime(y))),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 选择器网格单元：可点/禁用两态。
Widget _pickerCell(
    BuildContext context, String label, bool enabled, VoidCallback onTap) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? scheme.surfaceContainerHighest
            : scheme.surface.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
```

- [ ] **Step 3: 恢复并更新 `test/notebook_ui_test.dart` 报表入口用例**

```dart
  testWidgets('购物报表入口打开并渲染饼图', (tester) async {
    await store.addShopping(NotebookShopping(
      id: 'i1', item: '牛奶', price: 9.5, category: '生鲜食品',
      note: '', cartId: '', date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      createdAt: DateTime(2026, 8, 1),
    ));
    await pump(tester, ShoppingScreen(store: store));
    await tester.tap(find.byIcon(Icons.insert_chart_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingTrendScreen), findsOneWidget);
    expect(find.text('生鲜食品'), findsWidgets);
  });
```

（补 `import 'package:intl/intl.dart';`；删除原 `find.byIcon(Icons.bar_chart)` + `ReportScreen` 旧断言。）

- [ ] **Step 4: 跑测试**

Run: `flutter test test/shopping_trend_test.dart test/notebook_ui_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/modules/notebook/screens/shopping_trend_screen.dart test/shopping_trend_test.dart test/notebook_ui_test.dart && git commit -m "feat: 购物消费趋势报表（分类占比饼图/天月年/禁未来）"
```

---

### Task 6: 全量验证 + 收尾

**Files:** 全部改动文件。

- [ ] **Step 1: 静态检查**

Run: `flutter analyze`
Expected: 0 error（存量 info/警告可保留，但不得新增 error）

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 全量 PASS（任务模块 327 用例 + 购物新增用例全部绿）

- [ ] **Step 3: 死代码自查**

- `ReportScreen`/`StatsReport` 仍被 `LedgerScreen` 使用 → 保留。
- `expectedPrice`/`expected_price`/`actual_price` 引用全仓搜索 `rg "expectedPrice|expected_price|actual_price|actualPrice" lib test`：仅允许出现在 `notebook_shopping.dart` fromJson 兼容读取与迁移测试/旧数据 fixture 中；其余全部清除。
- 旧购物 UI 的 `_promptText`/`_promptItem`/`Icons.bar_chart` 引用确认无残留。

- [ ] **Step 4: 更新规格文档验证方式为「已实现」**

`docs/superpowers/specs/2026-08-06-shopping-module-design.md` 末尾追加一行：`> 实现状态：2026-08-07 落地，flutter analyze 0 error + flutter test 全量绿。`

- [ ] **Step 5: Commit**

```bash
git add -A -- lib test docs/superpowers/specs/2026-08-06-shopping-module-design.md && git commit -m "feat: 购物清单模块整改落地（表v4/层级重构/抽屉表单/饼图报表）"
```

提交前 `git status` 核对：不得包含工作区他人未提交文件（`.gitignore`、`lib/services/audio_capture_io.dart`、`test/pcm_resampler_test.dart`、平台生成文件等）。
