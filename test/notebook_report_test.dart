import 'package:daily_planner/modules/notebook/widgets/notebook_report.dart';
import 'package:daily_planner/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// 报表纯函数 [buildStatsBuckets] 单元测试（T7，G2）。
///
/// 覆盖：日/月/年三种粒度 + anchor 平移，断言：
///  - 返回的桶数恒为 6；
///  - 桶按 anchor 对齐 [anchor-5 .. anchor]，聚合到正确桶；
///  - 空 date 视为今日（落到今日桶）；
///  - 高度比例由桶值正确决定（数据层）；账本收入/支出分主/副序列堆叠。
///
/// 注：[buildStatsBuckets] 为纯函数，无需 WidgetTester / Binding。
void main() {
  group('buildStatsBuckets - 恒 6 桶', () {
    test('日粒度：桶数恒为 6，且按 anchor 对齐 [anchor-5..anchor]', () {
      final anchor = DateTime(2026, 7, 14);
      final data = <ReportDatum>[
        ReportDatum(date: '2026-07-14', value: 100), // anchor 当天 → index 5
        ReportDatum(date: '2026-07-10', value: 50), // anchor-4 → index 1
      ];
      final buckets = buildStatsBuckets(data, ReportGranularity.day, anchor);

      expect(buckets, hasLength(6), reason: '无论数据多少，桶数必须恒为 6');
      expect(buckets[5].label, '7/14');
      expect(buckets[5].value, 100);
      expect(buckets[1].label, '7/10');
      expect(buckets[1].value, 50);
      // 其余桶应为 0
      expect(buckets[0].value, 0);
      expect(buckets[2].value, 0);
      expect(buckets[3].value, 0);
      expect(buckets[4].value, 0);
    });

    test('日粒度：空 date 视为今日（落在今日桶 index 5）', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day); // 今日
      final data = <ReportDatum>[ReportDatum(date: '', value: 77)];
      final buckets = buildStatsBuckets(data, ReportGranularity.day, anchor);

      expect(buckets, hasLength(6));
      expect(buckets[5].value, 77, reason: '空 date 应 fill 为今日并落入末桶');
      expect(buckets[5].label, DateFormat('M/d').format(today));
      // 其余桶为空
      expect(buckets[0].value, 0);
    });

    test('月粒度：6 个月窗口，按月份聚合', () {
      final anchor = DateTime(2026, 7, 1);
      final data = <ReportDatum>[
        ReportDatum(date: '2026-07-15', value: 200), // index 5
        ReportDatum(date: '2026-03-20', value: 30), // anchor-4 月 → index 1
      ];
      final buckets = buildStatsBuckets(data, ReportGranularity.month, anchor);

      expect(buckets, hasLength(6));
      expect(buckets[5].label, '7月');
      expect(buckets[5].value, 200);
      expect(buckets[1].label, '3月');
      expect(buckets[1].value, 30);
    });

    test('年粒度：6 年窗口，按年聚合', () {
      final anchor = DateTime(2026, 1, 1);
      final data = <ReportDatum>[
        ReportDatum(date: '2026-05-01', value: 500), // index 5
        ReportDatum(date: '2022-08-01', value: 9), // anchor-4 年 → index 1
      ];
      final buckets = buildStatsBuckets(data, ReportGranularity.year, anchor);

      expect(buckets, hasLength(6));
      expect(buckets[5].label, '2026');
      expect(buckets[5].value, 500);
      expect(buckets[1].label, '2022');
      expect(buckets[1].value, 9);
    });

    test('anchor 平移：锚点后移 1 个月，窗口整体平移', () {
      final anchor = DateTime(2026, 8, 1); // 比 7 月后移
      final data = <ReportDatum>[ReportDatum(date: '2026-07-15', value: 42)];
      final buckets = buildStatsBuckets(data, ReportGranularity.month, anchor);

      expect(buckets, hasLength(6));
      // 窗口 [2026-03 .. 2026-08]，2026-07 位于 index 4
      expect(buckets[4].label, '7月');
      expect(buckets[4].value, 42);
    });

    test('高度比例（数据层）：桶值正确反映聚合，主/副序列清晰', () {
      final anchor = DateTime(2026, 7, 14);
      final data = <ReportDatum>[
        ReportDatum(date: '2026-07-14', value: 100), // index 5
        ReportDatum(date: '2026-07-13', value: 50), // index 4
      ];
      final buckets = buildStatsBuckets(data, ReportGranularity.day, anchor);

      expect(buckets[5].value, 100);
      expect(buckets[4].value, 50);
      // 渲染高度 h = value / maxVal * maxH，故两桶高度比 = 值比 = 2:1
      expect(buckets[5].value / buckets[4].value, 2.0,
          reason: '高度比例应由桶值决定');
      // 购物（无 kind）：主序列色为 accent，无副序列
      expect(buckets[5].color, AppTheme.accent);
      expect(buckets[5].secondaryValue, 0);
      expect(buckets[5].secondaryColor, isNull);
    });

    test('账本：收入进主序列、支出进副序列（堆叠），颜色正确', () {
      final anchor = DateTime(2026, 7, 14);
      final data = <ReportDatum>[
        ReportDatum(date: '2026-07-14', value: 120, kind: 'income'),
        ReportDatum(date: '2026-07-14', value: 30, kind: 'expense'),
      ];
      final buckets = buildStatsBuckets(data, ReportGranularity.day, anchor);

      expect(buckets[5].value, 120, reason: '收入 → 主序列');
      expect(buckets[5].secondaryValue, 30, reason: '支出 → 副序列');
      expect(buckets[5].color, AppTheme.ok);
      expect(buckets[5].secondaryColor, AppTheme.danger);
    });
  });
}
