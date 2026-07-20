import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/aliyun_asr_service.dart';
import '../../../services/aliyun_schedule_service.dart';
import '../../../services/notebook_store.dart';
import '../../../services/notebook_voice_service.dart';
import '../../../services/reminder_service.dart';
import '../../../theme/app_theme.dart';
import 'screens/ledger_detail.dart';
import 'screens/reading_detail.dart';
import 'screens/recipe_detail.dart';
import 'screens/shopping_detail.dart';
import 'screens/study_course_list.dart';
import 'screens/trip_detail.dart';
import 'widgets/notebook_hub_card.dart';

/// 记事本 Tab：以 2 列网格呈现六大子功能入口，格内显示条目数量。
///
/// 视觉按 UI UX Pro Max + Taste V1 重做：更大更精致的图标容器、更透气的排版、
/// 发丝边框 + 扩散阴影；**不含任何加号**（录入入口在各子功能详情页）。
class NotebookTab extends StatelessWidget {
  final AliyunAsrService asr;
  final AliyunScheduleService? schedule;
  final ReminderService? reminder;
  final NotebookVoiceService notebookVoice;

  const NotebookTab({
    super.key,
    required this.asr,
    this.schedule,
    this.reminder,
    required this.notebookVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记事本')),
      body: Consumer<NotebookStore>(
        builder: (context, store, _) {
          final items = <_SubItem>[
            _SubItem(
              key: 'shopping',
              title: '购物清单',
              icon: Icons.shopping_bag_outlined,
              count: store.shopping.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ShoppingDetail(
                  asr: asr,
                  voice: notebookVoice,
                ),
              )),
            ),
            _SubItem(
              key: 'ledger',
              title: '收支账本',
              icon: Icons.account_balance_wallet_outlined,
              count: store.ledger.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LedgerDetail(
                  asr: asr,
                  voice: notebookVoice,
                ),
              )),
            ),
            _SubItem(
              key: 'reading',
              title: '读书清单',
              icon: Icons.menu_book_outlined,
              count: store.reading.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReadingDetail(
                  asr: asr,
                  voice: notebookVoice,
                ),
              )),
            ),
            _SubItem(
              key: 'trip',
              title: '旅游行程',
              icon: Icons.luggage_rounded,
              count: store.trips.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TripDetail(
                  asr: asr,
                  voice: notebookVoice,
                ),
              )),
            ),
            _SubItem(
              key: 'study',
              title: '学习记录',
              icon: Icons.school_outlined,
              count: store.courses.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StudyCourseList(
                  asr: asr,
                  voice: notebookVoice,
                ),
              )),
            ),
            _SubItem(
              key: 'recipe',
              title: '菜谱收藏',
              icon: Icons.restaurant_menu_outlined,
              count: store.recipes.length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RecipeDetail(
                  asr: asr,
                  voice: notebookVoice,
                ),
              )),
            ),
          ];

          return GridView.builder(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppTheme.spaceMd,
              mainAxisSpacing: AppTheme.spaceMd,
              childAspectRatio: 1.15,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final it = items[i];
              return NotebookHubCard(
                icon: it.icon,
                title: it.title,
                count: it.count,
                onTap: it.onTap,
              );
            },
          );
        },
      ),
    );
  }
}

class _SubItem {
  final String key;
  final String title;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  _SubItem({
    required this.key,
    required this.title,
    required this.icon,
    required this.count,
    required this.onTap,
  });
}
