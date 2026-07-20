import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import 'prompt_def.dart';

/// 提示词加载器：从打包的只读资源 `assets/prompts/*.yaml` 读取并构造
/// [PromptDef] 列表。
///
/// 加载结果会在进程内缓存（[all] / [byId] / [bySubFunction]），供各语音流程
/// 在调用云端模型前同步读取。本版不提供运行时审批页，故直接以 YAML 内容为
/// 准（打包资源即视为已批准），无外部审批态合并。
class PromptLoader {
  /// 实际随包分发的提示词 YAML 清单（设计阶段已批准落地）。
  ///
  /// 注意：仅 `voice` 类；manual 类提示词已删除（手动录入不接 LLM）。
  static const List<String> _ids = [
    'tasks_voice_scheduled',
    'tasks_voice_delay',
    'notebook_voice_shopping',
    'notebook_voice_ledger',
    'notebook_voice_reading',
    'notebook_voice_trip',
    'notebook_voice_study',
    'notebook_voice_recipe',
  ];

  /// 任务模块「设定时间的任务」提示词 id。
  static const String tasksScheduledId = 'tasks_voice_scheduled';

  /// 任务模块「延时任务」提示词 id。
  static const String tasksDelayId = 'tasks_voice_delay';

  static List<PromptDef>? _cache;

  /// 已加载的全部提示词（不可变快照）。未加载时为空列表。
  static List<PromptDef> get all =>
      List.unmodifiable(_cache ?? const <PromptDef>[]);

  /// 按 [id] 取提示词（如 `tasks_voice`），未找到返回 null。
  static PromptDef? byId(String id) =>
      all.where((p) => p.id == id).firstOrNull;

  /// 按记事本子功能取提示词（如 `shopping`），未找到返回 null。
  static PromptDef? bySubFunction(String subFunction) => all
      .where((p) => p.module == PromptModule.notebook)
      .where((p) => p.subFunction == subFunction)
      .firstOrNull;

  /// 加载全部提示词 YAML 并缓存。幂等：重复调用只返回同一份缓存。
  static Future<List<PromptDef>> loadAll() async {
    if (_cache != null) return _cache!;
    final defs = <PromptDef>[];
    for (final id in _ids) {
      final yamlStr = await rootBundle.loadString('assets/prompts/$id.yaml');
      final doc = loadYaml(yamlStr);
      if (doc is Map) {
        defs.add(_fromYaml(doc));
      }
    }
    _cache = defs;
    return defs;
  }

  /// 将单个 YAML 文档解析为 [PromptDef]（纯函数，便于单测）。
  static PromptDef _fromYaml(Map doc) {
    final module = switch (doc['module']?.toString() ?? 'tasks') {
      'notebook' => PromptModule.notebook,
      _ => PromptModule.tasks,
    };
    // 仅 voice 类；manual 类提示词已删除（手动录入不接 LLM）。
    final type = PromptType.voice;
    return PromptDef(
      id: doc['id']?.toString() ?? '',
      module: module,
      subFunction: doc['sub_function']?.toString(),
      type: type,
      prompt: (doc['prompt']?.toString() ?? '').trim(),
      description: doc['description']?.toString() ?? '',
    );
  }
}
