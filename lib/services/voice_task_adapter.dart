import '../models/task.dart';
import 'aliyun_schedule_service.dart';
import 'nlp_parser.dart';

/// 语音解析结果 → Task 适配。
///
/// - [taskFromScheduled]：云端排期结果；补「倒计时折算为绝对时间」与 note 字段
///   （`ScheduledTask.toTask` 不处理 countdownSeconds → scheduledTime）。
/// - [taskFromParsed]：本地 NLP 兜底结果（NlpParser 已折算倒计时，此处直接映射）。
///
/// 冲突状态由调用方经 ConflictDetector 决定，本层不触碰。
Task taskFromScheduled(
  ScheduledTask scheduled, {
  required String id,
  required int notificationId,
  required DateTime now,
}) {
  final task = scheduled.toTask(
    id: id,
    notificationId: notificationId,
    createdAt: now,
  );
  // 倒计时任务（无绝对时间）折算为「现在 + 秒数」
  final seconds = scheduled.countdownSeconds;
  if (task.scheduledTime == null && seconds != null && seconds > 0) {
    task.scheduledTime = now.add(Duration(seconds: seconds));
  }
  task.note = scheduled.note;
  return task;
}

/// 本地 NLP 解析结果 → Task（NlpParser 已在解析期折算倒计时）。
Task taskFromParsed(
  ParsedTask parsed, {
  required String id,
  required int notificationId,
  required DateTime now,
}) =>
    Task(
      id: id,
      title: parsed.title,
      scheduledTime: parsed.scheduledTime,
      countdownMinutes: parsed.countdownMinutes,
      countdownSeconds: parsed.countdownSeconds,
      repeat: parsed.repeat,
      customWeekdays: parsed.customWeekdays,
      resource: parsed.resource,
      durationMinutes: parsed.durationMinutes ?? 0,
      ringSeconds: parsed.ringSeconds,
      source: TaskSource.voice,
      createdAt: now,
      notificationId: notificationId,
    );
