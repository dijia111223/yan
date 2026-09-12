import 'package:flutter/material.dart';

/// Markdown 源码高亮的配色与字形。
///
/// 深浅两套预设，与 App 主题同步切换。
@immutable
class MarkdownTheme {
  const MarkdownTheme({
    required this.body,
    required this.punctuation,
    required this.headingColors,
    required this.headingWeights,
    required this.emphasis,
    required this.italic,
    required this.strikethrough,
    required this.inlineCode,
    required this.inlineCodeBackground,
    required this.codeBlock,
    required this.codeBlockBackground,
    required this.codeFence,
    required this.link,
    required this.linkUrl,
    required this.quote,
    required this.listMarker,
    required this.rule,
    required this.image,
    required this.frontmatterKey,
    required this.frontmatterValue,
    required this.frontmatterComment,
    required this.frontmatterFence,
    required this.tableDelimiter,
    required this.math,
  });

  final TextStyle body;

  /// 标记符号：`#`、`-`、`>`、`|` 等
  final TextStyle punctuation;

  /// H1..H6 的文字样式（下标 0 对应 H1）
  final List<TextStyle> headingColors;

  /// H1..H6 的字重
  final List<FontWeight> headingWeights;

  final TextStyle emphasis;
  final TextStyle italic;
  final TextStyle strikethrough;

  final TextStyle inlineCode;
  final Color inlineCodeBackground;
  final TextStyle codeBlock;
  final Color codeBlockBackground;
  final TextStyle codeFence;

  final TextStyle link;
  final TextStyle linkUrl;
  final TextStyle quote;
  final TextStyle listMarker;
  final TextStyle rule;
  final TextStyle image;

  final TextStyle frontmatterKey;
  final TextStyle frontmatterValue;
  final TextStyle frontmatterComment;
  final TextStyle frontmatterFence;

  final TextStyle tableDelimiter;
  final TextStyle math;

  TextStyle heading(int level) {
    final index = (level - 1).clamp(0, 5);
    return headingColors[index].copyWith(fontWeight: headingWeights[index]);
  }

  static const MarkdownTheme light = MarkdownTheme(
    body: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF22252A)),
    punctuation: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF9AA3B2)),
    headingColors: <TextStyle>[
      TextStyle(fontSize: 24, height: 1.5, color: Color(0xFF1A1D23)),
      TextStyle(fontSize: 21, height: 1.5, color: Color(0xFF1F2530)),
      TextStyle(fontSize: 19, height: 1.5, color: Color(0xFF243044)),
      TextStyle(fontSize: 17, height: 1.6, color: Color(0xFF2B3A52)),
      TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF33445F)),
      TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF3C4F6B)),
    ],
    headingWeights: <FontWeight>[
      FontWeight.w700,
      FontWeight.w700,
      FontWeight.w600,
      FontWeight.w600,
      FontWeight.w600,
      FontWeight.w600,
    ],
    emphasis: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF181B20), fontWeight: FontWeight.w700),
    italic: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF2A2F38), fontStyle: FontStyle.italic),
    strikethrough: TextStyle(
      fontSize: 15,
      height: 1.7,
      color: Color(0xFF8A93A0),
      decoration: TextDecoration.lineThrough,
    ),
    inlineCode: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      color: Color(0xFF9C2A6B),
      backgroundColor: Color(0xFFF1F2F6),
    ),
    inlineCodeBackground: Color(0xFFF1F2F6),
    codeBlock: TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.6, color: Color(0xFF2C3138)),
    codeBlockBackground: Color(0xFFF6F7F9),
    codeFence: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6, color: Color(0xFF9AA3B2)),
    link: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF1A6FE0), decoration: TextDecoration.underline),
    linkUrl: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF7A879C)),
    quote: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF5A6472), fontStyle: FontStyle.italic),
    listMarker: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFE0651A), fontWeight: FontWeight.w700),
    rule: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFB9C1CE)),
    image: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF0E8F6E)),
    frontmatterKey: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF1A6FE0), fontWeight: FontWeight.w600),
    frontmatterValue: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF8A5A00)),
    frontmatterComment: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF8A93A0), fontStyle: FontStyle.italic),
    frontmatterFence: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFB9C1CE)),
    tableDelimiter: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF9AA3B2), fontWeight: FontWeight.w700),
    math: TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.7, color: Color(0xFF6A3FB5)),
  );

  static const MarkdownTheme dark = MarkdownTheme(
    body: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFD6DAE2)),
    punctuation: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF6C7686)),
    headingColors: <TextStyle>[
      TextStyle(fontSize: 24, height: 1.5, color: Color(0xFFF2F5FA)),
      TextStyle(fontSize: 21, height: 1.5, color: Color(0xFFE8EDF6)),
      TextStyle(fontSize: 19, height: 1.5, color: Color(0xFFDCE6F7)),
      TextStyle(fontSize: 17, height: 1.6, color: Color(0xFFCFDDF5)),
      TextStyle(fontSize: 16, height: 1.6, color: Color(0xFFC2D3F0)),
      TextStyle(fontSize: 15, height: 1.6, color: Color(0xFFB5C8EA)),
    ],
    headingWeights: <FontWeight>[
      FontWeight.w700,
      FontWeight.w700,
      FontWeight.w600,
      FontWeight.w600,
      FontWeight.w600,
      FontWeight.w600,
    ],
    emphasis: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFF0F3F8), fontWeight: FontWeight.w700),
    italic: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFC9D0DB), fontStyle: FontStyle.italic),
    strikethrough: TextStyle(
      fontSize: 15,
      height: 1.7,
      color: Color(0xFF78818F),
      decoration: TextDecoration.lineThrough,
    ),
    inlineCode: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      color: Color(0xFFF08BC0),
      backgroundColor: Color(0xFF272B33),
    ),
    inlineCodeBackground: Color(0xFF272B33),
    codeBlock: TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.6, color: Color(0xFFC8D1DE)),
    codeBlockBackground: Color(0xFF1E2229),
    codeFence: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.6, color: Color(0xFF6C7686)),
    link: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF6FA8FF), decoration: TextDecoration.underline),
    linkUrl: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF7E8899)),
    quote: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFA5AEBC), fontStyle: FontStyle.italic),
    listMarker: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFFFF9A57), fontWeight: FontWeight.w700),
    rule: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF545E6D)),
    image: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF4ED2A8)),
    frontmatterKey: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF6FA8FF), fontWeight: FontWeight.w600),
    frontmatterValue: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFE3C07B)),
    frontmatterComment: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF78818F), fontStyle: FontStyle.italic),
    frontmatterFence: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF545E6D)),
    tableDelimiter: TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF6C7686), fontWeight: FontWeight.w700),
    math: TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.7, color: Color(0xFFC79BFF)),
  );
}
