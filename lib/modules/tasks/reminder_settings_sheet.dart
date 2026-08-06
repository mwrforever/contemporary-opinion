import 'package:flutter/material.dart';

import '../../data/daos/settings_dao.dart';
import '../../data/models/reminder_settings.dart';

/// 铃铛提醒方式设置浮层（V2）。
///
/// - 静音 / 语音播报互斥（单选），震动为独立开关可叠加；
/// - 语音播报时提供音量滑杆（0-100）；
/// - 「完成」持久化到 user_settings 表。
class ReminderSettingsSheet extends StatefulWidget {
  const ReminderSettingsSheet({
    super.key,
    required this.userId,
    required this.settings,
    this.dao,
  });

  final int userId;
  final ReminderSettings settings;
  final SettingsDao? dao;

  @override
  State<ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<ReminderSettingsSheet> {
  late ReminderSettings _settings = widget.settings;

  Future<void> _save() async {
    await (widget.dao ?? SettingsDao()).save(widget.userId, _settings);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: 26 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '提醒方式',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          _modeOption(
            icon: Icons.volume_up_outlined,
            label: '语音播报',
            selected: _settings.mode == ReminderMode.voice,
            onTap: () => setState(
              () => _settings =
                  _settings.copyWith(mode: ReminderMode.voice),
            ),
          ),
          _modeOption(
            icon: Icons.notifications_off_outlined,
            label: '静音',
            selected: _settings.mode == ReminderMode.mute,
            onTap: () => setState(
              () => _settings = _settings.copyWith(mode: ReminderMode.mute),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '静音与语音播报互斥，只能选其一',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.vibration, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                const Text(
                  '震动',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '可与上方任一同时生效',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: _settings.vibrate,
                  onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(vibrate: v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '提醒音量',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${_settings.volume}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _settings.volume.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            label: '${_settings.volume}%',
            onChanged: _settings.mode == ReminderMode.mute
                ? null
                : (v) => setState(
                    () => _settings =
                        _settings.copyWith(volume: v.round()),
                  ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(onPressed: _save, child: const Text('完成')),
          ),
        ],
      ),
    );
  }

  Widget _modeOption({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surface,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const Spacer(),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
