import 'package:flutter/material.dart';

import '../data/models/user.dart';
import '../modules/tasks/tasks_tab.dart';
import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../services/task_store.dart';
import '../widgets/empty_state.dart';
import 'login_page.dart';

/// 主界面：三 Tab 外壳（任务 / 记事本 / 我的），对应设计稿底部导航。
///
/// 任务与记事本 Tab 在阶段 1 先呈现真实空状态；
/// 任务 Tab 于 Task 12/15 接入 SQLite TaskStore，记事本 Tab 于阶段 3 接入六子功能，
/// 「我的」先提供登出（完整资料页见 Task 16）。
class MainPage extends StatefulWidget {
  final AuthService? authService;
  final int userId;
  final TaskStore? taskStore;
  final ReminderService? reminder;

  const MainPage({
    super.key,
    this.authService,
    this.userId = 1,
    this.taskStore,
    this.reminder,
  });

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
          _ProfileTab(auth: _auth),
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

/// 「我的」占位页：展示当前用户并支持登出（完整资料/备份见 Task 16）。
class _ProfileTab extends StatelessWidget {
  final AuthService auth;

  const _ProfileTab({required this.auth});

  Future<void> _logout(BuildContext context) async {
    await auth.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: FutureBuilder<User?>(
        future: auth.currentUser(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          final displayName =
              user?.nickname?.isNotEmpty == true ? user!.nickname! : user?.username;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 32,
                    child: Text(
                      displayName?.isNotEmpty == true
                          ? displayName!.characters.first
                          : '?',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName ?? '未登录',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.tonal(
                      onPressed: () => _logout(context),
                      child: const Text('退出登录'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
