// 我的页测试：资料渲染/编辑、导入导出确认、提醒设置入口与摘要、深色三档、音色切换、退出登录
import 'package:daily_planner/data/daos/app_settings_dao.dart';
import 'package:daily_planner/data/models/user.dart';
import 'package:daily_planner/screens/profile_page.dart';
import 'package:daily_planner/services/backup_service.dart';
import 'package:daily_planner/services/permission_status_service.dart';
import 'package:daily_planner/services/reminder_service.dart';
import 'package:daily_planner/services/tts_service.dart';
import 'package:daily_planner/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_service.dart';
import 'support/fakes.dart';

/// 备份服务替身：记录调用并返回固定结果，避免触碰平台插件。
class FakeBackup extends BackupService {
  int exportCalls = 0;
  String? importedJson;

  /// 注入校验异常以验证「确认前拦截」分支
  FormatException? validateError;

  @override
  Future<String> exportJson(int userId) async {
    exportCalls++;
    return '{}';
  }

  @override
  Future<void> shareExport(String fileName, String json) async {}

  @override
  Future<String?> pickImportFile() async => '{"version":1,"tasks":[]}';

  @override
  int validateImport(String json) {
    final error = validateError;
    if (error != null) throw error;
    return 3;
  }

  @override
  Future<int> importJson(int userId, String json) async {
    importedJson = json;
    return 3;
  }
}

/// 设备级设置替身：内存键值，记录主题/音色持久化。
class FakeAppSettings extends AppSettingsDao {
  final Map<String, String> store = {};

  @override
  Future<String?> get(String key) async => store[key];

  @override
  Future<void> set(String key, String value) async {
    store[key] = value;
  }
}

/// 权限状态替身：固定返回可配置的聚合状态。
class FakePermissionStatus extends PermissionStatusService {
  ReminderPermissionStatus status =
      const ReminderPermissionStatus(notification: true);

  @override
  Future<ReminderPermissionStatus> reminderStatus() async => status;
}

/// 带音色能力的 TTS 替身：记录应用音色并返回固定语音列表。
class VoiceFakeTts extends FakeTts {
  String? appliedVoiceId;

  @override
  Future<List<TtsVoice>> availableVoices() async => const [
        TtsVoice(name: '普通话 · 女声', locale: 'zh-CN', id: 'v-female'),
        TtsVoice(name: '普通话 · 男声', locale: 'zh-CN', id: 'v-male'),
      ];

  @override
  Future<void> setVoice(String? voiceId) async {
    appliedVoiceId = voiceId;
  }
}

void main() {
  late FakeAuthService auth;
  late FakeBackup backup;
  late FakeAppSettings settings;
  late FakePermissionStatus perm;
  late VoiceFakeTts tts;
  late ThemeController theme;

  User buildUser() => User(
        id: 1,
        username: 'xiaoxu',
        passwordHash: 'fake',
        nickname: '小许',
        defaultRingSeconds: 30,
        createdAt: DateTime(2026, 8, 5),
      );

  setUp(() {
    auth = FakeAuthService(user: buildUser());
    backup = FakeBackup();
    settings = FakeAppSettings();
    perm = FakePermissionStatus();
    tts = VoiceFakeTts();
    theme = ThemeController(dao: settings);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 放大视口，确保平铺列表中的底部按钮（退出登录等）完整构建
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          auth: auth,
          backup: backup,
          reminder: ReminderService(
            scheduler: FakeScheduler(),
            audio: FakeAudio(),
            tts: tts,
            enableInAppTimers: false,
          ),
          theme: theme,
          permissionStatus: perm,
          settingsDao: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染昵称、用户名与默认响铃', (tester) async {
    await pumpPage(tester);
    expect(find.text('小许'), findsWidgets);
    expect(find.text('@xiaoxu'), findsOneWidget);
    expect(find.text('30 秒'), findsOneWidget);
    expect(find.text('本地账户'), findsOneWidget);
  });

  testWidgets('未设置默认响铃时展示兜底 10 秒', (tester) async {
    auth = FakeAuthService(
      user: User(
        id: 1,
        username: 'xiaoxu',
        passwordHash: 'fake',
        nickname: '小许',
        createdAt: DateTime(2026, 8, 5),
      ),
    );
    await pumpPage(tester);
    expect(find.text('10 秒'), findsOneWidget);
  });

  testWidgets('编辑昵称持久化并刷新', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('编辑昵称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新昵称');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(auth.loggedInUser!.nickname, '新昵称');
    expect(find.text('新昵称'), findsWidgets);
  });

  testWidgets('导出数据需确认后调用备份服务', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('导出数据'));
    await tester.pumpAndSettle();
    // 确认弹窗出现且尚未导出
    expect(find.textContaining('备份不包含密码哈希'),
        findsOneWidget);
    expect(backup.exportCalls, 0);
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.pumpAndSettle();
    expect(backup.exportCalls, 1);
    expect(find.text('备份已生成，请保存到安全位置'), findsOneWidget);
  });

  testWidgets('取消导出不触发备份', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('导出数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(backup.exportCalls, 0);
  });

  testWidgets('导入数据确认后导入并提示条数', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('导入数据'));
    await tester.pumpAndSettle();
    // 确认弹窗展示备份条数与合并规则
    expect(find.textContaining('备份中共有 3 条任务'), findsOneWidget);
    expect(backup.importedJson, isNull);
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();
    expect(backup.importedJson, '{"version":1,"tasks":[]}');
    expect(find.text('已导入 3 条任务'), findsOneWidget);
  });

  testWidgets('导入格式非法在确认前拦截', (tester) async {
    backup.validateError = const FormatException('备份文件格式不正确');
    await pumpPage(tester);
    await tester.tap(find.text('导入数据'));
    await tester.pumpAndSettle();
    // 不出现确认弹窗，直接提示错误
    expect(find.text('备份文件格式不正确'), findsOneWidget);
    expect(find.textContaining('备份中共有'), findsNothing); // 弹窗未出现
    expect(backup.importedJson, isNull);
  });

  testWidgets('提醒设置行展示权限摘要并可进入引导页', (tester) async {
    await pumpPage(tester);
    // 通知权限已开启 → 摘要「已开启」
    expect(find.text('已开启'), findsOneWidget);
    await tester.tap(find.text('提醒设置'));
    await tester.pumpAndSettle();
    expect(find.text('开启提醒，日程不迟到'), findsOneWidget);
  });

  testWidgets('深色模式抽屉切换三档并持久化', (tester) async {
    await pumpPage(tester);
    expect(find.text('跟随系统'), findsOneWidget);
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);
    expect(settings.store[AppSettingsDao.kThemeModeKey], 'dark');
    expect(find.text('深色'), findsOneWidget); // 主行尾值更新
  });

  testWidgets('播报音色抽屉选择后应用并持久化', (tester) async {
    await pumpPage(tester);
    expect(find.text('默认音色'), findsOneWidget);
    await tester.tap(find.text('播报音色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通话 · 女声'));
    await tester.pumpAndSettle();
    expect(tts.appliedVoiceId, 'v-female');
    expect(settings.store[AppSettingsDao.kTtsVoiceIdKey], 'v-female');
    expect(find.text('普通话 · 女声'), findsOneWidget); // 主行尾值更新
  });

  testWidgets('退出登录回到登录页并清空 session', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    // 确认弹窗：点「退出」后才真正登出
    expect(find.text('确定要退出当前账号吗？退出后需重新登录才能使用任务模块。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(auth.loggedInUser, isNull);
  });
}
