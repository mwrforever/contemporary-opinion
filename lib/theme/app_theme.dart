import 'package:flutter/material.dart';

/// 全局设计语言（依据 docs/superpowers/specs/2026-08-05-shishuo-ui-design.md 方向 A 温暖平面）
///
/// 设计基调：单一去饱和青绿强调色、暖白底、8px 间距系统、低扩散阴影；
/// 浅/深两套 Token 精确锁定，不做 fromSeed 漂色。
/// 关键约束：浅色主按钮用加深强调色（[accentStrong]）保证白字对比度 ≥4.5:1。
class AppTheme {
  // ── 强调色（设计规范锁定）────────────────────────────
  static const Color accent = Color(0xFF0E8C7F);
  static const Color accentStrong = Color(0xFF0A7368); // 浅色主按钮底
  static const Color accentSoft = Color(0xFFE2F4F1);

  // ── 语义色（设计规范锁定）────────────────────────────
  static const Color danger = Color(0xFFC0492F); // 冲突 / 删除 / 错误
  static const Color dangerSoft = Color(0xFFFBE9E4);
  static const Color warn = Color(0xFFC9782B); // 时间重叠弱提醒 / 待定
  static const Color warnSoft = Color(0xFFFBF1E3);
  static const Color ok = Color(0xFF3F9D6B); // 已完成 / 收入
  static const Color okSoft = Color(0xFFE4F3EA);

  // ── 中性色（三级文本）──────────────────────────────
  static const Color neutral = Color(0xFF8A8D85); // 浅色模式辅助文本
  static const Color neutralDark = Color(0xFF6B6F68); // 深色模式辅助文本

  // ── 语义色深色变体（深色模式文字/图标，保证 AA 对比）──
  static const Color dangerDark = Color(0xFFE08A74);
  static const Color okDark = Color(0xFF6FBF92);
  static const Color warnDark = Color(0xFFE0A263);

  // ── 圆角（统一阶梯：卡片 20 / 按钮 14 / 输入框 12）──
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusInput = 12;
  static const double radius = radiusLg; // 兼容旧引用

  // ── 间距（8px 基准）─────────────────────────────────
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  static ThemeData get light => buildAppTheme(Brightness.light);
  static ThemeData get dark => buildAppTheme(Brightness.dark);

  /// 扩散阴影：轻盈、宽展、低透明度，营造「浮起」而非「发光」。
  static List<BoxShadow> elevation(bool isDark) => [
        BoxShadow(
          color: isDark ? const Color(0x40000000) : const Color(0x14000000),
          blurRadius: isDark ? 28 : 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// 构建完整主题：Token 精确落地 + 组件主题收敛。
  ///
  /// [brightness] 决定浅/深两套 Token（跟随系统由 App/ThemeMode.system 切换）。
  static ThemeData buildAppTheme([Brightness brightness = Brightness.light]) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      // 品牌强调色与按钮色（浅色按钮用 accentStrong 保对比）
      primary: isDark ? const Color(0xFF4FBFAF) : accent,
      onPrimary: isDark ? const Color(0xFF101315) : Colors.white,
      primaryContainer: isDark ? const Color(0xFF143834) : accentSoft,
      onPrimaryContainer: isDark ? const Color(0xFF4FBFAF) : accentStrong,
      // 次级语义（ok 系列）
      secondary: isDark ? const Color(0xFF8FB5AC) : const Color(0xFF4A6B64),
      onSecondary: isDark ? const Color(0xFF101315) : Colors.white,
      secondaryContainer: isDark ? const Color(0xFF1C3326) : okSoft,
      onSecondaryContainer: isDark ? okDark : ok,
      // 错误（danger 系列）
      error: isDark ? dangerDark : danger,
      onError: isDark ? const Color(0xFF101315) : Colors.white,
      errorContainer: isDark ? const Color(0xFF3A211B) : dangerSoft,
      onErrorContainer: isDark ? dangerDark : const Color(0xFF8F2E1A),
      // 表面与文本
      surface: isDark ? const Color(0xFF1A1D20) : Colors.white,
      onSurface: isDark ? const Color(0xFFF2F3EF) : const Color(0xFF1C1E1B),
      surfaceContainerHighest:
          isDark ? const Color(0xFF23272B) : const Color(0xFFEEF1EC),
      onSurfaceVariant:
          isDark ? const Color(0xFF9EA19A) : const Color(0xFF5C5F58),
      outline: isDark ? const Color(0xFF2A2E32) : const Color(0xFFE2E5DF),
      outlineVariant:
          isDark ? const Color(0xFF2A2E32) : const Color(0xFFE2E5DF),
      surfaceTint: Colors.transparent,
    );

    final textTheme = TextTheme(
      // 品牌 / 大标题
      displaySmall: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      // 页面标题 20/800
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      // 卡片标题 16/600
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      // 正文 15/400 行高 1.5
      bodyLarge: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      // 正文 14/400 行高 1.5
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      // 按钮 16/600
      labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      // 标签 / 统计 13/600
      labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      // 辅助 12/400
      labelSmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    final bgColor =
        isDark ? const Color(0xFF101315) : const Color(0xFFF6F7F4);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bgColor,
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
          backgroundColor: isDark ? scheme.primary : accentStrong,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? scheme.primary : accentStrong,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
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
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        shape: const StadiumBorder(),
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusInput),
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.surface
                : Colors.transparent,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
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
