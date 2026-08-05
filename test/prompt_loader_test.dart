// PromptLoader 契约测试：任务两份语音提示词随包可加载
import 'package:daily_planner/prompts/prompt_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('加载任务设定时间与延时提示词', () async {
    final loaded = await PromptLoader.loadAll();
    expect(loaded, isNotEmpty);
    expect(PromptLoader.byId(PromptLoader.tasksScheduledId), isNotNull);
    expect(PromptLoader.byId(PromptLoader.tasksDelayId), isNotNull);
  });
}
