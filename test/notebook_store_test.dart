import 'dart:io';

import 'package:hive/hive.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/services/notebook_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// NotebookStore 子购物车 / 分组单元测试（T5，G2）。
///
/// 采用真实 Hive（temp 目录）验证持久化，测试后清理。
/// 覆盖：
///  - [NotebookShopping] / [NotebookShoppingCart] 模型默认值与 JSON round-trip；
///  - 子购物车 add / update / delete 读写一致；
///  - [NotebookStore.cartsOf] 对旧数据 cartId=='' 归「未分组」。
void main() {
  late NotebookStore store;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('hive_nb_store_');
    try {
      Hive.init(tmp.path);
    } catch (_) {}
    store = NotebookStore();
    await store.init();
  });

  setUp(() async {
    // 每个用例独立：清空相关盒子（init 已打开）。
    await Hive.box('notebook_shopping').clear();
    await Hive.box('notebook_shopping_carts').clear();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('NotebookShopping 模型 + 默认值', () {
    test('cartId / date 默认值为空串（未分组 / 今日）', () {
      final s = NotebookShopping(
        id: 's1',
        item: '牛奶',
        createdAt: DateTime.now(),
      );
      expect(s.cartId, kDefaultCartId);
      expect(s.cartId, '');
      expect(s.date, '');
    });

    test('fromJson / toJson 透传 cartId 与 date', () {
      final s = NotebookShopping(
        id: 's2',
        item: '鸡蛋',
        cartId: 'c1',
        date: '2026-07-19',
        createdAt: DateTime.now(),
      );
      final back = NotebookShopping.fromJson(s.toJson());
      expect(back.id, 's2');
      expect(back.item, '鸡蛋');
      expect(back.cartId, 'c1');
      expect(back.date, '2026-07-19');
    });

    test('kDefaultCartName 为「未分组」', () {
      expect(kDefaultCartName, '未分组');
    });
  });

  group('NotebookShoppingCart 模型 round-trip', () {
    test('fromJson / toJson 保留 note 与 createdAt', () {
      final c = NotebookShoppingCart(
        id: 'cc',
        name: '卡',
        createdAt: DateTime(2026, 7, 19, 8, 0),
        note: '备注',
      );
      final back = NotebookShoppingCart.fromJson(c.toJson());
      expect(back.id, 'cc');
      expect(back.name, '卡');
      expect(back.note, '备注');
      expect(back.createdAt, DateTime(2026, 7, 19, 8, 0));
    });
  });

  group('NotebookStore - 子购物车 CRUD', () {
    test('addCart 后 shoppingCarts 可见', () async {
      await store.addCart(NotebookShoppingCart(
        id: 'c1',
        name: '生鲜',
        createdAt: DateTime(2026, 7, 19),
      ));
      expect(store.shoppingCarts, hasLength(1));
      expect(store.shoppingCarts.first.name, '生鲜');
    });

    test('updateCart 改写 name（按 id 覆盖）', () async {
      await store.addCart(NotebookShoppingCart(
        id: 'c2',
        name: '旧名',
        createdAt: DateTime(2026, 7, 19),
      ));
      await store.updateCart(NotebookShoppingCart(
        id: 'c2',
        name: '新名',
        createdAt: DateTime(2026, 7, 19),
      ));
      final found = store.shoppingCarts.firstWhere((c) => c.id == 'c2');
      expect(found.name, '新名');
    });

    test('deleteCart 移除', () async {
      await store.addCart(NotebookShoppingCart(
        id: 'c3',
        name: 'x',
        createdAt: DateTime(2026, 7, 19),
      ));
      await store.deleteCart('c3');
      expect(store.shoppingCarts.any((c) => c.id == 'c3'), isFalse);
    });

    test('addCart 空 id 入参时自动生成非空 id', () async {
      await store.addCart(NotebookShoppingCart(
        id: '',
        name: '自动id',
        createdAt: DateTime(2026, 7, 19),
      ));
      final added =
          store.shoppingCarts.firstWhere((c) => c.name == '自动id');
      expect(added.id, isNotEmpty);
    });
  });

  group('NotebookStore - cartsOf 分组', () {
    test('旧数据 cartId=="" 归为未分组（cartsOf("") 返回这些项）', () async {
      await store.addShopping(NotebookShopping(
        id: 's1',
        item: 'A',
        createdAt: DateTime.now(),
      ));
      await store.addShopping(NotebookShopping(
        id: 's2',
        item: 'B',
        createdAt: DateTime.now(),
      ));
      await store.addShopping(
        NotebookShopping(
          id: 's3',
          item: 'C',
          cartId: 'c1',
          createdAt: DateTime.now(),
        ),
      );

      final ungrouped = store.cartsOf('');
      expect(ungrouped, hasLength(2),
          reason: '两个默认 cartId="" 的项应归入未分组');
      expect(ungrouped.map((e) => e.id), containsAll(['s1', 's2']));

      final c1 = store.cartsOf('c1');
      expect(c1, hasLength(1));
      expect(c1.first.item, 'C');
    });

    test('cartsOf(cartId) 仅返回该购物车下的项，cartsOf("") 仅返回未分组', () async {
      await store.addCart(NotebookShoppingCart(
        id: 'c9',
        name: '九',
        createdAt: DateTime(2026, 7, 19),
      ));
      await store.addShopping(
        NotebookShopping(
          id: 'x1',
          item: 'xa',
          cartId: 'c9',
          createdAt: DateTime.now(),
        ),
      );
      await store.addShopping(
        NotebookShopping(
          id: 'x2',
          item: 'xb',
          cartId: 'c9',
          createdAt: DateTime.now(),
        ),
      );
      await store.addShopping(NotebookShopping(
        id: 'x3',
        item: 'xc',
        createdAt: DateTime.now(),
      ));

      expect(store.cartsOf('c9'), hasLength(2));
      expect(store.cartsOf(''), hasLength(1));
      expect(store.cartsOf('c9').map((e) => e.id), containsAll(['x1', 'x2']));
    });
  });
}
