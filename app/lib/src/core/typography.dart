import 'package:flutter/material.dart';

/// 全应用的字体定义 —— 单一事实来源。
///
/// 为什么单独成文件：字体名一旦散落在各处，改一次要翻遍全工程，还容易漏。
/// 这里集中定义，`markdown_theme.dart` / `app.dart` / 各面板都从这里取。
abstract final class AppFonts {
  /// 正文与界面字体：**黑体**。
  ///
  /// 黑体是中文正文最稳的选择：字形方正、屏幕上笔画均匀、没有宋体的衬线退化问题。
  /// Windows 上字体族名是 `SimHei`（安装文件 simhei.ttf，注册名 "SimHei"）。
  ///
  /// 跨平台说明：鸿蒙 / Android / Linux 上没有 SimHei，字体族找不到时 Flutter 会
  /// 沿 [fallback] 依次尝试，最终回落到系统默认无衬线字体——所以这套写法在
  /// 任何平台都能正常显示中文，只是在 Windows 上才会得到"黑体"本身。
  static const String body = 'SimHei';

  /// 正文的回落链。
  static const List<String> fallback = <String>[
    'Microsoft YaHei', // Windows 备选（同为无衬线黑体风格）
    '微软雅黑',
    'Noto Sans CJK SC', // Android / Linux 常见
    'HarmonyOS Sans SC', // 鸿蒙
    'Source Han Sans SC',
    'PingFang SC', // macOS / iOS
    'sans-serif',
  ];

  /// 等宽字体：代码块、frontmatter 源码、公式源码。
  ///
  /// 这一处**刻意不用黑体**：等宽是代码可读性的硬需求（对齐、缩进、字符宽度一致），
  /// 黑体是比例字体，改用后代码块排版会散掉。
  ///
  /// 为什么不用 `'monospace'` 这个泛型名：实测在 Windows 上它**解析不到**，
  /// 引擎会回落到 CJK 字体，于是 `i` 与 `W` 变成同宽的全角字符、代码缩进全乱。
  /// 因此这里用**具体字体名**，并给出跨平台回落链。
  static const String mono = 'Consolas';

  /// 等宽字体回落链（配合 [mono] 使用）。
  static const List<String> monoFallback = <String>[
    'Cascadia Mono', // Windows Terminal 自带，较新系统上有
    'DejaVu Sans Mono', // Linux
    'Liberation Mono', // Linux
    'Menlo', // macOS
    'Monaco', // macOS
    'Courier New', // 兜底（Windows / macOS 都有）
    'monospace',
  ];

  /// 给一个 [TextStyle] 套上正文字体（保留其余属性）。
  static TextStyle bodyStyle(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontFamily: body, fontFamilyFallback: fallback);

  /// 给一个 [TextStyle] 套上等宽字体（保留其余属性）。
  static TextStyle monoStyle(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(fontFamily: mono, fontFamilyFallback: monoFallback);

  /// 把整棵 [ThemeData] 的文字体系换成黑体。
  ///
  /// 只改字体相关字段，其余（颜色、字号层级）保持 Flutter 默认，避免"改字体顺带改了
  /// 一堆视觉细节"。`Typography` 的 black / white 两套都要给，否则深色模式下会用回默认字体。
  static ThemeData apply(ThemeData theme) {
    TextStyle? withBody(TextStyle? s) => s == null ? null : bodyStyle(s);

    TextStyle v(TextStyle? s) => bodyStyle(s);
    TextStyle? n(TextStyle? s) => s == null ? null : withBody(s);

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
      // 两者皆给，确保浅色/深色都不会回落到默认字体
      typography: Typography.material2021(
        platform: theme.platform,
        black: textTheme,
        white: textTheme,
      ),
      // 显式列出，避免某些组件（如输入框、按钮）走各自默认字体
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
