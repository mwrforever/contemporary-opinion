// 语音解析结果 → Task 适配器测试：绝对时间/倒计时折算/字段映射
import 'package:daily_planner/models/task.dart';
import 'package:daily_planner/services/aliyun_schedule_service.dart';
import 'package:daily_planner/services/nlp_parser.dart';
import 'package:daily_planner/services/voice_task_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 5, 12, 0);

  group('taskFromScheduled', () {
    test('绝对时间与 note 映射、来源为 voice', () {
      final task = taskFromScheduled(
        ScheduledTask(
          title: '开会',
          scheduledTime: DateTime(2026, 8, 6, 10),
          resource: '会议室A',
          durationMinutes: 60,
          ringSeconds: 30,
          repeat: RepeatType.daily,
          note: '记得带投影仪',
        ),
        id: 'id-1',
        notificationId: 7,
        now: now,
      );
      expect(task.scheduledTime, DateTime(2026, 8, 6, 10));
      expect(task.resource, '会议室A');
      expect(task.durationMinutes, 60);
      expect(task.ringSeconds, 30);
      expect(task.repeat, RepeatType.daily);
      expect(task.note, '记得带投影仪');
      expect(task.source, TaskSource.voice);
      expect(task.createdAt, now);
      expect(task.notificationId, 7);
    });

    test('倒计时任务折算为绝对时间', () {
      final task = taskFromScheduled(
        const ScheduledTask(title: '吃药', countdownSeconds: 600),
        id: 'id-2',
        notificationId: 8,
        now: now,
      );
      expect(task.scheduledTime, now.add(const Duration(seconds: 600)));
      expect(task.countdownSeconds, 600);
    });

    test('无时间且无倒计时 → scheduledTime 为 null（进入待安排流程）', () {
      final task = taskFromScheduled(
        const ScheduledTask(title: '随便记一下'),
        id: 'id-3',
        notificationId: 9,
        now: now,
      );
      expect(task.scheduledTime, isNull);
    });
  });

  group('taskFromParsed', () {
    test('字段完整映射且保留倒计时原始值', () {
      final task = taskFromParsed(
        ParsedTask(
          title: '取快递',
          scheduledTime: now.add(const Duration(minutes: 30)),
          countdownMinutes: 30,
          repeat: RepeatType.none,
          resource: '菜鸟驿站',
          durationMinutes: 10,
          ringSeconds: 15,
        ),
        id: 'id-4',
        notificationId: 10,
        now: now,
      );
      expect(task.title, '取快递');
      expect(task.scheduledTime, now.add(const Duration(minutes: 30)));
      expect(task.countdownMinutes, 30);
      expect(task.resource, '菜鸟驿站');
      expect(task.durationMinutes, 10);
      expect(task.ringSeconds, 15);
      expect(task.source, TaskSource.voice);
    });
  });

  group('taskFromScheduled - 倒计时重复（DELAYED）', () {
    test('interval_seconds + max_repeats → 延时重复任务，首次触发即 next_fire_time', () {
      final scheduled = ScheduledTask(
        title: '提醒喝水',
        scheduledTime: now.add(const Duration(minutes: 30)),
        countdownSeconds: 1800,
        intervalSeconds: 1800,
        maxRepeats: 5,
      );
      final task = taskFromScheduled(
        scheduled,
        id: 'id-delay',
        notificationId: 11,
        now: now,
      );
      expect(task.isDelayed, isTrue);
      expect(task.intervalSeconds, 1800);
      expect(task.maxRepeats, 5);
      expect(task.repeatCount, 0);
      expect(task.nextFireTime, task.scheduledTime);
    });

    test('缺省 interval 回退到首次倒计时秒数', () {
      final scheduled = ScheduledTask(
        title: '吃药',
        scheduledTime: now.add(const Duration(minutes: 10)),
        countdownSeconds: 600,
        maxRepeats: 3,
      );
      final task = taskFromScheduled(
        scheduled,
        id: 'id-delay2',
        notificationId: 12,
        now: now,
      );
      expect(task.isDelayed, isTrue);
      expect(task.intervalSeconds, 600);
    });
  });
}
