// 枚举折叠组件测试：countChipsInRows 换行计数纯函数 + 折叠/展开交互
import 'package:daily_planner/modules/notebook/widgets/enum_chips_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

void main() {
  group('countChipsInRows - 模拟换行计数', () {
    test('空列表返回 0', () {
      expect(
        countChipsInRows(labels: [], maxRows: 2, maxWidth: 318, style: _style),
        0,
      );
    });

    test('一行放得下时返回全部', () {
      expect(
        countChipsInRows(
            labels: ['短', '更短'], maxRows: 2, maxWidth: 318, style: _style),
        2,
      );
    });

    test('两行裁剪：300px 下 11 项购物枚举返回 7（第 8 项起换到第三行被折叠）', () {
      const labels = [
        '生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居', '美妆个护',
        '母婴', '运动户外', '书籍文具', '药品保健', '其他',
      ];
      final actual = countChipsInRows(
          labels: labels, maxRows: 2, maxWidth: 300, style: _style);
      expect(
        actual,
        7,
      );
    });

    test('maxRows=1 时只返回第一行数量', () {
      const labels = ['生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居'];
      expect(
        countChipsInRows(labels: labels, maxRows: 1, maxWidth: 300, style: _style),
        3,
      );
    });
  });

  testWidgets('EnumChipsField 折叠态显示展开按钮，点击展开后收起', (tester) async {
    const values = [
      '生鲜食品', '日用品', '服饰鞋包', '数码家电', '家居', '美妆个护',
      '母婴', '运动户外', '书籍文具', '药品保健', '其他',
    ];
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: EnumChipsField(
            values: values,
            selected: '生鲜食品',
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    ));
    expect(find.textContaining('展开全部'), findsOneWidget);
    // 点击未折叠的「日用品」触发回调
    await tester.tap(find.text('日用品'));
    expect(picked, '日用品');
    // 展开
    await tester.tap(find.textContaining('展开全部'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('药品保健'), findsOneWidget);
  });

  testWidgets('MultiEnumChipsField 多选：点选加入、再点取消、不影响其他', (tester) async {
    const values = ['门票', '餐饮', '购物', '交通', '其他'];
    final selected = <String>{};
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: SizedBox(
            width: 400,
            child: MultiEnumChipsField(
              values: values,
              selected: selected,
              onChanged: (v) => setState(() {
                selected
                  ..clear()
                  ..addAll(v);
              }),
            ),
          ),
        ),
      ),
    ));
    // 依次点选两项
    await tester.tap(find.text('门票'));
    await tester.pumpAndSettle();
    expect(selected, {'门票'});
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    expect(selected, {'门票', '交通'});
    // 再点取消其中一项
    await tester.tap(find.text('门票'));
    await tester.pumpAndSettle();
    expect(selected, {'交通'});
  });
}
