import 'dart:async';

import 'package:flutter/material.dart';

import '../modules/notebook/notebook_tab.dart';
import '../modules/tasks/tasks_tab.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/notebook_store.dart';
import '../services/reminder_service.dart';
import '../services/task_store.dart';
import '../theme/theme_controller.dart';
import 'profile_page.dart';

/// 主界面：三 Tab 外壳（任务 / 记事本 / 我的），对应设计稿底部导航。
///
/// 任务 Tab 接入 SQLite TaskStore；记事本 Tab 于阶段 3 接入六子功能；
/// 我的 Tab 提供资料/备份/提醒引导/登出。
class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    this.authService,
    this.userId = 1,
    this.taskStore,
    this.reminder,
    this.notebookStore,
    this.theme,
  });

  final AuthService? authService;
  final int userId;
  final TaskStore? taskStore;
  final ReminderService? reminder;
  final NotebookStore? notebookStore;
  final ThemeController? theme;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final AuthService _auth = widget.authService ?? AuthService();
  late final TaskStore _store =
      widget.taskStore ?? TaskStore(userId: widget.userId);
  late final ReminderService _reminder =
      widget.reminder ?? ReminderService();
  late final NotebookStore _notebook =
      widget.notebookStore ?? NotebookStore(userId: widget.userId);
  late final ThemeController _theme;
  int _index = 0;
  // 展示名以登录用户资料为准；加载完成前不显示占位昵称
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    // 复用全局主题控制器（登录流程进入时未显式传入也能共享）
    _theme = widget.theme ?? ThemeScope.of(context);
    // 读取昵称用于首页问候语；同时初始化提醒服务并重排全部任务
    unawaited(_init());
  }

  Future<void> _init() async {
    await _refreshDisplayName();
    try {
      await _reminder.init(_store);
      await _reminder.reloadSettings(widget.userId);
      await _reminder.scheduleAll();
    } catch (_) {
      // 提醒初始化失败不阻断主流程
    }
  }

  /// 重新读取当前用户资料并刷新问候语展示名；
  /// 供「我的」页修改昵称后回调，保证首页昵称即时同步。
  Future<void> _refreshDisplayName() async {
    final user = await _auth.currentUser();
    if (user == null || !mounted) return;
    final name = user.nickname?.isNotEmpty == true
        ? user.nickname!
        : user.username;
    if (name != _displayName) setState(() => _displayName = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TasksTab(
            store: _store,
            reminder: _reminder,
            displayName: _displayName,
            userId: widget.userId,
            onOpenProfile: () => setState(() => _index = 2),
          ),
          NotebookTab(store: _notebook),
          ProfilePage(
            auth: _auth,
            backup: BackupService(),
            reminder: _reminder,
            theme: _theme,
            // 昵称修改后刷新首页问候语
            onNicknameChanged: _refreshDisplayName,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: '任务',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_alt_outlined),
            selectedIcon: Icon(Icons.note_alt),
            label: '记事本',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
