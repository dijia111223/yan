import 'package:flutter/material.dart';

/// 全应用字体。集中定义，避免字体名散落各处。
///
/// 用私有构造而非 `abstract final class`：后者是 Dart 3.9 语法，
/// 鸿蒙线用的 Flutter 3.27 只带 Dart 3.6。
class AppFonts {
  const AppFonts._();

  static const String body = 'SimHei';

  static const List<String> fallback = <String>[
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'HarmonyOS Sans SC',
    'Source Han Sans SC',
    'PingFang SC',
    'sans-serif',
  ];

  /// 代码块 / frontmatter 源码 / 公式源码。
  ///
  /// 不用泛型名 `'monospace'`：Windows 上解析不到，会回落到 CJK 字体，
  /// 拉丁字母变成全角、缩进全乱。
  static const String mono = 'Consolas';

  static const List<String> monoFallback = <String>[
    'Cascadia Mono',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Menlo',
    'Monaco',
    'Courier New',
    'monospace',
  ];

  static TextStyle bodyStyle(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontFamily: body, fontFamilyFallback: fallback);

  static TextStyle monoStyle(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontFamily: mono, fontFamilyFallback: monoFallback);

  /// 把 [ThemeData] 的文字体系换成黑体，其余保持 Flutter 默认。
  static ThemeData apply(ThemeData theme) {
    TextStyle? n(TextStyle? s) => s == null ? null : bodyStyle(s);
    TextStyle v(TextStyle? s) => bodyStyle(s);

    final textTheme = TextTheme(
      displayLarge: n(theme.textTheme.displayLarge),
      displayMedium: n(theme.textTheme.displayMedium),
      displaySmall: n(theme.textTheme.displaySmall),
      headlineLarge: n(theme.textTheme.headlineLarge),
      headlineMedium: n(theme.textTheme.headlineMedium),
      headlineSmall: n(theme.textTheme.headlineSmall),
      titleLarge: n(theme.textTheme.titleLarge),
      titleMedium: n(theme.textTheme.titleMedium),
      titleSmall: n(theme.textTheme.titleSmall),
      bodyLarge: n(theme.textTheme.bodyLarge),
      bodyMedium: n(theme.textTheme.bodyMedium),
      bodySmall: n(theme.textTheme.bodySmall),
      labelLarge: n(theme.textTheme.labelLarge),
      labelMedium: n(theme.textTheme.labelMedium),
      labelSmall: n(theme.textTheme.labelSmall),
    );

    return theme.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // black / white 都要给，否则深色模式会用回默认字体
      typography: Typography.material2021(
        platform: theme.platform,
        black: textTheme,
        white: textTheme,
      ),
      // 下列组件的文字样式不继承 textTheme，需逐个覆盖
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: v(theme.appBarTheme.titleTextStyle ?? const TextStyle(fontSize: 20)),
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        titleTextStyle: v(theme.dialogTheme.titleTextStyle ?? const TextStyle(fontSize: 20)),
        contentTextStyle: v(theme.dialogTheme.contentTextStyle ?? const TextStyle(fontSize: 14)),
      ),
      tooltipTheme: theme.tooltipTheme.copyWith(
        textStyle: v(theme.tooltipTheme.textStyle ?? const TextStyle(fontSize: 12)),
      ),
      snackBarTheme: theme.snackBarTheme.copyWith(
        contentTextStyle: v(theme.snackBarTheme.contentTextStyle ?? const TextStyle(fontSize: 14)),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        hintStyle: n(theme.inputDecorationTheme.hintStyle),
        labelStyle: n(theme.inputDecorationTheme.labelStyle),
      ),
    );
  }
}
