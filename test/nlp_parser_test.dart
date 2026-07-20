import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/nlp_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// NlpParser 单元测试（纯 Dart，无 Flutter 依赖，可快速运行）。
///
/// 用一个固定的 `now` 基准时间，使所有相对/绝对时间断言完全确定。
/// 基准：2026-07-14 06:00（周二），足够早以保证所有"当天时间点"都在未来，
/// 避免触发源码里 "时间早于 now 则顺延一天" 的兜底逻辑，从而断言更稳定。
void main() {
  final DateTime now = DateTime(2026, 7, 14, 6, 0);

  group('NlpParser - 绝对时间', () {
    test('今天下午3点开会 → 今天 15:00, repeat none', () {
      final List<ParsedTask> r = NlpParser.parse('今天下午3点开会', now: now);
      expect(r, hasLength(1), reason: '应解析出恰好 1 个任务');
      final ParsedTask t = r.first;
      expect(t.title, equals('开会'), reason: '标题应去掉时间词');
      expect(t.repeat, equals(RepeatType.none));
      expect(t.scheduledTime, isNotNull, reason: '已给出具体时间');
      expect(t.scheduledTime!.year, now.year);
      expect(t.scheduledTime!.month, now.month);
      expect(t.scheduledTime!.day, now.day);
      expect(t.scheduledTime!.hour, 15);
      expect(t.scheduledTime!.minute, 0);
    });

    test('明天上午9点吃药 → 明天 09:00', () {
      final r = NlpParser.parse('明天上午9点吃药', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('吃药'));
      expect(t.repeat, equals(RepeatType.none));
      final tomorrow = now.add(const Duration(days: 1));
      expect(t.scheduledTime!.year, tomorrow.year);
      expect(t.scheduledTime!.month, tomorrow.month);
      expect(t.scheduledTime!.day, tomorrow.day);
      expect(t.scheduledTime!.hour, 9);
      expect(t.scheduledTime!.minute, 0);
    });

    test('后天上午9点看书 → 后天 09:00', () {
      final r = NlpParser.parse('后天上午9点看书', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('看书'));
      final d2 = now.add(const Duration(days: 2));
      expect(t.scheduledTime!.day, d2.day);
      expect(t.scheduledTime!.hour, 9);
      expect(t.scheduledTime!.minute, 0);
    });

    test('大后天早上8点跑步 → 大后天 08:00', () {
      final r = NlpParser.parse('大后天早上8点跑步', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('跑步'));
      final d3 = now.add(const Duration(days: 3));
      expect(t.scheduledTime!.day, d3.day);
      expect(t.scheduledTime!.hour, 8);
      expect(t.scheduledTime!.minute, 0);
    });

    test('15:30开会 → 今天 15:30（冒号时间）', () {
      final r = NlpParser.parse('15:30开会', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('开会'));
      expect(t.scheduledTime!.year, now.year);
      expect(t.scheduledTime!.month, now.month);
      expect(t.scheduledTime!.day, now.day);
      expect(t.scheduledTime!.hour, 15);
      expect(t.scheduledTime!.minute, 30);
    });

    test('上午9:30吃药 → 今天 09:30', () {
      final r = NlpParser.parse('上午9:30吃药', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('吃药'));
      expect(t.scheduledTime!.hour, 9);
      expect(t.scheduledTime!.minute, 30);
    });
  });

  group('NlpParser - 相对时间（倒计时）', () {
    test('30分钟后吃药 → now+30min, repeat none', () {
      final r = NlpParser.parse('30分钟后吃药', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('吃药'));
      expect(t.repeat, equals(RepeatType.none));
      expect(t.scheduledTime, isNotNull);
      expect(t.scheduledTime!.difference(now).inMinutes, 30,
          reason: '30分钟后应为 now+30 分钟');
    });

    test('2小时后开会 → now+120min', () {
      final r = NlpParser.parse('2小时后开会', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('开会'));
      expect(t.scheduledTime!.difference(now).inMinutes, 120,
          reason: '2小时后应为 now+120 分钟');
    });

    test('半小时后吃药 → now+30min（半小时 = 30 分钟）', () {
      final r = NlpParser.parse('半小时后吃药', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('吃药'));
      expect(t.scheduledTime!.difference(now).inMinutes, 30,
          reason: '"半小时"应等于 30 分钟，而非 1 分钟');
    });
  });

  group('NlpParser - 重复', () {
    test('每天晚上8点跑步 → repeat daily', () {
      final r = NlpParser.parse('每天晚上8点跑步', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('跑步'));
      expect(t.repeat, equals(RepeatType.daily));
      expect(t.scheduledTime!.hour, 20);
      expect(t.scheduledTime!.minute, 0);
    });

    test('工作日早上7点锻炼 → repeat weekdays', () {
      final r = NlpParser.parse('工作日早上7点锻炼', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('锻炼'));
      expect(t.repeat, equals(RepeatType.weekdays));
      expect(t.scheduledTime!.hour, 7);
      expect(t.scheduledTime!.minute, 0);
    });

    test('每周一上午10点开会 → repeat custom, customWeekdays=[1]', () {
      // 「每周X」按设计归类为自定义星期(custom)，功能等价于每周X的重复提醒；
      // reminder_service 对 custom[1] 会按周一精确调度，与 weekly 表现一致。
      final r = NlpParser.parse('每周一上午10点开会', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('开会'),
          reason: '_cleanTitle 应去掉「周一」前缀，仅留任务名');
      expect(t.repeat, equals(RepeatType.custom),
          reason: '「每周X」按设计归类为自定义星期（custom）');
      expect(t.customWeekdays, equals([1]), reason: '应解析出周一(1)');
    });

    test('周一三五下午2点上课 → repeat custom, customWeekdays=[1,3,5]', () {
      final r = NlpParser.parse('周一三五下午2点上课', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, contains('上课'));
      expect(t.repeat, equals(RepeatType.custom));
      expect(t.customWeekdays, equals([1, 3, 5]),
          reason: '应解析出周一/三/五');
      expect(t.scheduledTime!.hour, 14);
      expect(t.scheduledTime!.minute, 0);
    });
  });

  group('NlpParser - 待办 / backlog', () {
    test('买牛奶和鸡蛋 → scheduledTime 为 null（待安排）', () {
      final r = NlpParser.parse('买牛奶和鸡蛋', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.title, equals('买牛奶和鸡蛋'));
      expect(t.scheduledTime, isNull, reason: '未给时间应进入 backlog');
      expect(t.repeat, equals(RepeatType.none));
    });
  });

  group('NlpParser - 多句切分', () {
    test('多个分句 → 多个任务', () {
      final r =
          NlpParser.parse('今天下午3点开会。买牛奶和鸡蛋', now: now);
      expect(r, hasLength(2), reason: '句号分隔应得到 2 个任务');
      expect(r[0].title, equals('开会'));
      expect(r[0].scheduledTime, isNotNull);
      expect(r[1].title, equals('买牛奶和鸡蛋'));
      expect(r[1].scheduledTime, isNull);
    });
  });

  group('NlpParser - 秒级倒计时（T1/T2 增量）', () {
    test('设置提醒时间为10秒，去倒垃圾 → countdownSeconds=10, scheduled≈now+10s, title=去倒垃圾', () {
      final r = NlpParser.parse('设置提醒时间为10秒，去倒垃圾', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.countdownSeconds, 10, reason: '应解析出 10 秒');
      expect(t.title, '去倒垃圾', reason: '核心目的应剥离"提醒/10秒"等参数');
      expect(t.scheduledTime, isNotNull);
      expect(t.scheduledTime!.difference(now).inSeconds, 10,
          reason: 'scheduledTime 应为 now+10s');
    });

    test('提醒时间为10秒去倒垃圾（无逗号）→ 同样解析', () {
      final r = NlpParser.parse('提醒时间为10秒去倒垃圾', now: now);
      expect(r, hasLength(1));
      expect(r.first.countdownSeconds, 10);
      expect(r.first.title, '去倒垃圾');
    });

    test('提醒时间为10分去散步 → countdownSeconds=600（分钟折算秒）', () {
      final r = NlpParser.parse('提醒时间为10分去散步', now: now);
      expect(r, hasLength(1));
      expect(r.first.countdownSeconds, 600);
      expect(r.first.title, '去散步');
    });

    test('X秒后 直接倒计时 → countdownSeconds=秒数', () {
      final r = NlpParser.parse('10秒后倒垃圾', now: now);
      expect(r, hasLength(1));
      expect(r.first.countdownSeconds, 10);
      expect(r.first.title, '倒垃圾');
    });

    test('纯触发词无目的 → 不产生任务（核心目的为空被丢弃）', () {
      final r = NlpParser.parse('提醒时间为10秒', now: now);
      expect(r, isEmpty, reason: '仅有提醒触发、无核心目的时应忽略');
    });
  });

  group('NlpParser - 核心目的提取（_extractCorePurpose，≥5 fixture）', () {
    // _extractCorePurpose 为私有方法，此处通过 parse(...).title 间接验证其行为。
    test('设置提醒时间为10秒去倒垃圾 → 去倒垃圾', () {
      expect(NlpParser.parse('设置提醒时间为10秒去倒垃圾', now: now).first.title,
          '去倒垃圾');
    });
    test('明天上午9点开会 → 开会', () {
      expect(
          NlpParser.parse('明天上午9点开会', now: now).first.title, '开会');
    });
    test('30分钟后吃药 → 吃药（不带"30分钟"）', () {
      expect(NlpParser.parse('30分钟后吃药', now: now).first.title, '吃药');
    });
    test('提醒时间为10分去散步 → 去散步', () {
      expect(
          NlpParser.parse('提醒时间为10分去散步', now: now).first.title, '去散步');
    });
    test('10秒后倒垃圾 → 倒垃圾', () {
      expect(NlpParser.parse('10秒后倒垃圾', now: now).first.title, '倒垃圾');
    });
    test('空回退：仅提醒触发词无目的 → 不产生任务', () {
      expect(NlpParser.parse('提醒时间为10秒', now: now), isEmpty);
    });
  });

  group('NlpParser - 回归：绝对/相对时间仍正确', () {
    test('30分钟后吃药 → scheduledTime≈now+30min', () {
      final r = NlpParser.parse('30分钟后吃药', now: now);
      expect(r.first.scheduledTime!.difference(now).inMinutes, 30);
    });
    test('明天上午9点开会 → 绝对时间解析为明天 09:00', () {
      final r = NlpParser.parse('明天上午9点开会', now: now);
      final tomorrow = now.add(const Duration(days: 1));
      expect(r.first.scheduledTime!.year, tomorrow.year);
      expect(r.first.scheduledTime!.month, tomorrow.month);
      expect(r.first.scheduledTime!.day, tomorrow.day);
      expect(r.first.scheduledTime!.hour, 9);
      expect(r.first.title, '开会');
    });
  });

  group('NlpParser - 资源抽取（T2 增量）', () {
    test('占用会议室A开会1小时 → resource=会议室A, durationMinutes=null', () {
      final r = NlpParser.parse('占用会议室A开会1小时', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.resource, '会议室A', reason: '应抽取资源名');
      expect(t.durationMinutes, isNull,
          reason: '本地不抽裸"1小时"时长，回退默认 60 由 _fallback 处理');
      expect(t.title, '开会', reason: '标题不含资源/时长参数');
    });
  });

  group('NlpParser - 时长抽取（T2 增量）', () {
    test('持续1小时写报告 → durationMinutes=60', () {
      final r = NlpParser.parse('持续1小时写报告', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.durationMinutes, 60, reason: '持续+小时 → 折算分钟');
      expect(t.title, '写报告');
    });
    test('花费90分钟健身 → durationMinutes=90', () {
      final r = NlpParser.parse('花费90分钟健身', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.durationMinutes, 90, reason: '花费+分钟 → 原值');
      expect(t.title, '健身');
    });
  });

  group('NlpParser - 重复语义（T2 增量）', () {
    test('每晚睡前跑步 → repeat=daily, scheduled≈23:00', () {
      final r = NlpParser.parse('每晚睡前跑步', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.repeat, RepeatType.daily);
      expect(t.scheduledTime!.hour, 23, reason: '睡前默认 23:00');
      expect(t.scheduledTime!.minute, 0);
    });
    test('每天早上8点背单词 → repeat=daily, scheduled=08:00', () {
      final r = NlpParser.parse('每天早上8点背单词', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.repeat, RepeatType.daily);
      expect(t.scheduledTime!.hour, 8);
      expect(t.scheduledTime!.minute, 0);
      expect(t.title, '背单词');
    });
    test('工作日开会 → repeat=weekdays', () {
      final r = NlpParser.parse('工作日开会', now: now);
      expect(r, hasLength(1));
      expect(r.first.repeat, RepeatType.weekdays);
      expect(r.first.title, '开会');
    });
    test('每周一开会 → repeat=custom, customWeekdays=[1]', () {
      final r = NlpParser.parse('每周一开会', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.repeat, RepeatType.custom);
      expect(t.customWeekdays, [1]);
      expect(t.title, '开会');
    });
    test('每周一三五健身 → repeat=custom, customWeekdays=[1,3,5]', () {
      final r = NlpParser.parse('每周一三五健身', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.repeat, RepeatType.custom);
      expect(t.customWeekdays, [1, 3, 5]);
      expect(t.title, '健身');
    });
    test('每周健身 → repeat=weekly（无星期 → weekly）', () {
      final r = NlpParser.parse('每周健身', now: now);
      expect(r, hasLength(1));
      final t = r.first;
      expect(t.repeat, RepeatType.weekly, reason: '每周无星期 → weekly');
      expect(t.customWeekdays, isEmpty);
      expect(t.title, '健身');
    });
  });

  group('NlpParser - 标题去参（_extractCorePurpose，T2 增量）', () {
    test('设置提醒时间为10秒，去倒垃圾 → 去倒垃圾', () {
      expect(NlpParser.parse('设置提醒时间为10秒，去倒垃圾', now: now).first.title,
          '去倒垃圾');
    });
    test('占用会议室A开会1小时 → 开会（不含会议室A/1小时）', () {
      expect(NlpParser.parse('占用会议室A开会1小时', now: now).first.title, '开会');
    });
    test('提醒时间为10分去散步 → 去散步', () {
      expect(NlpParser.parse('提醒时间为10分去散步', now: now).first.title, '去散步');
    });
  });

  group('NlpParser - 倒计时回归（T2 增量）', () {
    test('10秒后去倒垃圾 → countdownSeconds=10, title=去倒垃圾', () {
      final r = NlpParser.parse('10秒后去倒垃圾', now: now);
      expect(r, hasLength(1));
      expect(r.first.countdownSeconds, 10);
      // 设计意图：倒计时词"10秒后"被剥离，动作"去倒垃圾"整体保留（与
      // 「设置提醒时间为10秒，去倒垃圾」→"去倒垃圾" 行为一致，动词"去"不剥离）。
      expect(r.first.title, '去倒垃圾');
    });
  });

  group('NlpParser - 缺陷修复：标题/响铃/重复（用户截图回归）', () {
    // 复现用户语音输入（两句，句号分隔）
    const raw =
        '我下周一，下午三点，需要和朋友出去玩儿，你需要设置一个十秒钟的提醒时间。'
        '我明天上午十点，需要写作业，请你设置一个二十秒的提醒时间。';

    test('两句分别解析为 2 个一次性任务（repeat=none）', () {
      final r = NlpParser.parse(raw, now: now);
      expect(r, hasLength(2), reason: '句号分隔应得到 2 个任务');
      expect(r[0].repeat, RepeatType.none,
          reason: '「下周一」应视为一次性，非每周重复');
      expect(r[1].repeat, RepeatType.none, reason: '「明天」为一次性');
      expect(r[0].customWeekdays, isEmpty);
      expect(r[1].customWeekdays, isEmpty);
    });

    test('标题干净：和朋友出去玩儿 / 写作业（无乱码残留）', () {
      final r = NlpParser.parse(raw, now: now);
      expect(r[0].title, '和朋友出去玩儿',
          reason: '应剥离「我/下周一/下午三点/你需要设置一个十秒钟的提醒时间」');
      expect(r[1].title, '写作业',
          reason: '应剥离「我/明天/上午十点/请你设置一个二十秒的提醒时间」');
    });

    test('响铃时长生效：10 秒 / 20 秒（ringSeconds 非 null）', () {
      final r = NlpParser.parse(raw, now: now);
      expect(r[0].ringSeconds, 10, reason: '「十秒钟的提醒时间」→ 响铃 10 秒');
      expect(r[1].ringSeconds, 20, reason: '「二十秒的提醒时间」→ 响铃 20 秒');
    });

    test('时间安排：下周一 15:00 / 明天 10:00', () {
      final r = NlpParser.parse(raw, now: now);
      // now = 2026-07-14(周二) → 下周一 = 2026-07-20
      expect(r[0].scheduledTime!.year, 2026);
      expect(r[0].scheduledTime!.month, 7);
      expect(r[0].scheduledTime!.day, 20, reason: '下周一应解析为具体日期');
      expect(r[0].scheduledTime!.hour, 15);
      expect(r[0].scheduledTime!.minute, 0);
      // 明天 = 2026-07-15
      expect(r[1].scheduledTime!.day, 15, reason: '明天应解析为具体日期');
      expect(r[1].scheduledTime!.hour, 10);
      expect(r[1].scheduledTime!.minute, 0);
    });
  });

  group('NlpParser - 响铃时长识别（ringSeconds）', () {
    test('X秒(钟)的提醒时间 → ringSeconds，标题不含参', () {
      final r = NlpParser.parse('设置一个十秒钟的提醒时间去倒垃圾', now: now);
      expect(r, hasLength(1));
      expect(r.first.ringSeconds, 10, reason: '响铃 10 秒');
      expect(r.first.title, '去倒垃圾');
      expect(r.first.countdownSeconds, isNull,
          reason: '「X秒的提醒时间」属响铃而非倒计时');
    });

    test('响铃X秒 → ringSeconds', () {
      final r = NlpParser.parse('响铃20秒去锻炼', now: now);
      expect(r, hasLength(1));
      expect(r.first.ringSeconds, 20);
      expect(r.first.title, '去锻炼');
    });

    test('提醒时长X分钟 → 折算为秒', () {
      final r = NlpParser.parse('提醒时长2分钟开会', now: now);
      expect(r, hasLength(1));
      expect(r.first.ringSeconds, 120, reason: '2 分钟 = 120 秒');
    });

    test('与倒计时区分：「提醒时间为10秒」仍判 countdownSeconds 而非 ring', () {
      final r = NlpParser.parse('提醒时间为10秒去倒垃圾', now: now);
      expect(r.first.countdownSeconds, 10);
      expect(r.first.ringSeconds, isNull,
          reason: '「提醒时间为X秒」(数字在后) 语义为倒计时触发');
    });
  });

  group('NlpParser - 相对星期日期为一次性（非重复）', () {
    test('下周一 → repeat none 且解析到下周一日期', () {
      final r = NlpParser.parse('下周一上午9点开会', now: now);
      expect(r, hasLength(1));
      expect(r.first.repeat, RepeatType.none,
          reason: '「下周一」是一次性日期，不应误判为每周重复');
      expect(r.first.customWeekdays, isEmpty);
      expect(r.first.scheduledTime!.day, 20, reason: '2026-07-20 为下周一');
      expect(r.first.scheduledTime!.hour, 9);
      expect(r.first.title, '开会');
    });

    test('这周五 → repeat none', () {
      final r = NlpParser.parse('这周五下午3点健身', now: now);
      expect(r.first.repeat, RepeatType.none);
      expect(r.first.title, '健身');
    });

    test('裸「周一」(无 下/这/上 量词) 仍判重复', () {
      final r = NlpParser.parse('周一上午9点开会', now: now);
      expect(r.first.repeat, RepeatType.custom,
          reason: '裸周X 视为每周重复，与「下周一」一次性区分');
      expect(r.first.customWeekdays, [1]);
    });
  });
}
