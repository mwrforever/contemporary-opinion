import 'package:flutter/material.dart';

/// 全局设计语言（依据 UI UX Pro Max + Taste Skill V1）
///
/// 设计基调：Minimalist Productivity —— 单一去饱和强调色、留白即层次、
/// 8px 间距系统、扩散阴影（非霓虹辉光）。
///
/// Taste Skill 关键约束：
/// - 单一强调色（青绿），饱和度 < 80%，避开 AI 紫蓝与纯黑（#000）。
/// - 反卡片滥用：用发丝边框 + 扩散阴影营造层次，而非堆叠重阴影。
/// - 完整交互态：加载/空/错误/触感反馈。
class AppTheme {
  // ── 强调色（去饱和青绿）──────────────────────────────
  static const Color accent = Color(0xFF0F8C7E);
  static const Color accentStrong = Color(0xFF0A6E63); // 浅底上的强调文字
  static const Color accentSoft = Color(0xFFE4F4F1); // 浅底强调背景

  // ── 语义色（均做降饱和处理，避免刺眼）────────────────
  static const Color danger = Color(0xFFC24A3A); // 冲突 / 删除 / 错误
  static const Color dangerSoft = Color(0xFFFBEDEA);
  static const Color warn = Color(0xFFC07A2E); // 即将到来 / 时间重叠提醒
  static const Color warnSoft = Color(0xFFFBF1E4);
  static const Color ok = Color(0xFF3A9D6B); // 已完成 / 正常生效
  static const Color okSoft = Color(0xFFE6F4EC);

  // ── 待安排中性色（需稳定身份，非 onSurface 临时 alpha）────────
  static const Color neutral = Color(0xFF8A938F); // 浅色模式文字/图标
  static const Color neutralDark = Color(0xFF9AA39F); // 深色模式文字/图标

  // ── 语义色深色变体（仅深色模式用于文字/图标，提对比至 AA）──
  static const Color dangerDark = Color(0xFFE0705F); // danger 暗色文字/图标
  static const Color okDark = Color(0xFF5FBE8C); // ok 暗色文字/图标
  static const Color warnDark = Color(0xFFE0A050); // warn 暗色文字/图标

  // ── 圆角（统一阶梯）──────────────────────────────────
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radius = radiusLg; // 兼容旧引用

  // ── 间距（8px 基准）─────────────────────────────────
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  static ThemeData get light => _build(false);
  static ThemeData get dark => _build(true);

  /// 扩散阴影：轻盈、宽展、低透明度，营造"浮起"而非"发光"。
  static List<BoxShadow> elevation(bool isDark) => [
        BoxShadow(
          color: isDark
              ? const Color(0x40000000)
              : const Color(0x14000000),
          blurRadius: isDark ? 28 : 24,
          offset: const Offset(0, 8),
        ),
      ];

  static ThemeData _build(bool isDark) {
    final seed = accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
      surface: isDark ? const Color(0xFF161A19) : const Color(0xFFFCFDFC),
      onSurface: isDark ? const Color(0xFFE7EAEC) : const Color(0xFF1A1F1E),
    );

    final textTheme = TextTheme(
      // 品牌 / 大标题
      displaySmall: const TextStyle(
          fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      // 页面标题
      titleLarge: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      // 卡片标题
      titleMedium: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      // 正文
      bodyLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5),
      bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45),
      // 按钮
      labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      // 标签 / 统计数
      labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      // 说明 / 辅助
      labelSmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1110) : const Color(0xFFF6F7F4),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? const Color(0xFF0E1110) : const Color(0xFFF6F7F4),
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.07),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: textTheme.labelMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        elevation: 0,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.onSurface.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
