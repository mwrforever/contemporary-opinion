import 'package:flutter/material.dart';

import '../modules/notebook/notebook_tab.dart';
import '../modules/tasks/tasks_tab.dart';
import '../services/aliyun_asr_service.dart';
import '../services/aliyun_schedule_service.dart';
import '../services/notebook_voice_service.dart';
import '../services/reminder_service.dart';
import '../services/settings_service.dart';
import '../widgets/bottom_nav.dart';

/// 应用外壳：持有底部导航 [BottomNav] 与 [IndexedStack]。
///
/// [IndexedStack] 同时挂载全部 Tab，切换不销毁子树，天然实现「模块间状态隔离」
/// （筛选条件、滚动位置、表单草稿互不污染）。每个 Tab 各自持有 Scaffold /
/// AppBar / FAB，互不越界。
class TabShell extends StatefulWidget {
  final ReminderService reminder;
  final AliyunAsrService asr;
  final AliyunScheduleService schedule;
  final NotebookVoiceService notebookVoice;
  final SettingsService settings;

  const TabShell({
    super.key,
    required this.reminder,
    required this.asr,
    required this.schedule,
    required this.notebookVoice,
    required this.settings,
  });

  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      TasksTab(
        reminder: widget.reminder,
        asr: widget.asr,
        schedule: widget.schedule,
        settings: widget.settings,
      ),
      NotebookTab(
        asr: widget.asr,
        schedule: widget.schedule,
        reminder: widget.reminder,
        notebookVoice: widget.notebookVoice,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: BottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
