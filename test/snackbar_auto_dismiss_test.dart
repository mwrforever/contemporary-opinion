import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('撤销 SnackBar 在 duration(5s) 后自动消失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已删除'),
                    duration: Duration(seconds: 5),
                  ),
                ),
                child: const Text('delete'),
              ),
            ),
          ),
        ),
      ),
    );

    // 触发 SnackBar
    await tester.tap(find.text('delete'));
    await tester.pump();
    expect(find.text('已删除'), findsOneWidget); // 当下应可见

    // 让进入动画（约 250ms）完成、duration 定时器就绪
    await tester.pumpAndSettle();

    // <5s 时仍应可见：证明 duration 实际大于默认的 4s。
    // 若有人误删 duration 字段（回落默认 4s），此处会变红，起到回归保护作用。
    await tester.pump(const Duration(milliseconds: 4500));
    expect(find.text('已删除'), findsOneWidget);

    // 跨过「进入动画 + 5s duration」总时长，并预留退出动画余量，
    // 让 duration 定时器触发并完成退出动画（pump 需越过 5s 边界，否则退出动画不会被 pump 完成）。
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text('已删除'), findsNothing); // 已自动消失
  });
}
