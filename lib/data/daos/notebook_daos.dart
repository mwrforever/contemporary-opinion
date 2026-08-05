import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/notebook_ledger.dart';
import '../../models/notebook_reading.dart';
import '../../models/notebook_recipe.dart';
import '../../models/notebook_shopping.dart';
import '../../models/notebook_study.dart';
import '../../models/notebook_trip.dart';
import '../database_helper.dart';

/// 记事本 DAO 公共基座：统一连接获取。
abstract class _BaseNotebookDao {
  _BaseNotebookDao({Database? db}) : _db = db;

  final Database? _db;

  Future<Database> get _database async =>
      _db ?? DatabaseHelper.instance.database;
}

/// 购物 DAO：购物车 + 购物项（删购物车自动回收项为未分组，靠外键 SET NULL）。
class ShoppingDao extends _BaseNotebookDao {
  ShoppingDao({super.db});

  Future<void> insertCart(NotebookShoppingCart cart, {required int userId}) async {
    final j = cart.toJson();
    await (await _database).insert('shopping_carts', {
      'id': cart.id,
      'user_id': userId,
      'name': cart.name,
      'note': cart.note,
      'created_at': j['createdAt'],
    });
  }

  Future<void> updateCart(NotebookShoppingCart cart) async {
    await (await _database).update(
      'shopping_carts',
      {'name': cart.name, 'note': cart.note},
      where: 'id = ?',
      whereArgs: [cart.id],
    );
  }

  Future<void> deleteCart(String id) async {
    await (await _database).delete(
      'shopping_carts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<NotebookShoppingCart>> listCarts(int userId) async {
    final rows = await (await _database).query(
      'shopping_carts',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final r in rows)
        NotebookShoppingCart.fromJson({
          'id': r['id'],
          'name': r['name'],
          'note': r['note'],
          'createdAt': r['created_at'],
        }),
    ];
  }

  Future<void> insertItem(
    NotebookShopping item, {
    required int userId,
  }) async {
    final j = item.toJson();
    await (await _database).insert('shopping_items', {
      'id': item.id,
      'user_id': userId,
      'cart_id': item.cartId.isEmpty ? null : item.cartId,
      'item': item.item,
      'expected_price': item.expectedPrice,
      'actual_price': item.actualPrice,
      'category': item.category,
      'note': item.note,
      'date': item.date,
      'created_at': j['createdAt'],
    });
  }

  Future<void> updateItem(NotebookShopping item) async {
    await (await _database).update(
      'shopping_items',
      {
        'cart_id': item.cartId.isEmpty ? null : item.cartId,
        'item': item.item,
        'expected_price': item.expectedPrice,
        'actual_price': item.actualPrice,
        'category': item.category,
        'note': item.note,
        'date': item.date,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteItem(String id) async {
    await (await _database).delete(
      'shopping_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 按购物车列出项；[cartId] 为 null 表示「未分组」
  Future<List<NotebookShopping>> listItems(
    int userId, {
    String? cartId,
  }) async {
    final db = await _database;
    final rows = cartId == null
        ? await db.query(
            'shopping_items',
            where: 'user_id = ? AND cart_id IS NULL',
            whereArgs: [userId],
            orderBy: 'created_at ASC',
          )
        : await db.query(
            'shopping_items',
            where: 'user_id = ? AND cart_id = ?',
            whereArgs: [userId, cartId],
            orderBy: 'created_at ASC',
          );
    return [
      for (final r in rows)
        NotebookShopping.fromJson({
          'id': r['id'],
          'item': r['item'],
          'expectedPrice': r['expected_price'],
          'actualPrice': r['actual_price'],
          'category': r['category'],
          'note': r['note'],
          'cartId': r['cart_id'] ?? '',
          'date': r['date'],
          'createdAt': r['created_at'],
        }),
    ];
  }
}

/// 收支账本 DAO
class LedgerDao extends _BaseNotebookDao {
  LedgerDao({super.db});

  Future<void> insert(NotebookLedger item, {required int userId}) async {
    await (await _database).insert('ledger', {
      'id': item.id,
      'user_id': userId,
      'title': item.title,
      'kind': item.kind,
      'amount': item.amount,
      'category': item.category,
      'date': item.date,
      'note': item.note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> update(NotebookLedger item) async {
    await (await _database).update(
      'ledger',
      {
        'title': item.title,
        'kind': item.kind,
        'amount': item.amount,
        'category': item.category,
        'date': item.date,
        'note': item.note,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> delete(String id) async {
    await (await _database).delete('ledger', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NotebookLedger>> listByUser(int userId) async {
    final rows = await (await _database).query(
      'ledger',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'date DESC, created_at DESC',
    );
    return [
      for (final r in rows)
        NotebookLedger.fromJson({
          'id': r['id'],
          'title': r['title'],
          'kind': r['kind'],
          'amount': r['amount'],
          'category': r['category'],
          'date': r['date'],
          'note': r['note'],
          'createdAt': r['created_at'],
        }),
    ];
  }
}

/// 读书清单 DAO
class ReadingDao extends _BaseNotebookDao {
  ReadingDao({super.db});

  Future<void> insert(NotebookReading item, {required int userId}) async {
    await (await _database).insert('reading', {
      'id': item.id,
      'user_id': userId,
      'title': item.title,
      'author': item.author,
      'status': item.status,
      'rating': item.rating,
      'category': item.category,
      'note': item.note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> update(NotebookReading item) async {
    await (await _database).update(
      'reading',
      {
        'title': item.title,
        'author': item.author,
        'status': item.status,
        'rating': item.rating,
        'category': item.category,
        'note': item.note,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> delete(String id) async {
    await (await _database).delete('reading', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NotebookReading>> listByUser(int userId) async {
    final rows = await (await _database).query(
      'reading',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final r in rows)
        NotebookReading.fromJson({
          'id': r['id'],
          'title': r['title'],
          'author': r['author'],
          'status': r['status'],
          'rating': r['rating'],
          'category': r['category'],
          'note': r['note'],
        }),
    ];
  }
}

/// 旅游行程 DAO：行程 + 天 + 打卡点三层级联。
///
/// TripDay/TripCheckpoint 无业务 id，写库时生成 UUID + sort 保序；
/// 读取按 sort 还原嵌套结构。更新 = 整体替换（删除重建）。
class TripDao extends _BaseNotebookDao {
  TripDao({super.db});

  Future<void> insert(NotebookTrip trip, {required int userId}) async {
    final db = await _database;
    await db.insert('trips', _tripRow(trip, userId: userId));
    await _replaceDays(db, trip);
  }

  Future<void> update(NotebookTrip trip) async {
    final db = await _database;
    await db.update(
      'trips',
      _tripRow(trip),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
    await _replaceDays(db, trip);
  }

  Future<void> delete(String id) async {
    await (await _database).delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NotebookTrip>> listByUser(int userId) async {
    final db = await _database;
    final tripRows = await db.query(
      'trips',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    final days = await db.query(
      'trip_days',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'sort ASC',
    );
    final cps = await db.query(
      'trip_checkpoints',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'sort ASC',
    );
    final daysByTrip = <String, List<Map<String, dynamic>>>{};
    for (final d in days) {
      daysByTrip
          .putIfAbsent(d['trip_id'] as String, () => [])
          .add(d);
    }
    final cpsByDay = <String, List<Map<String, dynamic>>>{};
    for (final c in cps) {
      cpsByDay.putIfAbsent(c['day_id'] as String, () => []).add(c);
    }
    return [
      for (final tr in tripRows)
        NotebookTrip.fromJson({
          'id': tr['id'],
          'title': tr['title'],
          'city': tr['city'],
          'homeCity': tr['home_city'],
          'startDate': tr['start_date'],
          'endDate': tr['end_date'],
          'intercityTransport': _decodeMap(tr['intercity_transport']),
          'hotel': _decodeMap(tr['hotel']),
          'transports': _decodeList(tr['transports']),
          'days': [
            for (final d in daysByTrip[tr['id']] ?? const <Map<String, dynamic>>[])
              {
                'date': d['date'],
                'label': d['label'],
                'checkpoints': [
                  for (final c in cpsByDay[d['id']] ?? const <Map<String, dynamic>>[])
                    {
                      'name': c['name'],
                      'transport': _decodeMap(c['transport']),
                      'billings': _decodeList(c['billings']),
                      'done': (c['done'] as int) == 1,
                      'rating': c['rating'],
                      'note': c['note'],
                    },
                ],
              },
          ],
        }),
    ];
  }

  Map<String, dynamic> _tripRow(NotebookTrip trip, {int? userId}) => {
        if (userId != null) 'user_id': userId,
        'id': trip.id,
        'title': trip.title,
        'city': trip.city,
        'home_city': trip.homeCity,
        'start_date': trip.startDate,
        'end_date': trip.endDate,
        'intercity_transport':
            trip.intercityTransport == null ? null : jsonEncode(trip.intercityTransport!.toJson()),
        'hotel': trip.hotel == null ? null : jsonEncode(trip.hotel!.toJson()),
        'transports': jsonEncode([for (final t in trip.transports) t.toJson()]),
        'total_cost': trip.totalCost,
        'created_at': DateTime.now().toIso8601String(),
      };

  /// 删除并重建行程的天/打卡点；归属用户取该行程现有 user_id
  Future<void> _replaceDays(Database db, NotebookTrip trip) async {
    final owner = await db.query(
      'trips',
      columns: ['user_id'],
      where: 'id = ?',
      whereArgs: [trip.id],
      limit: 1,
    );
    final userId = owner.isEmpty ? 0 : owner.first['user_id'] as int;
    await db.delete('trip_days', where: 'trip_id = ?', whereArgs: [trip.id]);
    for (var di = 0; di < trip.days.length; di++) {
      final day = trip.days[di];
      final dayId = const Uuid().v4();
      await db.insert('trip_days', {
        'id': dayId,
        'trip_id': trip.id,
        'user_id': userId,
        'date': day.date,
        'label': day.label,
        'sort': di,
      });
      for (var ci = 0; ci < day.checkpoints.length; ci++) {
        final cp = day.checkpoints[ci];
        await db.insert('trip_checkpoints', {
          'id': const Uuid().v4(),
          'day_id': dayId,
          'user_id': userId,
          'name': cp.name,
          'transport': cp.transport == null ? null : jsonEncode(cp.transport!.toJson()),
          'billings': jsonEncode([for (final b in cp.billings) b.toJson()]),
          'done': cp.done ? 1 : 0,
          'rating': cp.rating,
          'note': cp.note,
          'sort': ci,
        });
      }
    }
  }
}

/// 学习 DAO：课程 + 名下记录级联。
class StudyDao extends _BaseNotebookDao {
  StudyDao({super.db});

  Future<void> insert(NotebookCourse course, {required int userId}) async {
    final db = await _database;
    await db.insert('courses', _courseRow(course, userId: userId));
    await _replaceRecords(db, course);
  }

  Future<void> update(NotebookCourse course) async {
    final db = await _database;
    await db.update(
      'courses',
      _courseRow(course),
      where: 'id = ?',
      whereArgs: [course.id],
    );
    await _replaceRecords(db, course);
  }

  Future<void> delete(String id) async {
    await (await _database).delete('courses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NotebookCourse>> listByUser(int userId) async {
    final db = await _database;
    final courseRows = await db.query(
      'courses',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    final records = await db.query(
      'study_records',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    final byCourse = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      byCourse.putIfAbsent(r['course_id'] as String, () => []).add(r);
    }
    return [
      for (final c in courseRows)
        NotebookCourse.fromJson({
          'id': c['id'],
          'title': c['title'],
          'source': c['source'],
          'status': c['status'],
          'progress': c['progress'],
          'rating': c['rating'],
          'category': c['category'],
          'note': c['note'],
          'records': [
            for (final r in byCourse[c['id']] ?? const <Map<String, dynamic>>[])
              {
                'id': r['id'],
                'title': r['title'],
                'content': r['content'],
                'rating': r['rating'],
                'note': r['note'],
                'createdAt': r['created_at'],
              },
          ],
        }),
    ];
  }

  Map<String, dynamic> _courseRow(NotebookCourse course, {int? userId}) => {
        if (userId != null) 'user_id': userId,
        'id': course.id,
        'title': course.title,
        'source': course.source,
        'status': course.status,
        'progress': course.progress,
        'rating': course.rating,
        'category': course.category,
        'note': course.note,
        'created_at': DateTime.now().toIso8601String(),
      };

  /// 删除并重建课程记录；归属用户取该课程现有 user_id
  Future<void> _replaceRecords(Database db, NotebookCourse course) async {
    final owner = await db.query(
      'courses',
      columns: ['user_id'],
      where: 'id = ?',
      whereArgs: [course.id],
      limit: 1,
    );
    final userId = owner.isEmpty ? 0 : owner.first['user_id'] as int;
    await db.delete(
      'study_records',
      where: 'course_id = ?',
      whereArgs: [course.id],
    );
    for (final r in course.records) {
      await db.insert('study_records', {
        'id': r.id,
        'course_id': course.id,
        'user_id': userId,
        'title': r.title,
        'content': r.content,
        'rating': r.rating,
        'note': r.note,
        'created_at': r.createdAt.toIso8601String(),
      });
    }
  }
}

/// 菜谱收藏 DAO。
class RecipeDao extends _BaseNotebookDao {
  RecipeDao({super.db});

  Future<void> insert(NotebookRecipe recipe, {required int userId}) async {
    await (await _database).insert('recipes', _recipeRow(recipe, userId: userId));
  }

  Future<void> update(NotebookRecipe recipe) async {
    await (await _database).update(
      'recipes',
      _recipeRow(recipe),
      where: 'id = ?',
      whereArgs: [recipe.id],
    );
  }

  Future<void> delete(String id) async {
    await (await _database).delete('recipes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NotebookRecipe>> listByUser(int userId) async {
    final rows = await (await _database).query(
      'recipes',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final r in rows)
        NotebookRecipe.fromJson({
          'id': r['id'],
          'name': r['name'],
          'category': r['category'],
          'ingredients': _decodeStringList(r['ingredients']),
          'steps': _decodeStringList(r['steps']),
          'difficulty': r['difficulty'],
          'rating': r['rating'],
          'note': r['note'],
        }),
    ];
  }

  Map<String, dynamic> _recipeRow(NotebookRecipe recipe, {int? userId}) => {
        if (userId != null) 'user_id': userId,
        'id': recipe.id,
        'name': recipe.name,
        'category': recipe.category,
        'ingredients': jsonEncode(recipe.ingredients),
        'steps': jsonEncode(recipe.steps),
        'difficulty': recipe.difficulty,
        'rating': recipe.rating,
        'note': recipe.note,
        'created_at': DateTime.now().toIso8601String(),
      };
}

Map<String, dynamic>? _decodeMap(dynamic value) {
  if (value == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(value as String) as Map);
  } catch (_) {
    return null;
  }
}

List<dynamic> _decodeList(dynamic value) {
  if (value == null) return const [];
  try {
    return jsonDecode(value as String) as List;
  } catch (_) {
    return const [];
  }
}

List<String> _decodeStringList(dynamic value) {
  try {
    return (jsonDecode(value as String) as List).cast<String>();
  } catch (_) {
    return const [];
  }
}
