import 'package:flutter/material.dart';

import '../data/daos/app_settings_dao.dart';
import '../data/models/user.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/permission_status_service.dart';
import '../services/reminder_service.dart';
import '../services/tts_service.dart';
import '../theme/theme_controller.dart';
import '../widgets/confirm_dialog.dart';
import 'login_page.dart';
import 'permission_guide_screen.dart';

/// 我的页：用户信息 + 平铺菜单（与页面融合，无卡片/边框/阴影）。
///
/// 菜单项：编辑昵称 / 默认响铃时长 / 导出数据 / 导入数据 / 提醒设置 /
/// 播报音色 / 深色模式 / 关于时说 + 退出登录。
/// 导入导出均带确认弹窗；提醒设置行实时摘要通知权限「已开启 / 未开启」；
/// 深色三档与播报音色走底部抽屉选择并持久化到设备级设置。
///
/// 依赖 [AuthService]（用户资料）、[BackupService]（备份）、
/// [ReminderService]（提醒与 TTS）、[ThemeController]（主题三档）、
/// [PermissionStatusService]（权限状态摘要）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.auth,
    this.backup,
    this.reminder,
    this.theme,
    this.permissionStatus,
    this.settingsDao,
  });

  final AuthService auth;
  final BackupService? backup;
  final ReminderService? reminder;
  final ThemeController? theme;
  final PermissionStatusService? permissionStatus;
  final AppSettingsDao? settingsDao;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final BackupService _backup = widget.backup ?? BackupService();
  late final ReminderService _reminder =
      widget.reminder ?? ReminderService();
  late final ThemeController _theme;
  late final PermissionStatusService _permissionStatus =
      widget.permissionStatus ?? PermissionStatusService();
  late final AppSettingsDao _settingsDao =
      widget.settingsDao ?? AppSettingsDao();

  /// 提醒权限摘要（通知/电池/自启动），加载前为 null。
  ReminderPermissionStatus? _permStatus;

  /// 系统 TTS 可选音色列表与当前选中音色键。
  List<TtsVoice> _voices = const [];
  String? _voiceId;
  String? _voiceLabel;

  @override
  void initState() {
    super.initState();
    // 复用全局主题控制器：登录流程进入时也能共享「深色模式」档位
    _theme = widget.theme ?? ThemeScope.of(context);
    // 并行加载权限摘要与音色列表（失败各自静默兜底）
    _loadPermissionSummary();
    _loadVoice();
  }

  /// 加载提醒权限摘要（进页与从提醒设置返回后调用）。
  Future<void> _loadPermissionSummary() async {
    final status = await _permissionStatus.reminderStatus();
    if (!mounted) return;
    setState(() => _permStatus = status);
  }

  /// 加载播报音色：查询引擎语音列表 + 读取持久化选中项。
  Future<void> _loadVoice() async {
    List<TtsVoice> voices = const [];
    String? voiceId;
    try {
      voices = await _reminder.tts.availableVoices();
      final raw = await _settingsDao.get(AppSettingsDao.kTtsVoiceIdKey);
      voiceId = (raw == null || raw.isEmpty) ? null : raw;
    } catch (_) {
      // 引擎/设置不可用时按默认音色展示
    }
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voiceId = voiceId;
      _voiceLabel = _findVoiceName(voices, voiceId);
    });
  }

  /// 根据音色键解析展示名；未选中或找不到时返回 null（显示「默认音色」）。
  static String? _findVoiceName(List<TtsVoice> voices, String? voiceId) {
    if (voiceId == null) return null;
    for (final voice in voices) {
      if (voice.key == voiceId || voice.id == voiceId) return voice.name;
    }
    return null;
  }

  /// 编辑昵称：对话框输入后持久化并刷新。
  Future<void> _editNickname(User user) async {
    final controller = TextEditingController(text: user.nickname ?? '');
    final nickname = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑昵称'),
        content: TextField(
          autocorrect: false,
          controller: controller,
          decoration: const InputDecoration(labelText: '昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (nickname == null || !mounted) return;
    await widget.auth.updateProfile(nickname: nickname);
    setState(() {});
  }

  /// 编辑默认响铃时长：数字输入，非法值回退未设置。
  Future<void> _editRing(User user) async {
    final controller = TextEditingController(
      text: user.defaultRingSeconds?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('默认响铃时长'),
        content: TextField(
          autocorrect: false,
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '秒',
            helperText: '新建任务未指定响铃时使用',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await widget.auth.updateProfile(defaultRingSeconds: int.tryParse(value));
    setState(() {});
  }

  /// 导出数据：先弹确认（说明内容与不含密码哈希），确认后生成并分享。
  Future<void> _confirmExport(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: _dialogIcon(Icons.file_upload_outlined),
        title: const Text('导出数据'),
        content: const Text(
          '将生成 JSON 备份文件，包含当前账户的全部任务与个人偏好'
          '（昵称、默认响铃时长）。\n\n'
          '备份不包含密码哈希，导出后请妥善保存，勿随意分享。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('导出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _export(user);
  }

  /// 实际执行导出并提示结果。
  Future<void> _export(User user) async {
    try {
      final json = await _backup.exportJson(user.id!);
      final name =
          'daily_planner_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      await _backup.shareExport(name, json);
      _toast('备份已生成，请保存到安全位置');
    } catch (_) {
      _toast('导出失败');
    }
  }

  /// 导入数据：选文件 → 格式校验 → 确认弹窗（合并规则）→ 执行导入。
  Future<void> _importWithConfirm(User user) async {
    final String? text;
    try {
      text = await _backup.pickImportFile();
    } catch (_) {
      _toast('导入失败');
      return;
    }
    if (text == null || !mounted) return; // 用户取消选文件

    // 确认前先校验格式：非法文件直接拦截报错，不弹确认
    final int count;
    try {
      count = _backup.validateImport(text);
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    } catch (_) {
      _toast('导入失败');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: _dialogIcon(Icons.file_download_outlined, warn: true),
        title: const Text('导入数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '备份中共有 $count 条任务，将合并进当前账户。'
              '与现有任务 ID 冲突的条目自动跳过，不会覆盖或删除现有数据。',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.errorContainer.withValues(
                    alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '导入不可撤销；重复导入同一备份可能产生重复任务。'
                '导入前建议先导出当前数据。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final imported = await _backup.importJson(user.id!, text);
      _toast('已导入 $imported 条任务');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('导入失败');
    }
  }

  /// 打开提醒设置引导页；返回后刷新通知权限摘要。
  Future<void> _openReminderSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PermissionGuideScreen(
          reminder: _reminder,
          permissionStatus: _permissionStatus,
        ),
      ),
    );
    if (mounted) await _loadPermissionSummary();
  }

  /// 播报音色：底部抽屉单选（默认音色 + 系统语音列表），持久化并立即应用。
  Future<void> _pickVoice() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '播报音色',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                '使用系统语音引擎朗读提醒；可选音色随机型与 TTS 引擎不同。',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _voiceOption(
                      ctx,
                      key: null,
                      name: '默认音色',
                      desc: '跟随系统 TTS 默认设置 · 推荐',
                    ),
                    for (final voice in _voices)
                      _voiceOption(
                        ctx,
                        key: voice.key,
                        name: voice.name,
                        desc: voice.locale,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const _SheetNote(
                text: '音色列表来自系统 TTS 引擎，机型不同列表不同；'
                    '引擎无可选音色时仅显示「默认音色」。',
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == _voiceId || !mounted) return;
    setState(() {
      _voiceId = selected;
      _voiceLabel = _findVoiceName(_voices, selected);
    });
    try {
      await _settingsDao.set(
        AppSettingsDao.kTtsVoiceIdKey,
        selected ?? '',
      );
      await _reminder.tts.setVoice(selected);
    } catch (_) {
      // 持久化或应用失败不影响本次展示
    }
  }

  /// 音色抽屉单选项。
  Widget _voiceOption(
    BuildContext ctx, {
    required String? key,
    required String name,
    required String desc,
  }) {
    final selected = key == _voiceId;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(ctx).pop(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(ctx).colorScheme.primaryContainer
                    : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.volume_up_outlined,
                size: 20,
                color: selected
                    ? Theme.of(ctx).colorScheme.primary
                    : Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: Theme.of(ctx).colorScheme.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  /// 深色模式：底部抽屉三档单选，持久化并全局生效。
  Future<void> _pickTheme() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '深色模式',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                '选择外观模式，全应用生效（含登录前页面）。',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              // 选项区可滚动，避免小屏/测试环境底部抽屉溢出
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _themeOption(ctx, ThemeMode.system, '跟随系统',
                        '随手机外观设置自动切换', Icons.brightness_auto_outlined),
                    _themeOption(ctx, ThemeMode.light, '浅色', '始终使用浅色外观',
                        Icons.light_mode_outlined),
                    _themeOption(ctx, ThemeMode.dark, '深色', '始终使用深色外观',
                        Icons.dark_mode_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const _SheetNote(
                text: '选择即时生效并记住；选择「跟随系统」时深色模式开关由手机控制。',
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _theme.setMode(selected);
    if (mounted) setState(() {});
  }

  /// 深色模式抽屉单选项。
  Widget _themeOption(
    BuildContext ctx,
    ThemeMode mode,
    String name,
    String desc,
    IconData icon,
  ) {
    final selected = mode == _theme.mode;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(ctx).pop(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(ctx).colorScheme.primaryContainer
                    : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? Theme.of(ctx).colorScheme.primary
                    : Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: Theme.of(ctx).colorScheme.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  /// 关于时说：展示版本与简介。
  Future<void> _showAbout() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: _dialogIcon(Icons.info_outline),
        title: const Text('关于时说'),
        content: const Text('时说 v1.0.0\n\n每日规划助手：定时提醒 + 语音解析自动规划。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 确认弹窗顶部图标容器。
  Widget _dialogIcon(IconData icon, {bool warn = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Icon(
        icon,
        size: 26,
        color: warn ? scheme.error : scheme.primary,
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    final ok = await ConfirmDialog.show(
      context,
      '退出登录',
      '确定要退出当前账号吗？退出后需重新登录才能使用任务模块。',
      '退出',
    );
    if (!ok || !mounted) return;
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  /// 主题档位展示文案。
  String get _themeLabel => switch (_theme.mode) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
      };

  /// 音色展示文案（默认音色）。
  String get _voiceLabelText => _voiceLabel ?? '默认音色';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: FutureBuilder<User?>(
        future: widget.auth.currentUser(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final displayName =
              user.nickname?.isNotEmpty == true ? user.nickname! : user.username;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 用户信息区：头像 + 昵称 + 本地账户徽标 + 编辑入口
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.characters.first,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '本地账户',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${user.username}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _editNickname(user),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑昵称',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // 平铺菜单：行间仅留白，无卡片/边框/阴影
              _menuRow(
                icon: Icons.person_outline,
                accent: true,
                label: '编辑昵称',
                trailing: user.nickname?.isNotEmpty == true
                    ? user.nickname
                    : '未设置',
                onTap: () => _editNickname(user),
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.alarm,
                accent: false,
                label: '默认响铃时长',
                trailing: user.defaultRingSeconds == null
                    ? '未设置'
                    : '${user.defaultRingSeconds} 秒',
                onTap: () => _editRing(user),
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.file_upload_outlined,
                accent: true,
                label: '导出数据',
                trailing: 'JSON 备份',
                onTap: () => _confirmExport(user),
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.file_download_outlined,
                accent: false,
                label: '导入数据',
                trailing: '恢复备份',
                onTap: () => _importWithConfirm(user),
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.notifications_outlined,
                accent: true,
                label: '提醒设置',
                trailingWidget: _permStatus == null
                    ? null
                    : Text(
                        _permStatus!.granted ? '已开启' : '未开启',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _permStatus!.granted
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                onTap: _openReminderSettings,
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.volume_up_outlined,
                accent: false,
                label: '播报音色',
                trailing: _voiceLabelText,
                onTap: _pickVoice,
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.dark_mode_outlined,
                accent: true,
                label: '深色模式',
                trailing: _themeLabel,
                onTap: _pickTheme,
              ),
              const SizedBox(height: 4),
              _menuRow(
                icon: Icons.info_outline,
                accent: false,
                label: '关于时说',
                trailing: 'v1.0.0',
                onTap: _showAbout,
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  onPressed: _logout,
                  child: const Text('退出登录'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 平铺菜单行：图标 + 标签 + 尾值 + 箭头，无边框无背景块。
  Widget _menuRow({
    required IconData icon,
    required bool accent,
    required String label,
    String? trailing,
    Widget? trailingWidget,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 19,
                color: accent
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailingWidget != null)
              trailingWidget
            else if (trailing != null)
              Text(
                trailing,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 20, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 抽屉底部说明条（accent-soft 底色 + 提示文案）。
class _SheetNote extends StatelessWidget {
  const _SheetNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 15,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
