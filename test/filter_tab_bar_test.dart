// FilterTabBar 测试：渲染与选中回调
import 'package:daily_planner/widgets/filter_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('点击待办触发选中回调', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterTabBar(
            items: const [
              FilterTabItem(label: '全部', count: 5),
              FilterTabItem(label: '待办', count: 2),
            ],
            selectedIndex: 0,
            onSelected: (i) => selected = i,
          ),
        ),
      ),
    );
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.text('待办'));
    expect(selected, 1);
  });
}
