import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 记事本 hub 的子功能入口卡（重设计版，依据 UI UX Pro Max + Taste V1）。
///
/// 视觉要点：更大的强调色图标容器、标题/计数更透气的排版、发丝边框 + 扩散阴影
/// 沿用 [AppTheme]，统一复用设计令牌。卡片**不含任何加号**，点击进对应子功能详情页。
class NotebookHubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;

  const NotebookHubCard({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
            boxShadow: AppTheme.elevation(isDark),
          ),
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(icon, color: AppTheme.accent, size: 28),
              ),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '$count 条',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
