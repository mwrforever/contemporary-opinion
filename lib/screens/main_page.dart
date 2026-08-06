import 'dart:async';

import 'package:flutter/material.dart';

import '../modules/notebook/notebook_tab.dart';
import '../modules/tasks/tasks_tab.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/notebook_store.dart';
import '../services/reminder_service.dart';
import '../services/task_store.dart';
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
  });

  final AuthService? authService;
  final int userId;
  final TaskStore? taskStore;
  final ReminderService? reminder;
  final NotebookStore? notebookStore;

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
  int _index = 0;
  String _displayName = '朋友';

  @override
  void initState() {
    super.initState();
    // 读取昵称用于首页问候语；同时初始化提醒服务并重排全部任务
    unawaited(_init());
  }

  Future<void> _init() async {
    final user = await _auth.currentUser();
    if (user != null && mounted) {
      final name = user.nickname?.isNotEmpty == true
          ? user.nickname!
          : user.username;
      if (name.isNotEmpty) setState(() => _displayName = name);
    }
    try {
      await _reminder.init(_store);
      await _reminder.reloadSettings(widget.userId);
      await _reminder.scheduleAll();
    } catch (_) {
      // 提醒初始化失败不阻断主流程
    }
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
