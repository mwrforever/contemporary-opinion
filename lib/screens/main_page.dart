import 'package:flutter/material.dart';

import '../modules/tasks/tasks_tab.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/reminder_service.dart';
import '../services/task_store.dart';
import '../widgets/empty_state.dart';
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
  });

  final AuthService? authService;
  final int userId;
  final TaskStore? taskStore;
  final ReminderService? reminder;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final AuthService _auth = widget.authService ?? AuthService();
  late final TaskStore _store =
      widget.taskStore ?? TaskStore(userId: widget.userId);
  late final ReminderService _reminder =
      widget.reminder ?? ReminderService();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TasksTab(store: _store, reminder: _reminder),
          // TODO(phase3-notebook): 记事本六子功能 Hub（阶段 3 引入）
          Scaffold(
            appBar: AppBar(title: const Text('记事本')),
            body: EmptyState(),
          ),
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
