// 内存版记事本仓储：widget 测试使用，避免 FakeAsync 中真实 SQLite 异步无法完成
import 'package:daily_planner/models/notebook_ledger.dart';
import 'package:daily_planner/models/notebook_reading.dart';
import 'package:daily_planner/models/notebook_recipe.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/models/notebook_study.dart';
import 'package:daily_planner/models/notebook_trip.dart';
import 'package:daily_planner/services/notebook_store.dart';

class FakeNotebookStore extends NotebookStore {
  FakeNotebookStore() : super(userId: 1);

  final List<NotebookShopping> _items = [];
  final List<NotebookShoppingCart> _carts = [];
  final List<NotebookLedger> _ledger = [];
  final List<NotebookReading> _reading = [];
  final List<NotebookTrip> _trips = [];
  final List<NotebookRecipe> _recipes = [];
  final List<NotebookCourse> _courses = [];

  @override
  Future<void> init() async {}

  @override
  List<NotebookShopping> get shopping => List.unmodifiable(_items);

  @override
  List<NotebookShoppingCart> get shoppingCarts => List.unmodifiable(_carts);

  @override
  List<NotebookShopping> cartsOf(String cartId) =>
      _items.where((i) => i.cartId == cartId).toList();

  @override
  Future<void> addShopping(NotebookShopping item) async {
    _items.removeWhere((i) => i.id == item.id);
    _items.add(item);
    notifyListeners();
  }

  @override
  Future<void> updateShopping(NotebookShopping item) async {
    final i = _items.indexWhere((x) => x.id == item.id);
    if (i >= 0) _items[i] = item;
    notifyListeners();
  }

  @override
  Future<void> deleteShopping(String id) async {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  @override
  Future<void> addCart(NotebookShoppingCart cart) async {
    _carts.removeWhere((c) => c.id == cart.id);
    _carts.add(cart);
    notifyListeners();
  }

  @override
  Future<void> updateCart(NotebookShoppingCart cart) async {
    final i = _carts.indexWhere((c) => c.id == cart.id);
    if (i >= 0) _carts[i] = cart;
    notifyListeners();
  }

  @override
  Future<void> deleteCart(String id) async {
    _carts.removeWhere((c) => c.id == id);
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].cartId == id) {
        _items[i] = _copyItem(_items[i], cartId: '');
      }
    }
    notifyListeners();
  }

  @override
  List<NotebookLedger> get ledger => List.unmodifiable(_ledger);

  @override
  Future<void> addLedger(NotebookLedger item) async {
    _ledger.removeWhere((x) => x.id == item.id);
    _ledger.add(item);
    notifyListeners();
  }

  @override
  Future<void> updateLedger(NotebookLedger item) async {
    final i = _ledger.indexWhere((x) => x.id == item.id);
    if (i >= 0) _ledger[i] = item;
    notifyListeners();
  }

  @override
  Future<void> deleteLedger(String id) async {
    _ledger.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  @override
  List<NotebookReading> get reading => List.unmodifiable(_reading);

  @override
  Future<void> addReading(NotebookReading item) async {
    _reading.removeWhere((x) => x.id == item.id);
    _reading.add(item);
    notifyListeners();
  }

  @override
  Future<void> updateReading(NotebookReading item) async {
    final i = _reading.indexWhere((x) => x.id == item.id);
    if (i >= 0) _reading[i] = item;
    notifyListeners();
  }

  @override
  Future<void> deleteReading(String id) async {
    _reading.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  @override
  List<NotebookTrip> get trips => List.unmodifiable(_trips);

  @override
  Future<void> addTrip(NotebookTrip item) async {
    _trips.removeWhere((x) => x.id == item.id);
    _trips.add(item);
    notifyListeners();
  }

  @override
  Future<void> updateTrip(NotebookTrip trip) async {
    final i = _trips.indexWhere((x) => x.id == trip.id);
    if (i >= 0) _trips[i] = trip;
    notifyListeners();
  }

  @override
  Future<void> deleteTrip(String id) async {
    _trips.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  @override
  List<NotebookRecipe> get recipes => List.unmodifiable(_recipes);

  @override
  Future<void> addRecipe(NotebookRecipe item) async {
    _recipes.removeWhere((x) => x.id == item.id);
    _recipes.add(item);
    notifyListeners();
  }

  @override
  Future<void> updateRecipe(NotebookRecipe item) async {
    final i = _recipes.indexWhere((x) => x.id == item.id);
    if (i >= 0) _recipes[i] = item;
    notifyListeners();
  }

  @override
  Future<void> deleteRecipe(String id) async {
    _recipes.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  @override
  List<NotebookCourse> get courses => List.unmodifiable(_courses);

  @override
  Future<void> addCourse(NotebookCourse course) async {
    _courses.removeWhere((x) => x.id == course.id);
    _courses.add(course);
    notifyListeners();
  }

  @override
  Future<void> updateCourse(NotebookCourse course) async {
    final i = _courses.indexWhere((x) => x.id == course.id);
    if (i >= 0) _courses[i] = course;
    notifyListeners();
  }

  @override
  Future<void> deleteCourse(String id) async {
    _courses.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  @override
  Future<void> addRecord(String courseId, StudyRecord record) async {
    final i = _courses.indexWhere((c) => c.id == courseId);
    if (i < 0) return;
    _courses[i] = _courses[i].copyWith(
      records: [..._courses[i].records, record],
    );
    notifyListeners();
  }

  @override
  Future<void> deleteRecord(String courseId, String recordId) async {
    final i = _courses.indexWhere((c) => c.id == courseId);
    if (i < 0) return;
    _courses[i] = _courses[i].copyWith(
      records: _courses[i].records.where((r) => r.id != recordId).toList(),
    );
    notifyListeners();
  }

  @override
  Future<void> updateRecord(String courseId, StudyRecord record) async {
    final i = _courses.indexWhere((c) => c.id == courseId);
    if (i < 0) return;
    _courses[i] = _courses[i].copyWith(
      records: [
        for (final r in _courses[i].records)
          if (r.id == record.id) record else r,
      ],
    );
    notifyListeners();
  }

  NotebookShopping _copyItem(NotebookShopping item, {required String cartId}) =>
      NotebookShopping(
        id: item.id,
        item: item.item,
        expectedPrice: item.expectedPrice,
        actualPrice: item.actualPrice,
        category: item.category,
        note: item.note,
        cartId: cartId,
        date: item.date,
        createdAt: item.createdAt,
      );
}
