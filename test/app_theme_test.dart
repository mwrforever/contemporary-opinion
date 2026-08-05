// 设计 Token 落地测试：浅/深主题色值、文本层级、组件形状与尺寸
import 'package:daily_planner/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('浅色主题 Token 与设计规范精确一致', () {
    final t = AppTheme.buildAppTheme(Brightness.light);
    expect(t.colorScheme.primary, const Color(0xFF0E8C7F));
    expect(t.colorScheme.onPrimary, const Color(0xFFFFFFFF));
    expect(t.colorScheme.primaryContainer, const Color(0xFFE2F4F1));
    expect(t.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(t.colorScheme.onSurface, const Color(0xFF1C1E1B));
    expect(t.colorScheme.error, const Color(0xFFC0492F));
    expect(t.scaffoldBackgroundColor, const Color(0xFFF6F7F4));
  });

  test('深色主题 Token 与设计规范精确一致', () {
    final t = AppTheme.buildAppTheme(Brightness.dark);
    expect(t.colorScheme.primary, const Color(0xFF4FBFAF));
    expect(t.colorScheme.onPrimary, const Color(0xFF101315));
    expect(t.colorScheme.surface, const Color(0xFF1A1D20));
    expect(t.scaffoldBackgroundColor, const Color(0xFF101315));
  });

  test('文本层级：页面标题 20/800、按钮 16/600、正文 14/400 行高 1.5', () {
    final t = AppTheme.buildAppTheme();
    expect(t.textTheme.titleLarge!.fontSize, 20);
    expect(t.textTheme.titleLarge!.fontWeight, FontWeight.w800);
    expect(t.textTheme.titleMedium!.fontSize, 16);
    expect(t.textTheme.titleMedium!.fontWeight, FontWeight.w600);
    expect(t.textTheme.labelLarge!.fontSize, 16);
    expect(t.textTheme.labelLarge!.fontWeight, FontWeight.w600);
    expect(t.textTheme.bodyMedium!.fontSize, 14);
    expect(t.textTheme.bodyMedium!.fontWeight, FontWeight.w400);
    expect(t.textTheme.bodyMedium!.height, 1.5);
  });

  test('组件形状：主按钮高 52、卡片圆角 20、输入框圆角 12、chip 胶囊', () {
    final t = AppTheme.buildAppTheme();
    final size =
        t.filledButtonTheme.style!.minimumSize!.resolve(const <WidgetState>{});
    expect(size, const Size(64, 52));
    final card = t.cardTheme.shape! as RoundedRectangleBorder;
    expect(card.borderRadius, BorderRadius.circular(20));
    final input = t.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    expect(input.borderRadius, BorderRadius.circular(12));
    expect(t.chipTheme.shape, isA<StadiumBorder>());
  });

  test('浅色主按钮背景使用加深强调色保证白字对比度', () {
    final t = AppTheme.buildAppTheme(Brightness.light);
    final bg = t.filledButtonTheme.style!.backgroundColor!
        .resolve(const <WidgetState>{});
    expect(bg, const Color(0xFF0A7368));
  });

  test('AppTheme.light/dark 与 buildAppTheme 等价', () {
    expect(
      AppTheme.light.colorScheme.primary,
      AppTheme.buildAppTheme(Brightness.light).colorScheme.primary,
    );
    expect(
      AppTheme.dark.colorScheme.surface,
      AppTheme.buildAppTheme(Brightness.dark).colorScheme.surface,
    );
  });
}
