// NotebookStore（SQLite 版）单元测试：六模块 CRUD、user_id 隔离、删购物车孤儿回收、记录操作
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/models/notebook_ledger.dart';
import 'package:daily_planner/models/notebook_reading.dart';
import 'package:daily_planner/models/notebook_recipe.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/models/notebook_study.dart';
import 'package:daily_planner/models/notebook_trip.dart';
import 'package:daily_planner/services/notebook_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late NotebookStore store;

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'owner',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    store = NotebookStore(userId: 1);
    await store.init();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('购物：子购物车与项 CRUD、删购物车孤儿回收', () async {
    await store.addCart(
      NotebookShoppingCart(
        id: 'c1',
        name: '超市',
        note: null,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    await store.addShopping(
      NotebookShopping(
        id: 'i1',
        item: '牛奶',
        price: 9.5,
        category: '食品',
        note: '',
        cartId: 'c1',
        date: '2026-08-05',
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    expect(store.shoppingCarts, hasLength(1));
    expect(store.cartsOf('c1'), hasLength(1));

    await store.updateCart(
      NotebookShoppingCart(
        id: 'c1',
        name: '超市（改）',
        note: null,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    expect(store.shoppingCarts.single.name, '超市（改）');

    await store.deleteCart('c1');
    expect(store.shoppingCarts, isEmpty);
    expect(store.shopping.single.cartId, '');
  });

  test('收支：增删改查', () async {
    await store.addLedger(
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 12000,
        category: '薪资',
        date: '2026-08-05',
        note: '',
      ),
    );
    expect(store.ledger.single.amount, 12000);
    await store.updateLedger(
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 13000,
        category: '薪资',
        date: '2026-08-05',
        note: '调薪',
      ),
    );
    expect(store.ledger.single.amount, 13000);
    await store.deleteLedger('l1');
    expect(store.ledger, isEmpty);
  });

  test('读书与菜谱：增删改查', () async {
    await store.addReading(
      NotebookReading(
        id: 'r1',
        title: '三体',
        author: '刘慈欣',
        status: 'reading',
        rating: 5,
        category: '科幻',
        note: '',
      ),
    );
    expect(store.reading.single.title, '三体');
    await store.deleteReading('r1');
    expect(store.reading, isEmpty);

    await store.addRecipe(
      NotebookRecipe(
        id: 'rc1',
        name: '红烧肉',
        category: '荤菜',
        ingredients: const ['五花肉'],
        steps: const ['炖'],
        difficulty: 'hard',
        rating: 5,
        note: '',
      ),
    );
    expect(store.recipes.single.ingredients, ['五花肉']);
    await store.deleteRecipe('rc1');
    expect(store.recipes, isEmpty);
  });

  test('旅游：增删改查与 totalCost', () async {
    final trip = NotebookTrip(
      id: 't1',
      title: '杭州三日',
      city: '杭州',
      homeCity: '上海',
      startDate: '2026-08-10',
      endDate: '2026-08-12',
      days: [
        TripDay(
          date: '2026-08-10',
          label: 'D1',
          checkpoints: [
            TripCheckpoint(
              name: '西湖',
              billings: [TripBilling(type: '门票', amount: 45)],
            ),
          ],
        ),
      ],
    );
    await store.addTrip(trip);
    expect(store.trips.single.days.single.checkpoints.single.name, '西湖');
    expect(store.trips.single.totalCost, 45);
    await store.deleteTrip('t1');
    expect(store.trips, isEmpty);
  });

  test('学习：课程与记录级联操作', () async {
    await store.addCourse(
      NotebookCourse(
        id: 'c1',
        title: 'Flutter',
        status: 'learning',
        progress: 40,
      ),
    );
    await store.addRecord(
      'c1',
      StudyRecord(
        id: 'r1',
        title: '状态管理',
        content: 'Provider',
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    expect(store.courses.single.records, hasLength(1));
    await store.updateRecord(
      'c1',
      StudyRecord(
        id: 'r1',
        title: '状态管理（复习）',
        content: 'Provider',
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    expect(store.courses.single.records.single.title, '状态管理（复习）');
    await store.deleteRecord('c1', 'r1');
    expect(store.courses.single.records, isEmpty);
    await store.deleteCourse('c1');
    expect(store.courses, isEmpty);
  });

  test('user_id 隔离：另一用户看不到数据', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('users', {
      'username': 'other',
      'password_hash': 'hash',
      'created_at': '2026-08-05T00:00:00',
    });
    await store.addLedger(
      NotebookLedger(
        id: 'l1',
        title: '工资',
        kind: 'income',
        amount: 1,
        category: '',
        date: '',
        note: '',
      ),
    );
    final other = NotebookStore(userId: 2);
    await other.init();
    expect(other.ledger, isEmpty);
  });
}
