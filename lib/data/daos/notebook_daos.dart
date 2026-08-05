import 'package:sqflite/sqflite.dart';

import '../../models/notebook_ledger.dart';
import '../../models/notebook_reading.dart';
import '../../models/notebook_shopping.dart';
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
