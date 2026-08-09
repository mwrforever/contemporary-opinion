/// 时间护栏：统一的「任务开始时间是否早于当前时间」判定。
///
/// 手动创建（[AddTaskScreen]）与语音录入（[VoiceInputScreen]）共用同一判据：
/// 非倒计时模式下，开始时间早于当前时间即视为「参数异常」需拦截/标记，
/// 避免写入一个永远不会正确触发的过去时刻任务。
library;

/// 判断 [scheduled] 是否早于当前时间（非倒计时模式下需拦截）。
///
/// - [countdownMode] 为 true 时（倒计时创建：scheduled = now + 分钟），永远不早于
///   now，直接返回 false，无需校验。
/// - [scheduled] 为 null（倒计时模式分钟数非法）时返回 false。
bool isScheduledTimeInPast(DateTime? scheduled, bool countdownMode) =>
    !countdownMode && scheduled != null && scheduled.isBefore(DateTime.now());
