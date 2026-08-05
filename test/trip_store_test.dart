import 'package:daily_planner/models/notebook_trip.dart';
import 'package:daily_planner/services/notebook_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// NotebookStore 的内存测试替身：不依赖 Hive，按 id 维护内存 map。
///
/// 用于验证「打卡点变更后经 updateTrip 持久化」的数据流（T04 R3），
/// 避免 headless 环境下初始化 Hive 盒子。
class FakeNotebookStore extends NotebookStore {
  FakeNotebookStore() : super(userId: 1);

  final Map<String, Map<String, dynamic>> _trips = {};

  @override
  List<NotebookTrip> get trips =>
      _trips.values.map((m) => NotebookTrip.fromJson(m)).toList();

  @override
  Future<void> addTrip(NotebookTrip item) async {
    final map = item.toJson();
    final id = (map['id'] as String?)?.isNotEmpty == true
        ? map['id'] as String
        : 'id_${_trips.length}';
    map['id'] = id;
    _trips[id] = map;
    notifyListeners();
  }

  @override
  Future<void> updateTrip(NotebookTrip trip) async {
    _trips[trip.id] = trip.toJson();
    notifyListeners();
  }

  @override
  Future<void> deleteTrip(String id) async {
    _trips.remove(id);
    notifyListeners();
  }
}

void main() {
  group('FakeNotebookStore - 旅游行程 CRUD 持久化', () {
    late FakeNotebookStore store;

    setUp(() => store = FakeNotebookStore());

    test('addTrip 后 trips 可见', () async {
      await store.addTrip(NotebookTrip(id: 't1', title: '厦门'));
      expect(store.trips, hasLength(1));
      expect(store.trips.first.id, 't1');
    });

    test('updateTrip 持久化「增 / 改 / 删」打卡点（copyWith 数据流）', () async {
      // 初始：1 天 2 打卡点
      await store.addTrip(NotebookTrip(
        id: 't1',
        title: '厦门',
        days: [
          TripDay(label: '第 1 天', checkpoints: [
            TripCheckpoint(name: '鼓浪屿'),
            TripCheckpoint(name: '南普陀'),
          ]),
        ],
      ));

      // —— 新增 ——
      final day0 = store.trips.first.days.first;
      var updated = store.trips.first.copyWith(days: [
        day0.copyWith(
          checkpoints: [...day0.checkpoints, TripCheckpoint(name: '火山岛')],
        ),
      ]);
      await store.updateTrip(updated);
      expect(store.trips.first.checkpointCount, 3);
      expect(store.trips.first.days.first.checkpoints.last.name, '火山岛');

      // —— 编辑（按 name 定位；store 每次读取都会重建实例，不能用引用身份）——
      final cur = store.trips.first;
      final day = cur.days.first;
      final list = List<TripCheckpoint>.from(day.checkpoints);
      final idx = list.indexWhere((c) => c.name == '鼓浪屿');
      list[idx] = list[idx].copyWith(name: '鼓浪屿(夜)', rating: 4);
      updated = cur.copyWith(days: [day.copyWith(checkpoints: list)]);
      await store.updateTrip(updated);
      expect(store.trips.first.days.first.checkpoints.first.name, '鼓浪屿(夜)');
      expect(store.trips.first.days.first.checkpoints, hasLength(3));

      // —— 删除（按 name 过滤）——
      final cur2 = store.trips.first;
      final day2 = cur2.days.first;
      final afterDel = day2.checkpoints.where((c) => c.name != '火山岛').toList();
      updated = cur2.copyWith(days: [day2.copyWith(checkpoints: afterDel)]);
      await store.updateTrip(updated);
      expect(store.trips.first.checkpointCount, 2);
    });

    test('deleteTrip 移除行程', () async {
      await store.addTrip(NotebookTrip(id: 't1', title: 'a'));
      await store.addTrip(NotebookTrip(id: 't2', title: 'b'));
      await store.deleteTrip('t1');
      expect(store.trips, hasLength(1));
      expect(store.trips.first.id, 't2');
    });
  });
}
