import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../data/daos/notebook_daos.dart';
import '../models/notebook_ledger.dart';
import '../models/notebook_reading.dart';
import '../models/notebook_recipe.dart';
import '../models/notebook_shopping.dart';
import '../models/notebook_study.dart';
import '../models/notebook_trip.dart';

/// 旧版 Hive 记事本 → SQLite 尽力迁移。
///
/// 读取旧 `notebook_*` boxes（模型 fromJson 兼容旧格式），经各 DAO 写入
/// 并归属 [userId]；幂等标记 `app_meta.legacy_notebook_migrated`；
/// 任一环节异常静默跳过，不阻塞使用。
class LegacyNotebookMigration {
  static const _metaBoxName = 'app_meta';
  static const _migratedKey = 'legacy_notebook_migrated';

  Future<bool> migrate(int userId) async {
    try {
      try {
        await Hive.initFlutter();
      } catch (_) {
        // 单测等环境沿用既有 Hive 初始化
      }
      final meta = await Hive.openBox(_metaBoxName);
      if (meta.get(_migratedKey) == true) return false;

      var moved = 0;
      moved += await _migrateShopping(userId);
      moved += await _migrateLedger(userId);
      moved += await _migrateReading(userId);
      moved += await _migrateTrips(userId);
      moved += await _migrateStudy(userId);
      moved += await _migrateRecipes(userId);

      await meta.put(_migratedKey, true);
      return moved > 0;
    } catch (e) {
      debugPrint('记事本旧数据迁移跳过: $e');
      return false;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  Future<int> _migrateShopping(int userId) async {
    final dao = ShoppingDao();
    var moved = 0;
    final carts = await Hive.openBox('notebook_shopping_carts');
    for (final v in carts.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        final cart = NotebookShoppingCart.fromJson(m);
        await dao.insertCart(cart, userId: userId);
        moved++;
      } catch (_) {}
    }
    final items = await Hive.openBox('notebook_shopping');
    for (final v in items.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        final item = NotebookShopping.fromJson(m);
        await dao.insertItem(item, userId: userId);
        moved++;
      } catch (_) {}
    }
    return moved;
  }

  Future<int> _migrateLedger(int userId) async {
    final dao = LedgerDao();
    var moved = 0;
    final box = await Hive.openBox('notebook_ledger');
    for (final v in box.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        await dao.insert(NotebookLedger.fromJson(m), userId: userId);
        moved++;
      } catch (_) {}
    }
    return moved;
  }

  Future<int> _migrateReading(int userId) async {
    final dao = ReadingDao();
    var moved = 0;
    final box = await Hive.openBox('notebook_reading');
    for (final v in box.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        await dao.insert(NotebookReading.fromJson(m), userId: userId);
        moved++;
      } catch (_) {}
    }
    return moved;
  }

  Future<int> _migrateTrips(int userId) async {
    final dao = TripDao();
    var moved = 0;
    final box = await Hive.openBox('notebook_trip');
    for (final v in box.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        await dao.insert(NotebookTrip.fromJson(m), userId: userId);
        moved++;
      } catch (_) {}
    }
    return moved;
  }

  Future<int> _migrateStudy(int userId) async {
    final dao = StudyDao();
    var moved = 0;
    final box = await Hive.openBox('notebook_study');
    for (final v in box.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        await dao.insert(NotebookCourse.fromJson(m), userId: userId);
        moved++;
      } catch (_) {}
    }
    return moved;
  }

  Future<int> _migrateRecipes(int userId) async {
    final dao = RecipeDao();
    var moved = 0;
    final box = await Hive.openBox('notebook_recipe');
    for (final v in box.values) {
      final m = _asMap(v);
      if (m.isEmpty) continue;
      try {
        await dao.insert(NotebookRecipe.fromJson(m), userId: userId);
        moved++;
      } catch (_) {}
    }
    return moved;
  }
}
