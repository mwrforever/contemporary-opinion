/// 提醒方式：静音 / 语音播报（互斥，单选）。
///
/// 震动（[ReminderSettings.vibrate]）为独立开关，可与任意一方同时生效；
/// 静音与语音播报不能同时存在。
enum ReminderMode { mute, voice }

/// 用户提醒设置（铃铛浮层持久化模型，对应 user_settings 表）。
class ReminderSettings {
  const ReminderSettings({
    this.mode = ReminderMode.voice,
    this.vibrate = true,
    this.volume = 60,
  });

  /// 提醒方式：语音播报或静音
  final ReminderMode mode;

  /// 是否震动（可叠加）
  final bool vibrate;

  /// 语音播报音量（0-100）
  final int volume;

  ReminderSettings copyWith({
    ReminderMode? mode,
    bool? vibrate,
    int? volume,
  }) =>
      ReminderSettings(
        mode: mode ?? this.mode,
        vibrate: vibrate ?? this.vibrate,
        volume: volume ?? this.volume,
      );

  Map<String, dynamic> toRow(int userId) => {
        'user_id': userId,
        'reminder_mode': mode.name,
        'vibrate': vibrate ? 1 : 0,
        'reminder_volume': volume,
      };

  factory ReminderSettings.fromRow(Map<String, dynamic> row) => ReminderSettings(
        mode: row['reminder_mode'] == 'mute'
            ? ReminderMode.mute
            : ReminderMode.voice,
        vibrate: (row['vibrate'] as int? ?? 1) == 1,
        volume: row['reminder_volume'] as int? ?? 60,
      );
}
