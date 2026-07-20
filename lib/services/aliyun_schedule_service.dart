import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/aliyun_config.dart';
import '../models/task.dart';
import '../prompts/prompt_loader.dart';
import 'nlp_parser.dart';

/// 云端排期模型返回的单条结构化任务（尚未持久化为 [Task]）。
class ScheduledTask {
  final String title;
  final DateTime? scheduledTime;
  final int durationMinutes;
  final String? resource;
  final RepeatType repeat;
  final List<int> customWeekdays;
  final String? note;
  final int? countdownSeconds;
  final int? ringSeconds;

  const ScheduledTask({
    required this.title,
    this.scheduledTime,
    this.durationMinutes = 0,
    this.resource,
    this.repeat = RepeatType.none,
    this.customWeekdays = const [],
    this.note,
    this.countdownSeconds,
    this.ringSeconds,
  });

  /// 转换为可持久化的 [Task]。冲突状态由调用方（冲突检测）决定，这里默认 none/effective。
  Task toTask({
    required String id,
    required int notificationId,
    required DateTime createdAt,
  }) =>
      Task(
        id: id,
        title: title,
        scheduledTime: scheduledTime,
        repeat: repeat,
        customWeekdays: customWeekdays,
        resource: resource,
        durationMinutes: durationMinutes,
        countdownSeconds: countdownSeconds,
        ringSeconds: ringSeconds,
        source: TaskSource.voice,
        createdAt: createdAt,
        notificationId: notificationId,
      );

  @override
  String toString() =>
      'ScheduledTask(title=$title, time=$scheduledTime, dur=$durationMinutes, resource=$resource, repeat=$repeat, ring=$ringSeconds)';
}

/// 阿里云排期服务：语音转写文本 → 结构化任务表。
///
/// 模型：通义千问 `qwen3.7-max-2026-05-17`（百炼），经 DashScope OpenAI 兼容接口调用，
/// 要求 JSON 结构化输出。该模型为「仅思考模式」，enable_thinking 必须为 true（设 false 会被
/// 服务端拒绝返回 400）。开启思考后响应可能携带思考链（`<think>...</think>` 或 reasoning_content），
/// 因此所有解析路径均经 [_extractJsonText] 剥离思考链（`<think>...</think>` 或
/// reasoning_content）后再 jsonDecode，保证 JSON 稳定。
/// 失败时退化为本地 [NlpParser]，保证离线/限流可用。
class AliyunScheduleService {
  final String apiKey;
  final String model;
  final String endpoint;
  final http.Client _client;

  AliyunScheduleService({
    required this.apiKey,
    this.model = AliyunConfig.scheduleModel,
    this.endpoint = AliyunConfig.chatCompletionsUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// 将转写文本转为结构化任务列表。
  ///
  /// [transcript] 语音识别文本；[existing] 现有任务（作为上下文，帮助模型避免明显冲突）。
  /// 任何云端异常/非 200/JSON 非法 → 退化到本地启发式解析。
  Future<List<ScheduledTask>> schedule(
    String transcript, {
    List<Task> existing = const [],
    DateTime? now,
  }) async {
    final text = transcript.trim();
    if (text.isEmpty) return const [];
    final ref = now ?? DateTime.now();

    final keyConfigured = apiKey.isNotEmpty;
    print('[LLM][schedule] ===== 开始解析 =====');
    print('[LLM][schedule] 输入文本: $text');
    print('[LLM][schedule] apiKey已配置=$keyConfigured, model=$model');
    if (!keyConfigured) {
      print('[LLM][schedule] ⚠️ apiKey 为空 → 将直接走本地 NlpParser 兜底（不会调用云端）');
    }

    try {
      final resp = await _callModel(text, existing, ref);
      print('[LLM][schedule] >>> 云端模型原始返回(RAW) <<<');
      print(resp);
      final parsed = parseJson(resp, now: ref);
      print('[LLM][schedule] 解析得到任务数=${parsed.length}');
      if (parsed.isNotEmpty) {
        print('[LLM][schedule] >>> 云端解析出的标题 <<<');
        for (final t in parsed) {
          print('  - title="${t.title}" | 时间=${t.scheduledTime} | 响铃=${t.ringSeconds} | 倒计时=${t.countdownSeconds}');
        }
        return parsed;
      }
      // 模型返回空 tasks → 退化为本地解析
      print('[LLM][schedule] 云端返回空 tasks → 退化为本地 NlpParser');
      final fb = _fallback(text);
      _logFallback(fb);
      return fb;
    } catch (e) {
      print('[LLM][schedule] 云端调用异常 → 退化为本地 NlpParser: $e');
      final fb = _fallback(text);
      _logFallback(fb);
      return fb;
    }
  }

  void _logFallback(List<ScheduledTask> fb) {
    print('[LLM][schedule] >>> 本地兜底(NlpParser)标题 <<<');
    for (final t in fb) {
      print('  - title="${t.title}" | 时间=${t.scheduledTime} | 响铃=${t.ringSeconds}');
    }
  }

  /// 通用结构化解析：给定 [systemPrompt] 与 [transcript]，调用模型并以
  /// `json_object` 模式返回解码后的 JSON 根节点（Map / List），失败时返回 null。
  ///
  /// 供记事本语音解析复用同一云端模型（与任务排期共用 DashScope Key）。
  /// 调用方负责把返回的结构化数据映射为对应的记事本条目模型。
  Future<dynamic> parseWithPrompt(
    String systemPrompt,
    String transcript, {
    String? tag,
    DateTime? now,
  }) async {
    final text = transcript.trim();
    final scope = tag ?? 'notebook';
    if (text.isEmpty) return null;
    final keyConfigured = apiKey.isNotEmpty;
    print('[LLM][$scope] ===== 开始解析 =====');
    print('[LLM][$scope] 输入文本: $text');
    print('[LLM][$scope] apiKey已配置=$keyConfigured');
    if (!keyConfigured) {
      print('[LLM][$scope] ⚠️ apiKey 为空 → 云端调用会失败，最终退化为本地/空');
    }
    try {
      final body = jsonEncode({
        'model': model,
        'response_format': {'type': 'json_object'},
        'temperature': 0.2,
        'enable_thinking': true,
        'messages': [
          {
            'role': 'system',
            'content': '$systemPrompt\n${_timeContextBlock(now ?? DateTime.now())}',
          },
          {'role': 'user', 'content': text},
        ],
      });
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode != 200) {
        print('[LLM][$scope] ⚠️ 云端返回非200(${response.statusCode}) → 返回 null(调用方退化)');
        return null;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        print('[LLM][$scope] ⚠️ choices 为空 → 返回 null');
        return null;
      }
      final message = choices.first['message'] as Map<String, dynamic>;
      final content = message['content'] as String;
      print('[LLM][$scope] >>> 云端模型原始返回(RAW) <<<');
      print(content);
      final decodedContent = jsonDecode(_extractJsonText(content));
      print('[LLM][$scope] 解码后类型=${decodedContent.runtimeType}');
      return decodedContent;
    } catch (e) {
      print('[LLM][$scope] 云端调用异常 → 返回 null(调用方退化): $e');
      return null;
    }
  }

  /// 调用云端排期模型，返回模型原始 content 文本。
  ///
  /// 系统提示词取自 `assets/prompts/` 下任务模块的两个拆分提示词（由 [PromptLoader]
  /// 在应用启动时缓存）：含倒计时且无明显绝对时刻的口语走 [PromptLoader.tasksDelayId]
  /// （延时任务），其余走 [PromptLoader.tasksScheduledId]（设定时间的任务）。任一缺失
  /// 时退路用另一个。若两个都缺失，按设计裁决抛 [StateError]，由 [schedule] 的 catch
  /// 落到本地 [_fallback]，比"报错卡死"更稳健。
  Future<String> _callModel(String transcript, List<Task> existing, DateTime now) async {
    final prompt = _resolveTaskPrompt(transcript);
    print('[LLM][schedule] 选用提示词(promptId)=${(_isDelayIntent(transcript) ? PromptLoader.tasksDelayId : PromptLoader.tasksScheduledId)}');
    if (prompt == null || prompt.isEmpty) {
      throw StateError('task prompt missing');
    }

    final existingCtx = existing.where((t) => t.scheduledTime != null).map((t) {
      final r = t.resource != null ? '，资源=${t.resource}' : '';
      return '- ${t.title} @ ${t.scheduledTime!.toLocal()} (${t.durationMinutes}分钟$r)';
    }).join('\n');

    final system = '$prompt\n${_timeContextBlock(now)}';
    final user = '''
现有任务（仅供参考，避免重复）：
${existingCtx.isEmpty ? '（无）' : existingCtx}

请解析以下口语：
$transcript''';

    final body = jsonEncode({
      'model': model,
      'response_format': {'type': 'json_object'},
      'temperature': 0.2,
      'enable_thinking': true,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    });

    final response = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('DashScope ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('empty choices');
    }
    final message = choices.first['message'] as Map<String, dynamic>;
    final content = message['content'] as String;
    return content;
  }

  /// 按口语意图选择任务提示词：优先按 [_isDelayIntent] 判定走延时/设定时间，
  /// 任一缺失时退路用另一个，保证至少一个可用。
  String? _resolveTaskPrompt(String transcript) {
    final primary = _isDelayIntent(transcript)
        ? PromptLoader.tasksDelayId
        : PromptLoader.tasksScheduledId;
    final secondary = _isDelayIntent(transcript)
        ? PromptLoader.tasksScheduledId
        : PromptLoader.tasksDelayId;
    return PromptLoader.byId(primary)?.prompt ??
        PromptLoader.byId(secondary)?.prompt;
  }

  /// 倒计时短语正则：X(秒|分钟|分|小时|时|天|日)后。
  static final RegExp _countdownRe = RegExp(
    r'(\d{1,3}|[零一二两三四五六七八九十]+)\s*(秒|分钟|分|小时|时|天|日)\s*后',
  );

  /// 判断口语是否为「纯延时任务」：含明确倒计时短语，且无明显绝对时刻词。
  /// 含绝对时刻（今天/明天/周X/点/上午…）的复合口语归为「设定时间的任务」，
  /// 由其提示词按子句分别处理倒计时与绝对时刻。
  static bool _isDelayIntent(String text) {
    final hasCountdown = _countdownRe.hasMatch(text) ||
        RegExp(r'提醒时间|定提醒|倒计时|定个提醒').hasMatch(text);
    if (!hasCountdown) return false;
    final hasAbsolute = RegExp(
      r'今天|今日|今|明天|明日|明|后天|大后天|周|星期|礼拜|月|号|点|上午|下午|晚上|早上|中午|凌晨|傍晚|黄昏',
    ).hasMatch(text);
    return !hasAbsolute;
  }

  /// 生成「当前系统时间」上下文块，追加到 system prompt，确保模型基于真实当前时间
  /// 解析相对时间（今天/明天/下周一/下午3点 等）。这是语音排期正确性的命脉。
  static String _timeContextBlock(DateTime now) {
    final weekday = const [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日'
    ][(now.weekday - 1).clamp(0, 6)];
    final stamp =
        '${now.year}-${_pad2(now.month)}-${_pad2(now.day)} ${_pad2(now.hour)}:${_pad2(now.minute)}';
    return '''
<current_time>
当前系统时间：$stamp（$weekday）
指令：用户口语中的所有相对时间（今天/今日/明天/明日/后天/大后天/下周一/本周X/上午/下午/晚上/凌晨 + 钟点 等）都必须以以上「当前系统时间」为唯一基准推算绝对日期与时间，绝对不可假设其他时间或自行编造。输出 datetime 字段时直接给出换算后的绝对日期时间（格式 yyyy-MM-dd HH:mm）。
</current_time>''';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  List<ScheduledTask> _fallback(String transcript) {
    return NlpParser.parse(transcript)
        .map((p) => ScheduledTask(
              title: p.title,
              scheduledTime: p.scheduledTime,
              repeat: p.repeat,
              customWeekdays: p.customWeekdays,
              resource: p.resource,
              durationMinutes: p.durationMinutes ?? 0,
              countdownSeconds: p.countdownSeconds,
              // 透传本地解析出的响铃时长；为 null 时 ScheduledTask 保持 null，
              // 最终落 Task 时回退全局默认（与云端 ring_seconds 行为一致）。
              ringSeconds: p.ringSeconds,
            ))
        .toList();
  }

  /// 清理模型返回内容：剥离思考链（`<think>...</think>` 或 reasoning_content 包裹文本），
  /// 去除 ```json 围栏，并抽取最外层 JSON 对象/数组文本，保证 jsonDecode 稳健。
  static String _extractJsonText(String raw) {
    var s = raw.trim();
    // 1) 去掉 <think>...</think> 思考块（部分部署会把思考塞进 content）
    s = s.replaceAllMapped(
      RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false),
      (_) => '',
    );
    s = s.trim();
    // 2) 去掉 ```json ... ``` 代码围栏
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r"^```[a-zA-Z]*\n?"), '');
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
      s = s.trim();
    }
    // 3) 截取最外层 {} 或 [] 之间内容
    final objStart = s.indexOf('{');
    final arrStart = s.indexOf('[');
    if (objStart == -1 && arrStart == -1) return s;
    late int start;
    late int end;
    if (objStart == -1) {
      start = arrStart;
      end = s.lastIndexOf(']');
    } else if (arrStart == -1) {
      start = objStart;
      end = s.lastIndexOf('}');
    } else if (objStart < arrStart) {
      start = objStart;
      end = s.lastIndexOf('}');
    } else {
      start = arrStart;
      end = s.lastIndexOf(']');
    }
    if (end > start) return s.substring(start, end + 1);
    return s;
  }

  /// 解析模型返回的 JSON 文本为 [ScheduledTask] 列表（纯函数，便于单测）。
  /// 兼容 {"tasks":[...]} / {"data":[...]} / 裸数组；单条字段缺失时给安全默认值。
  static List<ScheduledTask> parseJson(String jsonString, {DateTime? now}) {
    final base = now ?? DateTime.now();
    try {
      final decoded = jsonDecode(_extractJsonText(jsonString));
      List<dynamic>? list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map) {
        list = decoded['tasks'] as List? ?? decoded['data'] as List?;
      }
      if (list == null) return const [];

      final result = <ScheduledTask>[];
      for (final item in list) {
        if (item is! Map) continue;
        final m = item;
        final rawTitle = m['title'];
        final title = rawTitle is String ? rawTitle.trim() : null;
        if (title == null || title.isEmpty) continue;

        // 相对倒计时：remind_in_seconds（或 remind_in_minutes 折算）
        final secs = _asInt(m['remind_in_seconds'], 0);
        final secsFromMin = _asInt(m['remind_in_minutes'], 0) * 60;
        final totalSeconds = secs > 0 ? secs : secsFromMin;

        // 响铃时长：ring_seconds（null / 0 视为未指定，走全局默认）
        final rawRing = m['ring_seconds'];
        final ringSeconds =
            (rawRing == null || _asInt(rawRing, 0) == 0) ? null : _asInt(rawRing, 0);

        final DateTime? scheduledTime;
        final int? countdownSeconds;
        if (totalSeconds > 0) {
          scheduledTime = base.add(Duration(seconds: totalSeconds));
          countdownSeconds = totalSeconds;
        } else {
          scheduledTime = _parseDateTime(m['datetime'] ?? m['scheduledTime']);
          countdownSeconds = null;
        }

        result.add(ScheduledTask(
          title: title,
          scheduledTime: scheduledTime,
          durationMinutes: _asInt(m['duration_minutes'] ?? m['durationMinutes'], 0),
          resource: _asStringOrNull(m['resource']),
          repeat: _parseRepeat(_asStringOrNull(m['repeat']) ?? 'none'),
          customWeekdays: _asIntList(m['weekdays'] ?? m['customWeekdays']),
          note: _asStringOrNull(m['note']),
          countdownSeconds: countdownSeconds,
          ringSeconds: ringSeconds,
        ));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;

    // 1) ISO / 直接解析
    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    // 2) "yyyy-MM-dd HH:mm" / "yyyy/MM/dd HH:mm"
    final re = RegExp(
        r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{1,2})');
    final m = re.firstMatch(s);
    if (m != null) {
      final dt = DateTime.tryParse(
          '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}T${m.group(4)!.padLeft(2, '0')}:${m.group(5)!.padLeft(2, '0')}:00');
      if (dt != null) return dt;
    }
    // 3) 仅日期 "yyyy-MM-dd"
    final d = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(s);
    if (d != null) {
      final dt = DateTime.tryParse(
          '${d.group(1)}-${d.group(2)!.padLeft(2, '0')}-${d.group(3)!.padLeft(2, '0')}T09:00:00');
      if (dt != null) return dt;
    }
    return null;
  }

  static int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static List<int> _asIntList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => _asInt(e, 0))
          .where((e) => e >= 1 && e <= 7)
          .toList();
    }
    return const [];
  }

  static String? _asStringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static RepeatType _parseRepeat(String s) {
    return switch (s.toLowerCase()) {
      'daily' => RepeatType.daily,
      'weekdays' => RepeatType.weekdays,
      'weekly' => RepeatType.weekly,
      'custom' => RepeatType.custom,
      _ => RepeatType.none,
    };
  }
}
