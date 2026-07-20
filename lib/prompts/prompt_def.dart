/// 提示词所属模块。
enum PromptModule {
  /// 任务模块
  tasks,

  /// 记事本模块
  notebook,
}

/// 提示词触发方式。
enum PromptType {
  /// 语音录入流程（驱动 LLM 排期/解析管线）
  voice,
}

/// 提示词定义：提示词系统的唯一模型。
///
/// 提示词以只读 YAML 资源随包分发（[PromptLoader] 加载）。
/// 按范围决策，本版不提供运行时审批页——打包内的提示词即视为设计阶段已批准，
/// 因此此处**无 `approved` 字段、无审批闸门**：语音流程在调用 LLM 前直接取用
/// [PromptDef.prompt]，不校验任何批准状态。
class PromptDef {
  /// 唯一键，对应 `assets/prompts/<id>.yaml` 的文件名（去掉扩展名）。
  final String id;

  /// 所属模块。
  final PromptModule module;

  /// 记事本子功能（仅 notebook 模块使用，如 shopping / ledger / reading /
  /// trip / study / recipe）；任务模块为 null。
  final String? subFunction;

  /// 触发方式。
  final PromptType type;

  /// 实际注入 LLM 的 system 内容（来自 YAML 的 `prompt` 字段）。
  final String prompt;

  /// 人类可读的描述（调试/文档用途）。
  final String description;

  const PromptDef({
    required this.id,
    required this.module,
    required this.type,
    required this.prompt,
    required this.description,
    this.subFunction,
  });

  @override
  String toString() =>
      'PromptDef(id=$id, module=$module, subFunction=$subFunction, type=$type)';
}
