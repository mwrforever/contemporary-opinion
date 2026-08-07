import 'package:flutter/foundation.dart';

import '../data/daos/notebook_daos.dart';
import '../models/notebook_ledger.dart';
import '../models/notebook_reading.dart';
import '../models/notebook_recipe.dart';
import '../models/notebook_shopping.dart';
import '../models/notebook_study.dart';
import '../models/notebook_trip.dart';

/// 记事本仓储：基于 SQLite（各模块 DAO），对外暴露为 ChangeNotifier（Provider）。
///
/// 公开 API 与旧 Hive 版保持一致；[userId] 归属当前登录用户。
/// 所有写操作先落库再更新内存并 notifyListeners。
class NotebookStore extends ChangeNotifier {
  NotebookStore({
    required this.userId,
    ShoppingDao? shoppingDao,
    LedgerDao? ledgerDao,
    ReadingDao? readingDao,
    TripDao? tripDao,
    StudyDao? studyDao,
    RecipeDao? recipeDao,
  })  : _shopping = shoppingDao ?? ShoppingDao(),
        _ledger = ledgerDao ?? LedgerDao(),
        _reading = readingDao ?? ReadingDao(),
        _trip = tripDao ?? TripDao(),
        _study = studyDao ?? StudyDao(),
        _recipe = recipeDao ?? RecipeDao();

  final int userId;
  final ShoppingDao _shopping;
  final LedgerDao _ledger;
  final ReadingDao _reading;
  final TripDao _trip;
  final StudyDao _study;
  final RecipeDao _recipe;

  List<NotebookShopping> _shoppingItems = [];
  List<NotebookShoppingCart> _carts = [];
  List<NotebookLedger> _ledgerItems = [];
  List<NotebookReading> _readingItems = [];
  List<NotebookTrip> _tripItems = [];
  List<NotebookRecipe> _recipeItems = [];
  List<NotebookCourse> _courses = [];

  /// 从数据库加载当前用户全部记事本数据
  Future<void> init() async {
    _shoppingItems = await _shopping.listItems(userId);
    _carts = await _shopping.listCarts(userId);
    _ledgerItems = await _ledger.listByUser(userId);
    _readingItems = await _reading.listByUser(userId);
    _tripItems = await _trip.listByUser(userId);
    _recipeItems = await _recipe.listByUser(userId);
    _courses = await _study.listByUser(userId);
    notifyListeners();
  }

  // ── 购物 ─────────────────────────────────────────────
  List<NotebookShopping> get shopping => List.unmodifiable(_shoppingItems);
  List<NotebookShoppingCart> get shoppingCarts => List.unmodifiable(_carts);

  List<NotebookShopping> cartsOf(String cartId) =>
      _shoppingItems.where((i) => i.cartId == cartId).toList();

  Future<void> addShopping(NotebookShopping item) async {
    await _shopping.insertItem(item, userId: userId);
    _shoppingItems.add(item);
    notifyListeners();
  }

  Future<void> deleteShopping(String id) async {
    await _shopping.deleteItem(id);
    _shoppingItems.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> updateShopping(NotebookShopping item) async {
    await _shopping.updateItem(item);
    final i = _shoppingItems.indexWhere((x) => x.id == item.id);
    if (i >= 0) _shoppingItems[i] = item;
    notifyListeners();
  }

  Future<void> addCart(NotebookShoppingCart cart) async {
    await _shopping.insertCart(cart, userId: userId);
    _carts.add(cart);
    notifyListeners();
  }

  Future<void> updateCart(NotebookShoppingCart cart) async {
    await _shopping.updateCart(cart);
    final i = _carts.indexWhere((c) => c.id == cart.id);
    if (i >= 0) _carts[i] = cart;
    notifyListeners();
  }

  Future<void> deleteCart(String id) async {
    await _shopping.deleteCart(id);
    _carts.removeWhere((c) => c.id == id);
    // 删除购物车后其项回收为未分组（外键 SET NULL），重新拉取同步内存
    _shoppingItems = await _shopping.listItems(userId);
    notifyListeners();
  }

  // ── 收支 ─────────────────────────────────────────────
  List<NotebookLedger> get ledger => List.unmodifiable(_ledgerItems);

  Future<void> addLedger(NotebookLedger item) async {
    await _ledger.insert(item, userId: userId);
    _ledgerItems.add(item);
    notifyListeners();
  }

  Future<void> deleteLedger(String id) async {
    await _ledger.delete(id);
    _ledgerItems.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> updateLedger(NotebookLedger item) async {
    await _ledger.update(item);
    final i = _ledgerItems.indexWhere((x) => x.id == item.id);
    if (i >= 0) _ledgerItems[i] = item;
    notifyListeners();
  }

  // ── 读书 ─────────────────────────────────────────────
  List<NotebookReading> get reading => List.unmodifiable(_readingItems);

  Future<void> addReading(NotebookReading item) async {
    await _reading.insert(item, userId: userId);
    _readingItems.add(item);
    notifyListeners();
  }

  Future<void> deleteReading(String id) async {
    await _reading.delete(id);
    _readingItems.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> updateReading(NotebookReading item) async {
    await _reading.update(item);
    final i = _readingItems.indexWhere((x) => x.id == item.id);
    if (i >= 0) _readingItems[i] = item;
    notifyListeners();
  }

  // ── 旅游 ─────────────────────────────────────────────
  List<NotebookTrip> get trips => List.unmodifiable(_tripItems);

  Future<void> addTrip(NotebookTrip item) async {
    await _trip.insert(item, userId: userId);
    _tripItems.add(item);
    notifyListeners();
  }

  Future<void> deleteTrip(String id) async {
    await _trip.delete(id);
    _tripItems.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> updateTrip(NotebookTrip trip) async {
    await _trip.update(trip);
    final i = _tripItems.indexWhere((x) => x.id == trip.id);
    if (i >= 0) _tripItems[i] = trip;
    notifyListeners();
  }

  // ── 菜谱 ─────────────────────────────────────────────
  List<NotebookRecipe> get recipes => List.unmodifiable(_recipeItems);

  Future<void> addRecipe(NotebookRecipe item) async {
    await _recipe.insert(item, userId: userId);
    _recipeItems.add(item);
    notifyListeners();
  }

  Future<void> deleteRecipe(String id) async {
    await _recipe.delete(id);
    _recipeItems.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> updateRecipe(NotebookRecipe item) async {
    await _recipe.update(item);
    final i = _recipeItems.indexWhere((x) => x.id == item.id);
    if (i >= 0) _recipeItems[i] = item;
    notifyListeners();
  }

  // ── 学习 ─────────────────────────────────────────────
  List<NotebookCourse> get courses => List.unmodifiable(_courses);

  Future<void> addCourse(NotebookCourse course) async {
    await _study.insert(course, userId: userId);
    _courses.add(course);
    notifyListeners();
  }

  Future<void> updateCourse(NotebookCourse course) async {
    await _study.update(course);
    final i = _courses.indexWhere((x) => x.id == course.id);
    if (i >= 0) _courses[i] = course;
    notifyListeners();
  }

  Future<void> deleteCourse(String id) async {
    await _study.delete(id);
    _courses.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  Future<void> addRecord(String courseId, StudyRecord record) async {
    final i = _courses.indexWhere((c) => c.id == courseId);
    if (i < 0) return;
    final updated = _courses[i].copyWith(
      records: [..._courses[i].records, record],
    );
    await updateCourse(updated);
  }

  Future<void> deleteRecord(String courseId, String recordId) async {
    final i = _courses.indexWhere((c) => c.id == courseId);
    if (i < 0) return;
    final updated = _courses[i].copyWith(
      records: _courses[i].records.where((r) => r.id != recordId).toList(),
    );
    await updateCourse(updated);
  }

  Future<void> updateRecord(String courseId, StudyRecord record) async {
    final i = _courses.indexWhere((c) => c.id == courseId);
    if (i < 0) return;
    final updated = _courses[i].copyWith(
      records: [
        for (final r in _courses[i].records)
          if (r.id == record.id) record else r,
      ],
    );
    await updateCourse(updated);
  }
}
