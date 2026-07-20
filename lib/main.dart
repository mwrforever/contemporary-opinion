import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'config/aliyun_config.dart';
import 'models/task.dart';
import 'prompts/prompt_loader.dart';
import 'screens/splash_screen.dart';
import 'services/aliyun_asr_service.dart';
import 'services/aliyun_schedule_service.dart';
import 'services/notebook_store.dart';
import 'services/notebook_voice_service.dart';
import 'services/reminder_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';
import 'services/task_store.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(TaskAdapter());

  final store = TaskStore();
  await store.init();

  final notebookStore = NotebookStore();
  await notebookStore.init();

  final settings = SettingsService();
  await settings.init();

  final reminder = ReminderService(settings: settings);
  await reminder.init(store);
  await reminder.ensurePermissions();
  await reminder.scheduleAll();
  await store.markMissedIfNeeded();

  final speech = SpeechService();

  // 云端服务：排期(qwen3.7-max-2026-05-17) 与 语音识别(qwen3-asr-flash) 共用同一
  // DashScope Key；记事本语音解析复用同一排期模型。未配置时自动退回设备端识别
  // + 本地 NLP 解析（任务）/ 提示解析失败（记事本）。
  final asr = AliyunAsrService(
    apiKey: AliyunConfig.dashscopeApiKey,
    fallback: speech,
  );
  final schedule = AliyunScheduleService(apiKey: AliyunConfig.dashscopeApiKey);
  final notebookVoice = NotebookVoiceService(schedule: schedule);

  // 加载提示词 YAML（打包只读资源，随包分发、默认批准）。
  await PromptLoader.loadAll();

  runApp(MyApp(
    store: store,
    notebookStore: notebookStore,
    reminder: reminder,
    asr: asr,
    schedule: schedule,
    notebookVoice: notebookVoice,
    settings: settings,
  ));
}

class MyApp extends StatelessWidget {
  final TaskStore store;
  final NotebookStore notebookStore;
  final ReminderService reminder;
  final AliyunAsrService asr;
  final AliyunScheduleService schedule;
  final NotebookVoiceService notebookVoice;
  final SettingsService settings;

  const MyApp({
    super.key,
    required this.store,
    required this.notebookStore,
    required this.reminder,
    required this.asr,
    required this.schedule,
    required this.notebookVoice,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: notebookStore),
      ],
      child: MaterialApp(
        title: '时说',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: SplashScreen(
          reminder: reminder,
          asr: asr,
          schedule: schedule,
          notebookVoice: notebookVoice,
          settings: settings,
        ),
      ),
    );
  }
}
