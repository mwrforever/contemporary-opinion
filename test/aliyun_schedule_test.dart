import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/prompts/prompt_loader.dart';
import 'package:daily_planner/services/aliyun_schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// AliyunScheduleService.parseJson 纯函数单测（不触网）。
void main() {
  group('AliyunScheduleService.parseJson', () {
    test('解析标准 tasks 数组', () {
      const json = '''
      {"tasks":[
        {"title":"开会","datetime":"2026-07-14 15:00","duration_minutes":90,"resource":"会议室A","repeat":"none","weekdays":[],"note":null},
        {"title":"买菜","datetime":null,"resource":null,"repeat":"none","weekdays":[],"note":"晚饭后"}
      ]}''';
      final list = AliyunScheduleService.parseJson(json);
      expect(list, hasLength(2));
      expect(list[0].title, '开会');
      expect(list[0].scheduledTime, DateTime(2026, 7, 14, 15, 0));
      expect(list[0].durationMinutes, 90);
      expect(list[0].resource, '会议室A');
      expect(list[1].scheduledTime, isNull);
      expect(list[1].note, '晚饭后');
    });

    test('兼容裸数组与 data 键', () {
      final bare = AliyunScheduleService.parseJson(
          '[{"title":"跑步","datetime":"2026-07-14 07:00"}]');
      expect(bare, hasLength(1));
      final data = AliyunScheduleService.parseJson(
          '{"data":[{"title":"读书","datetime":null}]}');
      expect(data, hasLength(1));
    });

    test('custom 重复解析出星期', () {
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"上课","datetime":"2026-07-14 14:00","repeat":"custom","weekdays":[1,3,5]}]}');
      expect(list.first.repeat, RepeatType.custom);
      expect(list.first.customWeekdays, [1, 3, 5]);
    });

    test('非法/空 JSON → 返回空列表（不抛异常）', () {
      expect(AliyunScheduleService.parseJson('not json'), isEmpty);
      expect(AliyunScheduleService.parseJson(''), isEmpty);
      expect(AliyunScheduleService.parseJson('{"tasks":[]}'), isEmpty);
    });

    test('缺少 title 的条目被跳过', () {
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"datetime":"2026-07-14 10:00"},{"title":"有效","datetime":"2026-07-14 11:00"}]}');
      expect(list, hasLength(1));
      expect(list.first.title, '有效');
    });

    test('toTask 正确映射字段', () {
      final st = ScheduledTask(
        title: '开会',
        scheduledTime: DateTime(2026, 7, 14, 15, 0),
        durationMinutes: 90,
        resource: '会议室A',
      );
      final task = st.toTask(
        id: 'x1',
        notificationId: 5,
        createdAt: DateTime(2026, 7, 14, 8, 0),
      );
      expect(task.id, 'x1');
      expect(task.title, '开会');
      expect(task.scheduledTime, DateTime(2026, 7, 14, 15, 0));
      expect(task.durationMinutes, 90);
      expect(task.resource, '会议室A');
      expect(task.source, TaskSource.voice);
      expect(task.effective, isTrue);
    });
  });

  group('AliyunScheduleService.parseJson - 倒计时秒（T3 增量）', () {
    final now = DateTime(2026, 7, 14, 6, 0);

    test('remind_in_seconds=10 → countdownSeconds=10, scheduled=now+10s, title 正确', () {
      const json = '{"tasks":[{"title":"去倒垃圾","remind_in_seconds":10}]}';
      final list = AliyunScheduleService.parseJson(json, now: now);
      expect(list, hasLength(1));
      expect(list.first.title, '去倒垃圾');
      expect(list.first.countdownSeconds, 10);
      expect(list.first.scheduledTime!.difference(now).inSeconds, 10);
    });

    test('remind_in_minutes=10 → countdownSeconds=600', () {
      const json = '{"tasks":[{"title":"休息","remind_in_minutes":10}]}';
      final list = AliyunScheduleService.parseJson(json, now: now);
      expect(list.first.countdownSeconds, 600);
      expect(list.first.scheduledTime!.difference(now).inSeconds, 600);
    });

    test('remind_in_seconds 优先于 remind_in_minutes', () {
      const json =
          '{"tasks":[{"title":"x","remind_in_seconds":5,"remind_in_minutes":100}]}';
      final list = AliyunScheduleService.parseJson(json, now: now);
      expect(list.first.countdownSeconds, 5);
    });

    test('无倒计时且有 datetime → countdownSeconds 为 null', () {
      const json = '{"tasks":[{"title":"开会","datetime":"2026-07-14 15:00"}]}';
      final list = AliyunScheduleService.parseJson(json, now: now);
      expect(list.first.countdownSeconds, isNull);
      expect(list.first.scheduledTime, DateTime(2026, 7, 14, 15, 0));
    });
  });

  group('AliyunScheduleService.parseJson - T1 参数 schema 落地', () {
    final now = DateTime(2026, 7, 14, 6, 0);

    test('ring_seconds=10 → ringSeconds=10', () {
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"开会","ring_seconds":10}]}');
      expect(list.first.ringSeconds, 10);
    });

    test('ring_seconds=null/0 → ringSeconds=null（走全局默认）', () {
      final nullList = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"a","ring_seconds":null}]}');
      expect(nullList.first.ringSeconds, isNull);
      final zeroList = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"b","ring_seconds":0}]}');
      expect(zeroList.first.ringSeconds, isNull);
    });

    test('duration_minutes=90 → 90；缺失 → 0（默认只做提醒）', () {
      final withVal = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"开会","duration_minutes":90}]}');
      expect(withVal.first.durationMinutes, 90);
      final missing = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"开会"}]}');
      expect(missing.first.durationMinutes, 0);
    });

    test('resource 透传', () {
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"开会","resource":"会议室A"}]}');
      expect(list.first.resource, '会议室A');
    });

    test('repeat + weekdays 映射到 RepeatType 与 customWeekdays', () {
      final daily = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"a","repeat":"daily"}]}');
      expect(daily.first.repeat, RepeatType.daily);
      final wd = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"b","repeat":"weekdays"}]}');
      expect(wd.first.repeat, RepeatType.weekdays);
      final weekly = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"c","repeat":"weekly"}]}');
      expect(weekly.first.repeat, RepeatType.weekly);
      final custom = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"d","repeat":"custom","weekdays":[1,3,5]}]}');
      expect(custom.first.repeat, RepeatType.custom);
      expect(custom.first.customWeekdays, [1, 3, 5]);
    });

    test('remind_in_seconds=10 → countdownSeconds=10 + scheduled=now+10s', () {
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"倒垃圾","remind_in_seconds":10}]}', now: now);
      expect(list.first.countdownSeconds, 10);
      expect(list.first.scheduledTime!.difference(now).inSeconds, 10);
    });

    test('remind_in_minutes=10 → countdownSeconds=600 + scheduled=now+600s', () {
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"休息","remind_in_minutes":10}]}', now: now);
      expect(list.first.countdownSeconds, 600);
      expect(list.first.scheduledTime!.difference(now).inSeconds, 600);
    });

    test('含参 title 原样透传（去参属 prompt 职责，parseJson 不负责）', () {
      // 云端 schema 中 title 可能携带口语参数；parseJson 仅按原样读取字段。
      const title = '设置提醒时间为10秒去健身房练腿';
      final list = AliyunScheduleService.parseJson(
          '{"tasks":[{"title":"$title"}]}');
      expect(list.first.title, title);
    });
  });

  group('AliyunScheduleService.schedule - prompt 缺失落本地回退 (T1 增量)', () {
    test('PromptLoader 未加载 → _callModel 抛 StateError → 回退 NlpParser', () async {
      // 全新 isolate 下 PromptLoader 缓存为空，byId('tasks_voice_scheduled') 返回
      // null，_callModel 因此抛 StateError，被 schedule 的 catch 捕获后落 _fallback。
      expect(PromptLoader.byId(PromptLoader.tasksScheduledId), isNull,
          reason: '前置：本 isolate 未加载提示词，确保走 null-prompt 分支');
      // 即便 prompt 存在，throwing client 也会触发 catch；双重保险保证回退。
      final client = _ThrowingClient();
      final svc = AliyunScheduleService(apiKey: 'x', client: client);
      final r = await svc.schedule('提醒时间为10秒去倒垃圾');
      expect(r, hasLength(1));
      expect(r.first.title, '去倒垃圾');
      expect(r.first.countdownSeconds, 10,
          reason: '回退路径应经 _fallback 透传秒级倒计时');
    });
  });

  group('AliyunScheduleService.schedule - 云端失败回退透传 countdownSeconds', () {
    test('callModel 抛错 → 回退 NlpParser 仍透传秒级 countdownSeconds', () async {
      final client = _ThrowingClient();
      final svc = AliyunScheduleService(apiKey: 'x', client: client);
      final r = await svc.schedule('提醒时间为10秒去倒垃圾');
      expect(r, hasLength(1));
      expect(r.first.title, '去倒垃圾');
      expect(r.first.countdownSeconds, 10,
          reason: '回退路径应经 _fallback 透传秒级倒计时');
    });
  });

  group('AliyunScheduleService.schedule - 回退透传 ringSeconds (缺陷修复)', () {
    test('callModel 抛错 → 回退 NlpParser 透传响铃时长 ringSeconds', () async {
      final client = _ThrowingClient();
      final svc = AliyunScheduleService(apiKey: 'x', client: client);
      final r = await svc.schedule('设置一个十秒钟的提醒时间去倒垃圾');
      expect(r, hasLength(1));
      expect(r.first.ringSeconds, 10,
          reason: '回退路径应经 _fallback 映射本地解析出的 ringSeconds');
      expect(r.first.title, '去倒垃圾');
    });

    test('「下周一」回退解析为一次性（repeat=none）', () async {
      final client = _ThrowingClient();
      final svc = AliyunScheduleService(apiKey: 'x', client: client);
      final r = await svc.schedule('下周一上午9点开会');
      expect(r, hasLength(1));
      expect(r.first.repeat, RepeatType.none,
          reason: '回退路径不应把「下周一」误判为每周重复');
    });
  });

  group('parseJson - 多任务与倒计时重复（冒烟缺陷回归）', () {
    test('一次口语多个任务全部解析（含思考链包裹）', () {
      final json = '''
<think>用户安排了开会和打电话两件事</think>
{"tasks":[
  {"title":"晨会同步项目进度","datetime":"2026-08-07 09:00","duration_minutes":120,"resource":"会议室A"},
  {"title":"给客户回电话","datetime":"2026-08-07 14:00","duration_minutes":15}
]}
''';
      final list = AliyunScheduleService.parseJson(json);
      expect(list, hasLength(2));
      expect(list.map((t) => t.title), ['晨会同步项目进度', '给客户回电话']);
    });

    test('裸数组多任务解析', () {
      final json = '''
[{"title":"第一件事","datetime":"2026-08-07 09:00"},
 {"title":"第二件事","datetime":"2026-08-07 10:00"}]
''';
      final list = AliyunScheduleService.parseJson(json);
      expect(list, hasLength(2));
    });

    test('倒计时重复：interval_seconds + max_repeats → DELAYED 字段', () {
      final list = AliyunScheduleService.parseJson(
        '{"tasks":[{"title":"提醒喝水","remind_in_seconds":1800,"interval_seconds":1800,"max_repeats":5}]}',
        now: DateTime(2026, 8, 5, 8, 0),
      );
      final task = list.single;
      expect(task.maxRepeats, 5);
      expect(task.intervalSeconds, 1800);
      expect(task.scheduledTime, DateTime(2026, 8, 5, 8, 30));
    });

    test('倒计时重复：缺省 interval 回退首次倒计时秒数', () {
      final list = AliyunScheduleService.parseJson(
        '{"tasks":[{"title":"吃药","remind_in_seconds":600,"max_repeats":3}]}',
        now: DateTime(2026, 8, 5, 8, 0),
      );
      final task = list.single;
      expect(task.maxRepeats, 3);
      expect(task.intervalSeconds, 600);
    });
  });
}

/// 模拟网络异常的 http 客户端：任何请求都抛错，触发 schedule 的回退分支。
class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw Exception('simulated network error');
}
