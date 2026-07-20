import '../models/notebook_ledger.dart';
import '../models/notebook_reading.dart';
import '../models/notebook_recipe.dart';
import '../models/notebook_shopping.dart';
import '../models/notebook_study.dart';
import '../models/notebook_trip.dart';
import '../prompts/prompt_loader.dart';
import 'aliyun_schedule_service.dart';

/// 记事本语音解析服务：复用任务排期同一云端模型（[AliyunScheduleService]）将
/// 语音转写文本结构化为各子功能的草稿条目。
///
/// 设计要点：
/// - 每个子功能取对应 prompt（[PromptLoader.bySubFunction]），以 `json_object`
///   模式调用模型，返回解码后的 JSON 根节点。
/// - 多数子功能输出 `{"items":[...]}`；旅游输出 `{"trip":{...}}`（单条嵌套对象）。
/// - 解析失败（无 key / 模型不可用）→ 返回空列表或 null，由 UI 引导手动录入。
/// - 课程维度的学习记录：LLM 只产出记录（不含课程名），课程由 App 绑定。
class NotebookVoiceService {
  final AliyunScheduleService _schedule;

  NotebookVoiceService({required this._schedule});

  Future<List<NotebookShopping>> parseShopping(String transcript) =>
      _parseList(transcript, 'shopping', NotebookShopping.fromJson);

  Future<List<NotebookLedger>> parseLedger(String transcript) =>
      _parseList(transcript, 'ledger', NotebookLedger.fromJson);

  Future<List<NotebookReading>> parseReading(String transcript) =>
      _parseList(transcript, 'reading', NotebookReading.fromJson);

  Future<List<NotebookRecipe>> parseRecipe(String transcript) =>
      _parseList(transcript, 'recipe', NotebookRecipe.fromJson);

  /// 旅游：单条嵌套行程对象（非列表）。
  Future<NotebookTrip?> parseTrip(String transcript) async {
    final def = PromptLoader.bySubFunction('trip');
    if (def == null) return null;
    final data = await _schedule.parseWithPrompt(def.prompt, transcript, tag: 'notebook:trip');
    if (data is! Map) return null;
    final trip = data['trip'];
    if (trip is! Map) return null;
    return NotebookTrip.fromJson(Map<String, dynamic>.from(trip));
  }

  /// 学习记录：LLM 只产出记录（不含课程名），课程由调用方绑定。
  Future<List<StudyRecord>> parseStudy(String transcript) async {
    final def = PromptLoader.bySubFunction('study');
    if (def == null) return <StudyRecord>[];
    final data = await _schedule.parseWithPrompt(def.prompt, transcript, tag: 'notebook:study');
    if (data is! Map) return <StudyRecord>[];
    final items = data['items'];
    if (items is! List) return <StudyRecord>[];
    return items
        .whereType<Map>()
        .map((e) => StudyRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 通用列表解析：从返回 JSON 的 `items` 数组映射为强类型列表。
  Future<List<T>> _parseList<T>(
    String transcript,
    String sub,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final def = PromptLoader.bySubFunction(sub);
    if (def == null) return <T>[];
    final data = await _schedule.parseWithPrompt(def.prompt, transcript, tag: 'notebook:$sub');
    if (data is! Map) return <T>[];
    final items = data['items'];
    if (items is! List) return <T>[];
    return items
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
