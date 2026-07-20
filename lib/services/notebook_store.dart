import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/notebook_ledger.dart';
import '../models/notebook_reading.dart';
import '../models/notebook_recipe.dart';
import '../models/notebook_shopping.dart';
import '../models/notebook_study.dart';
import '../models/notebook_trip.dart';

/// 记事本仓储：封装各子功能 Hive 读写，对外暴露为 ChangeNotifier（Provider）。
///
/// 存储策略：**JSON-map 存储**——每个子功能一个 `notebook_<sub>` 盒子，存入
/// 模型 `toJson()` 得到的 `Map`，读取时经 `fromJson` 还原。这样无需为这一打
/// 嵌套模型手写 Hive TypeAdapter，降低维护成本；盒子统一在 [init] 中打开。
class NotebookStore extends ChangeNotifier {
  late Box _shoppingBox;
  late Box _cartsBox;
  late Box _ledgerBox;
  late Box _readingBox;
  late Box _tripBox;
  late Box _studyBox;
  late Box _recipeBox;

  int _seq = 0;

  /// 进程内唯一 id（时间戳 + 自增，避免同毫秒碰撞）。
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<void> init() async {
    _shoppingBox = await Hive.openBox('notebook_shopping');
    _cartsBox = await Hive.openBox('notebook_shopping_carts');
    _ledgerBox = await Hive.openBox('notebook_ledger');
    _readingBox = await Hive.openBox('notebook_reading');
    _tripBox = await Hive.openBox('notebook_trip');
    _studyBox = await Hive.openBox('notebook_study');
    _recipeBox = await Hive.openBox('notebook_recipe');
    notifyListeners();
  }

  // ── 通用：按盒子还原为强类型列表 ─────────────────────
  List<T> _list<T>(Box box, T Function(Map<String, dynamic>) fromJson) =>
      box.values
          .whereType<Map>()
          .map((m) => fromJson(Map<String, dynamic>.from(m)))
          .toList();

  // ── 购物 ─────────────────────────────────────────────
  List<NotebookShopping> get shopping =>
      _list(_shoppingBox, NotebookShopping.fromJson);

  Future<void> addShopping(NotebookShopping item) async {
    final map = item.toJson();
    final id = _ensureId(map);
    await _shoppingBox.put(id, map);
    notifyListeners();
  }

  Future<void> deleteShopping(String id) async {
    await _shoppingBox.delete(id);
    notifyListeners();
  }

  // ── 购物子购物车 ─────────────────────────────────────
  List<NotebookShoppingCart> get shoppingCarts =>
      _list(_cartsBox, NotebookShoppingCart.fromJson);

  Future<void> addCart(NotebookShoppingCart cart) async {
    final map = cart.toJson();
    final id = _ensureId(map);
    await _cartsBox.put(id, map);
    notifyListeners();
  }

  Future<void> updateCart(NotebookShoppingCart cart) async {
    await _cartsBox.put(cart.id, cart.toJson());
    notifyListeners();
  }

  Future<void> deleteCart(String id) async {
    await _cartsBox.delete(id);
    notifyListeners();
  }

  /// 返回指定 [cartId] 下的购物项；[cartId] 为空（''）即「未分组」分组。
  List<NotebookShopping> cartsOf(String cartId) =>
      shopping.where((e) => e.cartId == cartId).toList();

  // ── 收支账本 ─────────────────────────────────────────
  List<NotebookLedger> get ledger => _list(_ledgerBox, NotebookLedger.fromJson);

  Future<void> addLedger(NotebookLedger item) async {
    final map = item.toJson();
    final id = _ensureId(map);
    await _ledgerBox.put(id, map);
    notifyListeners();
  }

  Future<void> deleteLedger(String id) async {
    await _ledgerBox.delete(id);
    notifyListeners();
  }

  Future<void> updateLedger(NotebookLedger item) async {
    await _ledgerBox.put(item.id, item.toJson());
    notifyListeners();
  }

  // ── 读书清单 ─────────────────────────────────────────
  List<NotebookReading> get reading =>
      _list(_readingBox, NotebookReading.fromJson);

  Future<void> addReading(NotebookReading item) async {
    final map = item.toJson();
    final id = _ensureId(map);
    await _readingBox.put(id, map);
    notifyListeners();
  }

  Future<void> deleteReading(String id) async {
    await _readingBox.delete(id);
    notifyListeners();
  }

  Future<void> updateReading(NotebookReading item) async {
    await _readingBox.put(item.id, item.toJson());
    notifyListeners();
  }

  // ── 旅游行程 ─────────────────────────────────────────
  List<NotebookTrip> get trips => _list(_tripBox, NotebookTrip.fromJson);

  Future<void> addTrip(NotebookTrip item) async {
    final map = item.toJson();
    final id = _ensureId(map);
    await _tripBox.put(id, map);
    notifyListeners();
  }

  Future<void> deleteTrip(String id) async {
    await _tripBox.delete(id);
    notifyListeners();
  }

  Future<void> updateTrip(NotebookTrip trip) async {
    await _tripBox.put(trip.id, trip.toJson());
    notifyListeners();
  }

  // ── 菜谱收藏 ─────────────────────────────────────────
  List<NotebookRecipe> get recipes => _list(_recipeBox, NotebookRecipe.fromJson);

  Future<void> addRecipe(NotebookRecipe item) async {
    final map = item.toJson();
    final id = _ensureId(map);
    await _recipeBox.put(id, map);
    notifyListeners();
  }

  Future<void> deleteRecipe(String id) async {
    await _recipeBox.delete(id);
    notifyListeners();
  }

  Future<void> updateRecipe(NotebookRecipe item) async {
    await _recipeBox.put(item.id, item.toJson());
    notifyListeners();
  }

  // ── 学习记录（课程维度）──────────────────────────────
  List<NotebookCourse> get courses =>
      _list(_studyBox, NotebookCourse.fromJson);

  Future<void> addCourse(NotebookCourse course) async {
    final map = course.toJson();
    final id = _ensureId(map);
    await _studyBox.put(id, map);
    notifyListeners();
  }

  Future<void> updateCourse(NotebookCourse course) async {
    await _studyBox.put(course.id, course.toJson());
    notifyListeners();
  }

  Future<void> deleteCourse(String id) async {
    await _studyBox.delete(id);
    notifyListeners();
  }

  /// 在指定课程下追加一条学习记录（语音/手动录入均走此入口）。
  Future<void> addRecord(String courseId, StudyRecord record) async {
    final raw = _studyBox.get(courseId);
    if (raw is! Map) return;
    final course = NotebookCourse.fromJson(Map<String, dynamic>.from(raw));
    final map = record.toJson();
    final id = _ensureId(map);
    final records = List<StudyRecord>.from(course.records)
      ..add(record.copyWith(id: id));
    await _studyBox.put(
        courseId, course.copyWith(records: records).toJson());
    notifyListeners();
  }

  Future<void> deleteRecord(String courseId, String recordId) async {
    final raw = _studyBox.get(courseId);
    if (raw is! Map) return;
    final course = NotebookCourse.fromJson(Map<String, dynamic>.from(raw));
    final records =
        course.records.where((r) => r.id != recordId).toList();
    await _studyBox.put(
        courseId, course.copyWith(records: records).toJson());
    notifyListeners();
  }

  /// 更新课程下某条学习记录（编辑后落库）。
  Future<void> updateRecord(String courseId, StudyRecord record) async {
    final raw = _studyBox.get(courseId);
    if (raw is! Map) return;
    final course = NotebookCourse.fromJson(Map<String, dynamic>.from(raw));
    final records = course.records
        .map((r) => r.id == record.id ? record : r)
        .toList();
    await _studyBox.put(
        courseId, course.copyWith(records: records).toJson());
    notifyListeners();
  }

  // ── 内部工具 ─────────────────────────────────────────
  /// 若模型 id 为空，生成新 id 并写回 map，返回最终使用的 id。
  String _ensureId(Map<String, dynamic> map) {
    final existing = map['id']?.toString() ?? '';
    if (existing.isNotEmpty) return existing;
    final id = _newId();
    map['id'] = id;
    return id;
  }
}
