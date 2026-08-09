import 'package:daily_planner/models/dictionary.dart';
import 'package:daily_planner/models/notebook_trip.dart' as trip;
import 'package:flutter_test/flutter_test.dart';

/// 公共字典单元测试（T9，G4）。
///
/// 覆盖：
///  1. [kTransportModes] / [kBillingTypes] 的取值与顺序（全应用约定）。
///  2. [notebook_trip.dart] 通过 `export ... show` 再导出同源常量，
///     保证旅游行程 / 账本等子功能零改动引用（编译期 + 运行期一致性）。
void main() {
  group('公共字典 - dictionary.dart 取值与顺序', () {
    test('kTransportModes 8 项且顺序正确', () {
      expect(kTransportModes, hasLength(8));
      expect(
        kTransportModes,
        equals(['飞机', '高铁', '火车', '汽车', '地铁', '公交', '打车', '其他']),
      );
    });

    test('kBillingTypes 5 项且顺序正确', () {
      expect(kBillingTypes, hasLength(5));
      expect(
        kBillingTypes,
        equals(['门票', '餐饮', '购物', '交通', '其他']),
      );
    });

    test('kExpenseTypes 支出 9 项且顺序正确', () {
      expect(kExpenseTypes, hasLength(9));
      expect(
        kExpenseTypes,
        equals(['餐饮', '交通', '购物', '居住', '娱乐', '医疗', '教育', '人情往来', '其他']),
      );
    });

    test('kIncomeTypes 收入 6 项且顺序正确', () {
      expect(kIncomeTypes, hasLength(6));
      expect(
        kIncomeTypes,
        equals(['工资', '奖金', '理财', '兼职', '退款', '其他']),
      );
    });

    test('导出常量非空且为不可变列表', () {
      expect(kTransportModes, isA<List<String>>());
      expect(kBillingTypes, isA<List<String>>());
      expect(kExpenseTypes, isA<List<String>>());
      expect(kIncomeTypes, isA<List<String>>());
      // const 列表不可写
      expect(() => kTransportModes.add('新增'), throwsUnsupportedError);
    });
  });

  group('公共字典 - notebook_trip.dart 再导出一致性', () {
    test('notebook_trip 再导出的常量与 dictionary 同源一致', () {
      // notebook_trip.dart: export 'dictionary.dart' show kTransportModes, kBillingTypes;
      // 二者应指向完全相同的底层常量（编译期即可验证再导出存在）。
      expect(trip.kTransportModes, equals(kTransportModes));
      expect(trip.kBillingTypes, equals(kBillingTypes));
      expect(trip.kTransportModes, hasLength(8));
      expect(trip.kBillingTypes, hasLength(5));
    });
  });
}
