import 'package:flutter/material.dart';


/// 底部导航栏：M3 规范的 [NavigationBar] 封装。
///
/// 仅承载「任务 / 记事本」两个 Tab（范围决策：不设置 Tab）。
/// 选中项用主色图标+文字，未选项使用 onSurface 低透明度；指示器为
/// [NavigationBar] 自带药丸，不另加辉光。
class BottomNav extends StatelessWidget {
  /// 当前选中索引。
  final int currentIndex;

  /// 切换回调。
  final ValueChanged<int> onTap;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: scheme.surface,
      elevation: 0,
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
      ],
    );
  }
}
