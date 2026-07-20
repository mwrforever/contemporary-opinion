import 'secrets.dart';

/// 阿里云接入配置（纯前端 Demo 用）。
///
/// ⚠️ 安全提示：把 API Key 打包进前端仅适合 Demo 与内测。
/// 生产环境务必改为「后端 / 云函数代理」持有密钥，前端只拿短期 token。
///
/// 排期(qwen3.7-max-2026-05-17) 与 语音识别(qwen3-asr-flash) 同属阿里云百炼/DashScope 体系，
/// 共用同一个 [dashscopeApiKey]，因此只需配置一个 key。
/// 若留空，App 自动退回设备端语音识别(speech_to_text) + 本地 NLP 解析，仍可正常使用。
///
/// 请求地址支持两种形态（均为 OpenAI 兼容的 /chat/completions）：
/// - 公网 DashScope：https://dashscope.aliyuncs.com/compatible-mode/v1
/// - 私有 MaaS 部署：形如 https://llm-xxxx.maas.aliyuncs.com/api/v1
/// 默认指向本地私密配置（见 [secrets.dart]，已 gitignore），可用环境变量覆盖。
class AliyunConfig {
  /// DashScope API Key（控制台：https://dashscope.console.aliyun.com/）。
  /// 排期与语音识别都只需它这一个 key。
  static const String dashscopeApiKey = String.fromEnvironment(
    'DASHSCOPE_API_KEY',
    defaultValue: kDashscopeApiKey,
  );

  /// 请求基址（不含末尾 /chat/completions）。默认指向私有 MaaS 部署，
  /// 可用环境变量 DASHSCOPE_BASE_URL 覆盖为其他兼容端点。
  static const String baseUrl = String.fromEnvironment(
    'DASHSCOPE_BASE_URL',
    defaultValue: kDashscopeBaseUrl,
  );

  /// 完整的 chat completions 请求地址。
  static const String chatCompletionsUrl = '$baseUrl/chat/completions';

  /// 排期模型（通义千问）。可用环境变量 DASHSCOPE_SCHEDULE_MODEL 覆盖。
  static const String scheduleModel = String.fromEnvironment(
    'DASHSCOPE_SCHEDULE_MODEL',
    defaultValue: 'qwen3.7-max-2026-05-17',
  );

  /// 语音识别模型（Qwen3-ASR）。可用环境变量 DASHSCOPE_ASR_MODEL 覆盖。
  static const String asrModel = String.fromEnvironment(
    'DASHSCOPE_ASR_MODEL',
    defaultValue: 'qwen3-asr-flash',
  );

  /// 是否已配置云端能力（ASR 与排期共用同一 key）。
  static bool get configured => dashscopeApiKey.isNotEmpty;

  /// 是否已配置云端 ASR（qwen3-asr-flash）。
  static bool get asrConfigured => configured;

  /// 是否已配置云端排期（qwen3.7-max-2026-05-17）。
  static bool get scheduleConfigured => configured;
}
