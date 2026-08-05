// 记事本 DAO 测试：购物（车+项+孤儿回收）/ 收支 / 读书 的增删改查与隔离
import 'package:daily_planner/data/database_helper.dart';
import 'package:daily_planner/data/daos/notebook_daos.dart';
import 'package:daily_planner/models/notebook_ledger.dart';
import 'package:daily_planner/models/notebook_reading.dart';
import 'package:daily_planner/models/notebook_recipe.dart';
import 'package:daily_planner/models/notebook_shopping.dart';
import 'package:daily_planner/models/notebook_study.dart';
import 'package:daily_planner/models/notebook_trip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() async {
    DatabaseHelper.setFactoryForTest(databaseFactoryFfi);
    DatabaseHelper.setPathForTest(inMemoryDatabasePath);
    final db = await DatabaseHelper.instance.database;
    for (final i in [1, 2]) {
      await db.insert('users', {
        'username': 'user$i',
        'password_hash': 'hash',
        'created_at': '2026-08-05T00:00:00',
      });
    }
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  group('ShoppingDao', () {
    test('购物车与项：插入、按车列出、删除车回收为未分组', () async {
      final dao = ShoppingDao();
      await dao.insertCart(
        NotebookShoppingCart(id: 'c1', name: '超市', note: null, createdAt: DateTime(2026, 8, 1)),
        userId: 1,
      );
      await dao.insertItem(
        NotebookShopping(
          id: 'i1',
          item: '牛奶',
          expectedPrice: 10,
          actualPrice: 9.5,
          category: '食品',
          note: '',
          cartId: 'c1',
          date: '2026-08-05',
          createdAt: DateTime(2026, 8, 1),
        ),
        userId: 1,
      );
      expect(await dao.listCarts(1), hasLength(1));
      expect(await dao.listItems(1, cartId: 'c1'), hasLength(1));
      expect(await dao.listItems(1), isEmpty);

      // 删除购物车 → 项回收为未分组
      await dao.deleteCart('c1');
      final recycled = await dao.listItems(1);
      expect(recycled.single.cartId, '');
    });

    test('购物项更新与删除', () async {
      final dao = ShoppingDao();
      final item = NotebookShopping(
        id: 'i1',
        item: '苹果',
        expectedPrice: 5,
        actualPrice: 4,
        category: '',
        note: '',
        cartId: '',
        date: '',
        createdAt: DateTime(2026, 8, 1),
      );
      await dao.insertItem(item, userId: 1);
      await dao.updateItem(
        NotebookShopping(
          id: 'i1',
          item: '苹果',
          expectedPrice: 6,
          actualPrice: 5,
          category: '',
          note: '特价',
          cartId: '',
          date: '',
          createdAt: DateTime(2026, 8, 1),
        ),
      );
      final updated = (await dao.listItems(1)).single;
      expect(updated.expectedPrice, 6);
      expect(updated.note, '特价');
      await dao.deleteItem('i1');
      expect(await dao.listItems(1), isEmpty);
    });

    test('按 user_id 隔离', () async {
      final dao = ShoppingDao();
      await dao.insertItem(
        NotebookShopping(
          id: 'i1',
          item: '用户1的',
          expectedPrice: 1,
          actualPrice: 1,
          category: '',
          note: '',
          cartId: '',
          date: '',
          createdAt: DateTime(2026, 8, 1),
        ),
        userId: 1,
      );
      expect(await dao.listItems(2), isEmpty);
    });
  });

  group('LedgerDao', () {
    test('增删改查与隔离', () async {
      final dao = LedgerDao();
      await dao.insert(
        NotebookLedger(
          id: 'l1',
          title: '工资',
          kind: 'income',
          amount: 12000,
          category: '薪资',
          date: '2026-08-05',
          note: '',
        ),
        userId: 1,
      );
      expect((await dao.listByUser(1)).single.amount, 12000);
      await dao.update(
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
      final updated = (await dao.listByUser(1)).single;
      expect(updated.amount, 13000);
      expect(updated.note, '调薪');
      expect(await dao.listByUser(2), isEmpty);
      await dao.delete('l1');
      expect(await dao.listByUser(1), isEmpty);
    });
  });

  group('ReadingDao', () {
    test('增删改查', () async {
      final dao = ReadingDao();
      await dao.insert(
        NotebookReading(
          id: 'r1',
          title: '三体',
          author: '刘慈欣',
          status: 'reading',
          rating: 5,
          category: '科幻',
          note: '',
        ),
        userId: 1,
      );
      expect((await dao.listByUser(1)).single.title, '三体');
      await dao.update(
        NotebookReading(
          id: 'r1',
          title: '三体',
          author: '刘慈欣',
          status: 'done',
          rating: 5,
          category: '科幻',
          note: '读完',
        ),
      );
      final updated = (await dao.listByUser(1)).single;
      expect(updated.status, 'done');
      expect(updated.note, '读完');
      await dao.delete('r1');
      expect(await dao.listByUser(1), isEmpty);
    });
  });

  group('TripDao', () {
    test('三层级联 round-trip 与 totalCost', () async {
      final dao = TripDao();
      final trip = NotebookTrip(
        id: 't1',
        title: '杭州三日',
        city: '杭州',
        homeCity: '上海',
        startDate: '2026-08-10',
        endDate: '2026-08-12',
        intercityTransport: TripTransport(
          mode: '高铁',
          isRoundTrip: true,
          amount: 73,
        ),
        days: [
          TripDay(
            date: '2026-08-10',
            label: 'D1',
            checkpoints: [
              TripCheckpoint(
                name: '西湖',
                billings: [TripBilling(type: '门票', amount: 0)],
              ),
              TripCheckpoint(
                name: '灵隐寺',
                transport: TripTransport(mode: '打车', amount: 30),
                billings: [TripBilling(type: '门票', amount: 45)],
                done: true,
                rating: 4,
              ),
            ],
          ),
        ],
      );
      await dao.insert(trip, userId: 1);

      final restored = (await dao.listByUser(1)).single;
      expect(restored.title, '杭州三日');
      expect(restored.homeCity, '上海');
      expect(restored.intercityTransport!.amount, 73);
      expect(restored.days.single.checkpoints, hasLength(2));
      final cp = restored.days.single.checkpoints[1];
      expect(cp.name, '灵隐寺');
      expect(cp.done, isTrue);
      expect(cp.rating, 4);
      expect(cp.transport!.mode, '打车');
      expect(cp.billings.single.amount, 45);
      // totalCost = 城际73*2 + 门票45 = 191（打卡点内交通不计入，见模型 getter）
      expect(restored.totalCost, 191);

      await dao.delete('t1');
      expect(await dao.listByUser(1), isEmpty);
    });

    test('user_id 隔离', () async {
      final dao = TripDao();
      await dao.insert(
        NotebookTrip(id: 't1', title: '行程', days: const []),
        userId: 1,
      );
      expect(await dao.listByUser(2), isEmpty);
    });
  });

  group('StudyDao', () {
    test('课程与记录级联 round-trip、更新替换记录', () async {
      final dao = StudyDao();
      await dao.insert(
        NotebookCourse(
          id: 'c1',
          title: 'Flutter',
          status: 'learning',
          progress: 40,
          records: [
            StudyRecord(
              id: 'r1',
              title: '状态管理',
              content: 'Provider',
              createdAt: DateTime(2026, 8, 1),
            ),
            StudyRecord(
              id: 'r2',
              title: '路由',
              content: 'GoRouter',
              createdAt: DateTime(2026, 8, 2),
            ),
          ],
        ),
        userId: 1,
      );

      var course = (await dao.listByUser(1)).single;
      expect(course.records, hasLength(2));
      expect(course.records[1].content, 'GoRouter');

      await dao.update(course.copyWith(
        progress: 80,
        records: [
          course.records.first.copyWith(title: '状态管理（复习）'),
        ],
      ));
      course = (await dao.listByUser(1)).single;
      expect(course.progress, 80);
      expect(course.records, hasLength(1));
      expect(course.records.single.title, '状态管理（复习）');

      await dao.delete('c1');
      expect(await dao.listByUser(1), isEmpty);
    });
  });

  group('RecipeDao', () {
    test('配料/步骤 JSON 列 round-trip', () async {
      final dao = RecipeDao();
      await dao.insert(
        NotebookRecipe(
          id: 'r1',
          name: '红烧肉',
          category: '荤菜',
          ingredients: const ['五花肉', '冰糖'],
          steps: const ['焯水', '炖 1 小时'],
          difficulty: 'hard',
          rating: 5,
          note: '外婆菜谱',
        ),
        userId: 1,
      );
      final restored = (await dao.listByUser(1)).single;
      expect(restored.ingredients, ['五花肉', '冰糖']);
      expect(restored.steps, ['焯水', '炖 1 小时']);
      expect(restored.difficulty, 'hard');
      expect(restored.note, '外婆菜谱');

      await dao.update(
        NotebookRecipe(
          id: 'r1',
          name: '红烧肉',
          category: '荤菜',
          ingredients: const ['五花肉', '冰糖'],
          steps: const ['焯水', '炖 1 小时'],
          difficulty: 'hard',
          rating: 5,
          note: '已复刻',
        ),
      );
      expect((await dao.listByUser(1)).single.note, '已复刻');
      await dao.delete('r1');
      expect(await dao.listByUser(1), isEmpty);
    });
  });
}
