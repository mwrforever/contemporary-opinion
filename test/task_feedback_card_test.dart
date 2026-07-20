import 'package:daily_planner/theme/app_theme.dart';
import 'package:daily_planner/widgets/task_feedback_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TaskFeedbackCard] 组件测试（T4 增量）。
///
/// 覆盖：
///  - 三态（success / delete / undo）各自渲染正确文案与图标
///  - 撤销 action 点击触发 onAction
///  - ~3.3s 后自动移除（进入 ~280ms + 停留 3s + 退出 ~280ms）
///  - 卡片以应用级 Overlay 呈现，不阻塞页面其它交互
///
/// 动画时序提示：停留 3s 后才 reverse，约 3.56s 才真正 remove。
/// 收尾用 `pump(4s)` 越过边界再 `pumpAndSettle()`，避免卡在退出动画边界。
void main() {
  Future<void> _pump(
    WidgetTester tester, {
    required FeedbackType type,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => TaskFeedbackCard.show(
                context,
                type: type,
                message: message,
                actionLabel: actionLabel,
                onAction: onAction,
              ),
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    );
  }

  group('TaskFeedbackCard - 三态渲染', () {
    testWidgets('success 态渲染正确文案与图标', (tester) async {
      await _pump(tester, type: FeedbackType.success, message: '已添加 2 个任务');
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('已添加 2 个任务'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('delete 态渲染正确文案与图标', (tester) async {
      await _pump(tester, type: FeedbackType.delete, message: '已删除');
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('已删除'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('undo 态渲染正确文案与图标', (tester) async {
      await _pump(tester, type: FeedbackType.undo, message: '已撤销');
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('已撤销'), findsOneWidget);
      expect(find.byIcon(Icons.undo_outlined), findsOneWidget);
    });
  });

  group('TaskFeedbackCard - 撤销 action', () {
    testWidgets('点击撤销 action 触发 onAction', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        type: FeedbackType.delete,
        message: '已删除',
        actionLabel: '撤销',
        onAction: () => tapped = true,
      );
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('已删除'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pump();
      expect(tapped, isTrue, reason: '撤销按钮应触发 onAction 回调');
    });
  });

  group('TaskFeedbackCard - 自动消失', () {
    testWidgets('卡片在 ~3.3s 后自动移除', (tester) async {
      await _pump(
        tester,
        type: FeedbackType.delete,
        message: '已删除',
        actionLabel: '撤销',
        onAction: () {},
      );
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('已删除'), findsOneWidget); // 当下可见

      // 关键：先 pumpAndSettle 让进入动画(~280ms)完成，从而把 3s 停留定时器
      // 正确地挂在 t≈280ms（而非被单次 pump(4s) 跳变重排在 t=4s，导致永不触发）。
      await tester.pumpAndSettle();
      // 跨过 进入(~280ms) + 停留 3s + 退出(~280ms) ≈ 3.56s 边界。
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已删除'), findsNothing, reason: '超时后应自动移除');
    });
  });

  group('TaskFeedbackCard - 不阻塞页面交互', () {
    testWidgets('卡片出现时页面其它按钮仍可按', (tester) async {
      var otherTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => TaskFeedbackCard.show(
                      context,
                      type: FeedbackType.delete,
                      message: '已删除',
                      actionLabel: '撤销',
                      onAction: () {},
                    ),
                    child: const Text('触发'),
                  ),
                ),
                const SizedBox(height: 200),
                ElevatedButton(
                  onPressed: () => otherTapped = true,
                  child: const Text('其他按钮'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('已删除'), findsOneWidget);
      // 反馈卡片是顶部 Overlay，不应拦截下方按钮的点击。
      await tester.tap(find.text('其他按钮'));
      await tester.pump();
      expect(otherTapped, isTrue, reason: 'Overlay 反馈不阻塞页面其它交互');
    });
  });
}
