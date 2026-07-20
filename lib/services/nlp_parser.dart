import '../models/task.dart';

/// 解析结果（可能为 null scheduledTime，表示"待安排"的 backlog 任务）
class ParsedTask {
  final String title;
  final DateTime? scheduledTime;
  final RepeatType repeat;
  final List<int> customWeekdays;
  final int? countdownMinutes;
  final int? countdownSeconds;
  final String? resource;
  final int? durationMinutes;
  /// 响铃时长（秒）。为 null 时回退全局默认设置。来源于云端模型 `ring_seconds`
  /// 或本地口语「X秒(钟)的提醒时间 / 响铃X秒 / 提醒时长X秒」的识别。
  final int? ringSeconds;

  const ParsedTask({
    required this.title,
    this.scheduledTime,
    this.repeat = RepeatType.none,
    this.customWeekdays = const [],
    this.countdownMinutes,
    this.countdownSeconds,
    this.resource,
    this.durationMinutes,
    this.ringSeconds,
  });

  @override
  String toString() =>
      'ParsedTask(title=$title, time=$scheduledTime, repeat=$repeat, wd=$customWeekdays, resource=$resource, dur=$durationMinutes, ring=$ringSeconds)';
}

/// 本地中文时间表达式解析器（纯前端、零配置、无后端 AI）。
///
/// 支持：
///  - 绝对时间：今天/明天/后天/大后天 + 上午/下午/晚上 + X点(半)/(X:YY)
///  - 相对时间：X分钟后 / X小时后 / X天后（折算为倒计时绝对时间）
///  - 重复：每天 / 工作日 / 每周X / 周一三五（自定义）/ 每周（无星期则按设定日）
///           / 睡前 → 每天 + 23:00
///  - 资源：在/用/占用/使用 + 资源名（取首个）
///  - 时长：持续/历时/花费/长达 + N 分钟|小时（占用时段，与倒计时严格分离）
///  - 未明确时间的任务 → 进入"待安排"（scheduledTime = null），由用户后续规划
class NlpParser {
  NlpParser._();

  /// 资源抽取：在/用/占用/使用/借/租 + 资源名（取首个），由后续动作动词截断。
  static final RegExp _resourceRe = RegExp(
    r'(?:在|用|占用|使用|借用|租|租用)\s*([\u4e00-\u9fa5A-Za-z0-9]+?)(?=(?:开会|上课|工作|锻炼|跑步|睡觉|吃药|倒垃圾|健身|看书|散步|买|写|打电话|见|洗澡|吃饭|学习|出发|处理|去|做|打|上班|下班|喝|聊|复习|开|吃|玩|运动|读书|练|走|回|到|完成|睡觉|休息|开会))',
  );

  /// 时长抽取（占用时段）：持续/历时/花费/长达 + N (分钟|小时|分|时)。
  /// 与倒计时（含"后"/"提醒时间"）严格区分，互不误吞。
  static final RegExp _durationRe = RegExp(
    r'(?:持续|历时|花费|长达)\s*(\d{1,3}|[零一二两三四五六七八九十]+)\s*(分钟|分|小时|个小时|时)',
  );

  static List<ParsedTask> parse(String raw, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final results = <ParsedTask>[];
    // 以中英文句号/换行/分号切分句子
    final clauses = raw
        .split(RegExp(r'[。!?！？\n;；]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    for (final clause in clauses) {
      final parsed = _parseClause(clause, base);
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  static ParsedTask? _parseClause(String clause, DateTime now) {
    var text = clause;
    var repeat = RepeatType.none;
    var customWeekdays = const <int>[];
    var bedtime = false; // 睡前/睡觉前 → daily + 23:00
    int? countdownMinutes;
    DateTime? datePart;
    var dateExplicit = false;
    int? hour;
    var minute = 0;
    var hasTime = false;

    // 1) 日期关键词
    if (text.contains('大后天')) {
      datePart = _addDays(now, 3);
      dateExplicit = true;
    } else if (text.contains('后天')) {
      datePart = _addDays(now, 2);
      dateExplicit = true;
    } else if (text.contains(RegExp(r'明天|明日|明'))) {
      datePart = _addDays(now, 1);
      dateExplicit = true;
    } else if (text.contains(RegExp(r'今天|今日|今'))) {
      datePart = DateTime(now.year, now.month, now.day);
      dateExplicit = true;
    }

    // 1b) 一次性相对星期日期：下周一 / 这周五 / 上周X → 解析为具体日期，不重复。
    //     必须在 Step5 重复判定前移除原文，否则「下周一」会被 _extractWeekdays
    //     抽出「一」并在 `else if (wd.isNotEmpty)` 分支误判为「每周一」重复。
    final relWdMatch = _relativeWeekdayRe.firstMatch(text);
    if (relWdMatch != null) {
      final relDate = _resolveRelativeWeekday(text, now);
      if (relDate != null) {
        datePart = relDate;
        dateExplicit = true;
        // 连同量词(下/这/上)+周/星期 整体移除，避免标题残留「下」等
        text = text.replaceFirst(relWdMatch.group(0)!, '');
      }
    }

    // 2) 相对时间：X(分钟|小时|天)后
    final rel = RegExp(
        r'(半|\d{1,3}|[零一二两三四五六七八九十]+)\s*(分钟|分|min|小时|个小时|时|天|日)\s*后');
    final rm = rel.firstMatch(text);
    if (rm != null) {
      final numStr = rm.group(1)!;
      final unit = rm.group(2)!;
      int mins;
      if (numStr == '半') {
        // "半" = 半个时间单位：半小时=30分、半天=12小时(720分)
        if (unit.contains('小时') || unit == '时') {
          mins = 30;
        } else if (unit.contains('天') || unit == '日') {
          mins = 720;
        } else {
          mins = 30;
        }
      } else {
        final val = _parseInt(numStr) ?? 1;
        if (unit.contains('分钟') || unit == '分' || unit == 'min') {
          mins = val;
        } else if (unit.contains('小时') || unit == '时') {
          mins = val * 60;
        } else {
          mins = val * 1440;
        }
      }
      countdownMinutes = mins;
      text = text.replaceFirst(rm.group(0)!, '');
    }

    // 2b) 秒级倒计时：X秒后 / 提醒时间(为)?X秒/分/时
    int? countdownSeconds;
    final secMatch = _parseSeconds(text);
    if (secMatch != null) {
      countdownSeconds = secMatch.$1;
      text = text.replaceFirst(secMatch.$2, '');
    }

    // 2c) 响铃时长：X秒(钟)的提醒时间 / 响铃X秒 / 提醒时长X秒（与倒计时严格区分）。
    //     注意：「提醒时间为X秒」(数字在「提醒时间」之后) 已在 2b 判为倒计时；
    //     此处仅处理「X秒的提醒时间」(数字在前) 这类口语，映射为 ringSeconds。
    int? ringSeconds;
    final ringMatch = _parseRingSeconds(text);
    if (ringMatch != null) {
      ringSeconds = ringMatch.$1;
      // 移除整段响铃表达（含「的/钟」等连接字），避免标题残留「钟/的」等噪声
      text = text.replaceFirst(ringMatch.$2, '');
    }

    // 3) 资源抽取（先于时间/标题清洗，resource 不参与标题）
    String? resource;
    final resMatch = _resourceRe.firstMatch(text);
    if (resMatch != null) {
      resource = _extractResource(text);
      text = text.replaceFirst(resMatch.group(0)!, '');
    }

    // 4) 时长抽取（占用时段；与倒计时词互斥，先抽时长不影响倒计时）
    int? durationMinutes;
    final durMatch = _durationRe.firstMatch(text);
    if (durMatch != null) {
      durationMinutes = _extractDurationMinutes(text);
      text = text.replaceFirst(durMatch.group(0)!, '');
    }

    // 5) 重复
    if (text.contains(RegExp(r'睡前|睡觉前'))) {
      // 睡前/睡觉前 → 每天，且未给具体时刻时默认 23:00
      repeat = RepeatType.daily;
      bedtime = true;
    }
    if (text.contains(RegExp(
        r'每天|每日|天天|每一天|每晚|每天早上|每个早上|每天早晨|每个早晨'))) {
      repeat = RepeatType.daily;
    } else if (text.contains('工作日')) {
      repeat = RepeatType.weekdays;
    } else {
      final wd = _extractWeekdays(text);
      if (text.contains(RegExp(r'每周|每星期|每个星期'))) {
        repeat = wd.isNotEmpty ? RepeatType.custom : RepeatType.weekly;
        customWeekdays = wd;
      } else if (wd.isNotEmpty) {
        repeat = RepeatType.custom;
        customWeekdays = wd;
      }
    }

    // 6) 时间点
    final period = _matchPeriod(text); // 仅用于判定是否 +12 小时
    // 6a) 冒号时间 X:YY
    final colon = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{1,2})').firstMatch(text);
    if (colon != null) {
      hour = int.parse(colon.group(1)!);
      minute = int.parse(colon.group(2)!);
      hasTime = true;
      text = text.replaceFirst(colon.group(0)!, '');
    } else {
      // 6b) 中文时段 + X点(半)/(X分)
      final timeRe = RegExp(
          r'(半|\d{1,2}|[零一二两三四五六七八九十]+)\s*点\s*(半|(\d{1,2})\s*分?)?');
      final tm = timeRe.firstMatch(text);
      if (tm != null) {
        final hStr = tm.group(1)!;
        var h = hStr == '半' ? 0 : (_parseInt(hStr) ?? 0);
        var min = 0;
        if (tm.group(2) == '半') {
          min = 30;
        } else if (tm.group(3) != null) {
          min = int.parse(tm.group(3)!);
        }
        if (period != null && period && h != 12) {
          h += 12;
        }
        hour = h;
        minute = min;
        hasTime = true;
        text = text.replaceFirst(tm.group(0)!, '');
      }
    }
    // 统一去除时段词（上午/下午/早上/晚上/中午…），覆盖全部变体，避免漏删
    text = text.replaceAll(
        RegExp(
            r'凌晨|清晨|早上|早晨|上午|中午|正午|下午|午后|晚上|夜里|夜晚|傍晚|黄昏|晨'),
        '');

    // 睡前但未给具体时刻 → 默认 23:00
    if (bedtime && !hasTime) {
      hour = 23;
      minute = 0;
      hasTime = true;
    }

    // 7) 计算触发时间
    DateTime? scheduled;
    if (countdownMinutes != null) {
      scheduled = now.add(Duration(minutes: countdownMinutes));
    } else if (countdownSeconds != null) {
      scheduled = now.add(Duration(seconds: countdownSeconds));
    } else if (hasTime) {
      final baseDate = datePart ?? DateTime(now.year, now.month, now.day);
      scheduled = DateTime(
          baseDate.year, baseDate.month, baseDate.day, hour!, minute);
      if (!dateExplicit && scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    } else if (datePart != null) {
      // 有日期无时间：推断为当天 09:00
      scheduled =
          DateTime(datePart.year, datePart.month, datePart.day, 9, 0);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    }

    final title = _extractCorePurpose(text);
    if (title.isEmpty) return null;

    return ParsedTask(
      title: title,
      scheduledTime: scheduled,
      repeat: repeat,
      customWeekdays: customWeekdays,
      countdownSeconds: countdownSeconds,
      resource: resource,
      durationMinutes: durationMinutes,
      ringSeconds: ringSeconds,
    );
  }

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day).add(Duration(days: days));

  /// 抽取资源名（取首个匹配）；返回 null 表示无资源。
  static String? _extractResource(String text) {
    final m = _resourceRe.firstMatch(text);
    return m?.group(1);
  }

  /// 抽取占用时段（分钟）；返回 null 表示未显式表达时长。
  static int? _extractDurationMinutes(String text) {
    final m = _durationRe.firstMatch(text);
    if (m == null) return null;
    final numStr = m.group(1)!;
    final val = _parseInt(numStr) ?? int.tryParse(numStr) ?? 1;
    final unit = m.group(2)!;
    // 小时/时 → 折算分钟；分钟/分 → 原值
    return (unit.contains('小时') || unit == '时') ? val * 60 : val;
  }

  /// 中文/阿拉伯数字转 int（支持 0-99）
  static int? _parseInt(String s) {
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null) return n;
    const d = {
      '零': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (s == '十') return 10;
    if (s.length == 2 && s[0] == '十' && d.containsKey(s[1])) {
      return 10 + d[s[1]]!;
    }
    if (s.length == 2 && d.containsKey(s[0]) && s[1] == '十') {
      return d[s[0]]! * 10;
    }
    if (s.length == 3 &&
        d.containsKey(s[0]) &&
        s[1] == '十' &&
        d.containsKey(s[2])) {
      return d[s[0]]! * 10 + d[s[2]]!;
    }
    if (d.containsKey(s)) return d[s];
    return null;
  }

  static List<int> _extractWeekdays(String text) {
    final map = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    final wds = <int>{};
    final re = RegExp(r'(周|星期|礼拜)\s*([一二三四五六日天]+)');
    for (final m in re.allMatches(text)) {
      final seg = m.group(2)!;
      for (var i = 0; i < seg.length; i++) {
        final ch = seg[i];
        if (map.containsKey(ch)) wds.add(map[ch]!);
      }
    }
    return wds.toList()..sort();
  }

  /// 一次性相对星期日期正则：必须带量词 下/下下/这/上，与「每周X」(重复) 区分。
  static final RegExp _relativeWeekdayRe = RegExp(
    r'(下下|下|这|上)\s*(周|星期|礼拜)\s*([一二三四五六日天]+)');

  /// 解析「下周一 / 这周五 / 上周X / 下下周一」为具体日期（仅取首个工作日字）。
  /// 与重复判定解耦：返回非 null 时调用方应将其视为一次性绝对日期。
  static DateTime? _resolveRelativeWeekday(String text, DateTime now) {
    final m = _relativeWeekdayRe.firstMatch(text);
    if (m == null) return null;
    final quant = m.group(1)!;
    final ch = m.group(3)![0];
    const map = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    final wd = map[ch];
    if (wd == null) return null;
    int diff = (wd - now.weekday) % 7;
    late final DateTime result;
    if (quant == '上') {
      // 上周X：回退到上一周的该星期
      final back = diff == 0 ? 7 : 7 - diff;
      result = now.subtract(Duration(days: back));
    } else if (quant == '这') {
      // 本周X：保持原样（dateExplicit 不自动顺延）
      result = now.add(Duration(days: diff));
    } else {
      // 下 / 下下：严格落在未来；若今天即该星期则 +7 归入下一周
      if (diff == 0) diff = 7;
      final extra = quant == '下下' ? 7 : 0;
      result = now.add(Duration(days: diff + extra));
    }
    return DateTime(result.year, result.month, result.day);
  }

  /// 将数量+单位折算为秒（分钟×60，小时×3600）。
  static int _secondsFromUnit(int val, String unit) {
    if (unit == '秒') return val;
    if (unit == '分钟' || unit == '分') return val * 60;
    return val * 3600; // 小时 / 时 / 个小时
  }

  /// 抽取「响铃时长」（ringSeconds），与倒计时(countdownSeconds) 严格区分。
  ///
  /// 支持三种口语：
  ///  1) X秒(钟)的提醒时间 / X秒提醒时间（数字在「提醒时间」之前；区别于「提醒时间为X秒」倒计时）
  ///  2) 响铃X秒 / 响铃X分钟
  ///  3) 提醒时长X秒
  ///
  /// 返回 (秒数, 命中原文)；未命中返回 null。分钟/小时按换算填入秒数。
  static (int, String)? _parseRingSeconds(String text) {
    // 1) X秒(钟)的提醒时间（数字在「提醒时间」之前）
    final r1 = RegExp(
        r'(\d{1,3}|[零一二两三四五六七八九十]+)\s*(秒|分钟|分|小时|个小时|时)\s*钟?\s*的?\s*提醒时间');
    final m1 = r1.firstMatch(text);
    if (m1 != null) {
      final val = _parseInt(m1.group(1)!) ?? 1;
      return (_secondsFromUnit(val, m1.group(2)!), m1.group(0)!);
    }
    // 2) 响铃X秒 / 响铃X分钟
    final r2 = RegExp(
        r'响铃\s*(\d{1,3}|[零一二两三四五六七八九十]+)\s*(秒|分钟|分|小时|个小时|时)');
    final m2 = r2.firstMatch(text);
    if (m2 != null) {
      final val = _parseInt(m2.group(1)!) ?? 1;
      return (_secondsFromUnit(val, m2.group(2)!), m2.group(0)!);
    }
    // 3) 提醒时长X秒
    final r3 = RegExp(
        r'提醒时长\s*(\d{1,3}|[零一二两三四五六七八九十]+)\s*(秒|分钟|分|小时|个小时|时)');
    final m3 = r3.firstMatch(text);
    if (m3 != null) {
      final val = _parseInt(m3.group(1)!) ?? 1;
      return (_secondsFromUnit(val, m3.group(2)!), m3.group(0)!);
    }
    return null;
  }

  /// 仅判定时段词是否需 +12 小时（下午/晚上/中午下午段 → true）。
  /// 实际时段词（上午/早上/晚上/中午…）的删除统一交给 Step 6 末尾的正则，
  /// 不再依赖返回的「原词」，避免「早上/晚上」等变体漏删的 Bug。
  static bool? _matchPeriod(String text) {
    if (text.contains(RegExp(r'下午|午后|晚上|夜里|夜晚|傍晚|黄昏'))) {
      return true;
    }
    if (text.contains(RegExp(r'中午|正午'))) {
      return true;
    }
    if (text.contains(RegExp(r'凌晨|清晨|早上|早晨|上午|晨'))) {
      return false;
    }
    return null;
  }

  static String _cleanTitle(String text) {
    var t = text;
    // 去掉「(每?)(周|星期|礼拜)+星期字」整体（如 每周一 / 周一三五），避免残留「每/一三五」
    t = t.replaceAll(RegExp(r'每?\s*(周|星期|礼拜)\s*[一二三四五六日天]*'), '');
    t = t.replaceAll(
        RegExp(
            r'今天|今日|今|明天|明日|明|后天|大后天|每天|每日|天天|每一天|每晚|每天早上|每个早上|每天早晨|每个早晨|工作日|每|后'),
        '');
    // 兜底：去除可能残留的时段词
    t = t.replaceAll(
        RegExp(
            r'凌晨|清晨|早上|早晨|上午|中午|正午|下午|午后|晚上|夜里|夜晚|傍晚|黄昏|晨'),
        '');
    t = t.replaceAll(RegExp(r'[，。、！？,.;:：\s]'), '');
    t = t.replaceFirst(RegExp(r'^(我要|我想|记得|提醒我|帮我|请|做|还有|以及|然后|之后|再|顺便|要|该)'), '');
    // 去除残留量词 / 指示代词（如「一个」「这个」「那个」），避免标题含虚词
    t = t.replaceAll(RegExp(r'一个|这个|那个'), '');
    return t.trim();
  }

  /// 提取秒级倒计时：兼容「X秒后」与「提醒时间(为)?X秒/分/时」。
  ///
  /// 返回 (秒数, 命中原文)；未命中返回 null。分钟/时按换算填入秒数
  /// （例如「提醒时间为10分」→ 600 秒）。
  static (int, String)? _parseSeconds(String text) {
    // 1) 「X秒后」
    final r1 = RegExp(
        r'(半|\d{1,3}|[零一二两三四五六七八九十]+)\s*秒\s*后');
    final m1 = r1.firstMatch(text);
    if (m1 != null) {
      final val = _parseInt(m1.group(1)!) ?? 1;
      return (val, m1.group(0)!);
    }
    // 2) 「提醒时间(为)?X秒/分/时」（数字在「提醒时间」之后 → 视为倒计时）
    final r2 = RegExp(
        r'提醒时间\s*为?\s*(\d{1,3}|[零一二两三四五六七八九十]+)\s*(秒|分钟|分|小时|个小时|时)');
    final m2 = r2.firstMatch(text);
    if (m2 != null) {
      final val = _parseInt(m2.group(1)!) ?? 1;
      final unit = m2.group(2)!;
      final int seconds;
      if (unit == '秒') {
        seconds = val;
      } else if (unit == '分钟' || unit == '分') {
        seconds = val * 60;
      } else {
        seconds = val * 3600; // 小时 / 时
      }
      return (seconds, m2.group(0)!);
    }
    return null;
  }

  /// 在 [_cleanTitle] 基础上进一步精炼「核心目的 / 动作片段」：
  /// 剥离残留的提醒·倒计时短语（提醒时间 / 提醒 / 倒计时 / 定提醒 / 设置…）、
  /// 时间表达式（X秒 / X分钟 / X点 / 明天 / 后天…）、重复词（每天 / 每周…），
  /// 以及连接代词/祈使词（我需要 / 你需要 / 请你 / 我 / 你 / 请 / 需要），
  /// 取剩余的动作片段；若精炼后为空，则回退 [_cleanTitle] 的结果。
  static String _extractCorePurpose(String text) {
    final base = _cleanTitle(text);
    if (base.isEmpty) return base;
    var t = base;
    // 提醒 / 倒计时 相关短语
    t = t.replaceAll(
        RegExp(r'提醒时间|提醒|倒计时|定提醒|定个提醒|设置提醒|设定提醒'), '');
    // 通用的「设置」前缀（如「设置提醒时间为10秒」残留的「设置」）
    t = t.replaceAll(RegExp(r'设置'), '');
    // 兜底：残留的时间表达式 / 日期 / 时段 / 重复词（理论上已在 _parseClause 移除）
    t = t.replaceAll(
        RegExp(
            r'今天|今日|今|明天|明日|明|后天|大后天|每天|每日|天天|每一天|每晚|每天早上|每个早上|每天早晨|每个早晨|工作日|每|后'),
        '');
    t = t.replaceAll(
        RegExp(
            r'凌晨|清晨|早上|早晨|上午|中午|正午|下午|午后|晚上|夜里|夜晚|傍晚|黄昏|晨'),
        '');
    // 连接代词 / 祈使词（我需要 / 你需要 / 请你 / 我 / 你 / 请 / 需要）。
    // 这些为口语功能词，标题不应保留；「和」等连词不在此列，避免误删「和朋友出去玩儿」。
    t = t.replaceAll(RegExp(r'我|你|请|需要'), '');
    // 残留的"N(单位)"时间/时长表达（不含"后"的裸时长如"1小时"也应剥离，避免标题含参）
    t = t.replaceAll(
        RegExp(
            r'(\d{1,3}|[零一二两三四五六七八九十]+)\s*(秒|分钟|分|小时|时|天|日)\s*后?'),
        '');
    // 去除残留量词（一个）与尾随虚词（的 / 个）
    t = t.replaceAll(RegExp(r'一个'), '');
    t = t.replaceAll(RegExp(r'[的个]$'), '');
    t = t.replaceAll(RegExp(r'[，。、！？,.;:：\s]'), '');
    t = t.trim();
    if (t.isEmpty) return base;
    return t;
  }
}
