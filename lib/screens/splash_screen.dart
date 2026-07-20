import 'package:flutter/material.dart';

import '../app/tab_shell.dart';
import '../services/aliyun_asr_service.dart';
import '../services/aliyun_schedule_service.dart';
import '../services/notebook_voice_service.dart';
import '../services/reminder_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 启动页（品牌「时说」）：展示品牌标识与主标语，点击进入主界面。
class SplashScreen extends StatefulWidget {
  final ReminderService reminder;
  final AliyunAsrService asr;
  final AliyunScheduleService schedule;
  final NotebookVoiceService notebookVoice;
  final SettingsService settings;

  const SplashScreen({
    super.key,
    required this.reminder,
    required this.asr,
    required this.schedule,
    required this.notebookVoice,
    required this.settings,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _BrandMark(),
              const SizedBox(height: 28),
              Text(
                '时说',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '把脑子里的安排，顺成一天的秩序。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '说出来就好——会听、会排，还会帮你避开每一次撞车。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => TabShell(
                        reminder: widget.reminder,
                        asr: widget.asr,
                        schedule: widget.schedule,
                        notebookVoice: widget.notebookVoice,
                        settings: widget.settings,
                      ),
                    ),
                  ),
                  child: const Text('开始规划'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '你的时间，不该撞车。',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// 品牌标识：柔和圆底 + 声波图形，呼应「语音规划」的差异化。
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.graphic_eq_rounded, size: 44, color: AppTheme.accent),
    );
  }
}
