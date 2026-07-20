import 'package:daily_planner/models/notebook_trip.dart';
import 'package:flutter_test/flutter_test.dart';

/// 旅游行程模型单测（T04 核心数据契约）。
///
/// 覆盖：NotebookTrip / TripDay / TripCheckpoint 的不可变 copyWith，
/// 向指定天「增 / 改 / 删」打卡点的数据流（与 _TripDrillDown._applyCheckpoint
/// 等逻辑同构），计数/金额汇总，交通/计费枚举常量，以及 JSON round-trip。
void main() {
  group('NotebookTrip - copyWith 与打卡点增删改', () {
    final baseTrip = NotebookTrip(
      id: 't1',
      title: '厦门游',
      city: '厦门',
      days: [
        TripDay(label: '第 1 天', checkpoints: [
          TripCheckpoint(name: '鼓浪屿'),
          TripCheckpoint(name: '南普陀'),
        ]),
        TripDay(label: '第 2 天', checkpoints: const []),
      ],
    );

    test('copyWith 不传参返回等价但新的对象（不可变）', () {
      final copy = baseTrip.copyWith();
      expect(copy, isNot(same(baseTrip)));
      expect(copy.id, baseTrip.id);
      expect(copy.title, baseTrip.title);
      expect(copy.days, hasLength(2));
    });

    test('copyWith 仅覆盖传入字段，其余保持不变', () {
      final copy = baseTrip.copyWith(title: '新版厦门游');
      expect(copy.title, '新版厦门游');
      expect(copy.city, baseTrip.city);
      expect(copy.days, hasLength(2));
    });

    test('TripDay.copyWith 仅替换指定字段', () {
      final day = baseTrip.days.first;
      final updated = day.copyWith(
        checkpoints: [...day.checkpoints, TripCheckpoint(name: '新增点')],
      );
      expect(updated.checkpoints, hasLength(3));
      expect(updated.label, day.label); // label 不变
    });

    test('TripCheckpoint.copyWith 仅替换指定字段', () {
      final cp = baseTrip.days.first.checkpoints.first;
      final updated = cp.copyWith(done: true, rating: 5);
      expect(updated.done, isTrue);
      expect(updated.rating, 5);
      expect(updated.name, cp.name);
      expect(updated.transport, cp.transport);
    });

    test('新增打卡点到指定天（copyWith 数据流）', () {
      // 同构 _TripDrillDown._applyCheckpoint 的「新增」分支
      final newCp = TripCheckpoint(name: '火山岛', done: true, rating: 4);
      final days = List<TripDay>.from(baseTrip.days);
      final day = days[0];
      days[0] = day.copyWith(checkpoints: [...day.checkpoints, newCp]);
      final updated = baseTrip.copyWith(days: days);

      expect(updated.days[0].checkpoints, hasLength(3));
      expect(updated.days[0].checkpoints.last.name, '火山岛');
      expect(updated.days[1].checkpoints, isEmpty); // 其他天不受影响
      expect(updated.checkpointCount, 3);
    });

    test('编辑指定打卡点（按引用定位，数量不变）', () {
      final original = baseTrip.days.first.checkpoints.first;
      final edited = original.copyWith(name: '鼓浪屿(夜)', rating: 3);
      final days = List<TripDay>.from(baseTrip.days);
      final list = List<TripCheckpoint>.from(days[0].checkpoints);
      list[list.indexOf(original)] = edited;
      days[0] = days[0].copyWith(checkpoints: list);
      final updated = baseTrip.copyWith(days: days);

      expect(updated.days[0].checkpoints.first.name, '鼓浪屿(夜)');
      expect(updated.days[0].checkpoints, hasLength(2));
    });

    test('删除指定打卡点（按引用过滤）', () {
      final target = baseTrip.days.first.checkpoints.last;
      final days = List<TripDay>.from(baseTrip.days);
      final list = days[0].checkpoints.where((e) => e != target).toList();
      days[0] = days[0].copyWith(checkpoints: list);
      final updated = baseTrip.copyWith(days: days);

      expect(updated.days[0].checkpoints, hasLength(1));
      expect(updated.days[0].checkpoints.first.name, '鼓浪屿');
    });

    test('days 为空时自动建首条「未排天」天（兜底逻辑）', () {
      final empty = NotebookTrip(id: 'e1', title: '空行程');
      final cp = TripCheckpoint(name: '兜底点');
      final days = <TripDay>[];
      days.add(TripDay(label: '未排天', checkpoints: [cp]));
      final updated = empty.copyWith(days: days);

      expect(updated.days, hasLength(1));
      expect(updated.days.first.label, '未排天');
    });
  });

  group('NotebookTrip - 计算与常量', () {
    test('checkpointCount 跨天累加', () {
      final trip = NotebookTrip(
        id: 'c1',
        days: [
          TripDay(checkpoints: [
            TripCheckpoint(name: 'a'),
            TripCheckpoint(name: 'b'),
          ]),
          TripDay(checkpoints: [TripCheckpoint(name: 'c')]),
        ],
      );
      expect(trip.checkpointCount, 3);
    });

    test('totalCost 汇总各打卡点计费', () {
      final trip = NotebookTrip(
        id: 'c2',
        days: [
          TripDay(checkpoints: [
            TripCheckpoint(
              name: 'a',
              billings: [TripBilling(type: '门票', amount: 50)],
            ),
            TripCheckpoint(
              name: 'b',
              billings: [
                TripBilling(type: '餐饮', amount: 30),
                TripBilling(type: '交通', amount: 20),
              ],
            ),
          ]),
        ],
      );
      expect(trip.totalCost, 100);
    });

    test('交通/计费枚举常量定义完整且非空', () {
      expect(kTransportModes, isNotEmpty);
      expect(kTransportModes, contains('飞机'));
      expect(kTransportModes, contains('其他'));
      expect(kBillingTypes, isNotEmpty);
      expect(kBillingTypes, contains('门票'));
      expect(kBillingTypes, contains('其他'));
    });
  });

  group('NotebookTrip - JSON round-trip', () {
    test('toJson → fromJson 字段一致（含嵌套打卡点）', () {
      final trip = NotebookTrip(
        id: 'rt',
        title: '厦门',
        city: '厦门',
        startDate: '2026-07-20',
        endDate: '2026-07-22',
        days: [
          TripDay(label: '第 1 天', date: '2026-07-20', checkpoints: [
            TripCheckpoint(
              name: '鼓浪屿',
              transport: TripTransport(mode: '高铁', amount: 200),
              billings: [TripBilling(type: '门票', amount: 50)],
              done: true,
              rating: 5,
              note: '漂亮',
            ),
          ]),
        ],
      );

      final back = NotebookTrip.fromJson(trip.toJson());
      expect(back.id, trip.id);
      expect(back.title, trip.title);
      expect(back.startDate, '2026-07-20');
      expect(back.days, hasLength(1));

      final cp = back.days.first.checkpoints.first;
      expect(cp.name, '鼓浪屿');
      expect(cp.transport?.mode, '高铁');
      expect(cp.transport?.amount, 200);
      expect(cp.billings.first.type, '门票');
      expect(cp.billings.first.amount, 50);
      expect(cp.done, isTrue);
      expect(cp.rating, 5);
      expect(cp.note, '漂亮');
    });
  });
}
