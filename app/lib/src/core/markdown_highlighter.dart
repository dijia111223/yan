import 'package:flutter/material.dart';

import 'markdown_theme.dart';

/// Markdown 源码高亮器。
///
/// v1 的关键取舍：不用 WebView、不引第三方高亮插件（`flutter_highlight`
/// 等已停更且不兼容 Dart 3.13），而是自己做一个行级 + 行内两级词法扫描。
/// 这样零依赖、可单测，也能把 frontmatter 当成一等公民来着色。
class MarkdownHighlighter {
  const MarkdownHighlighter(this.theme);

  final MarkdownTheme theme;

  /// 超过这个行数就放弃高亮（直接返回纯文本），保证大文件输入不卡。
  static const int maxHighlightedLines = 8000;

  /// 把 [source] 变成带样式的 [TextSpan]。
  ///
  /// 永不抛异常：任何异常都退化为纯文本，编辑体验优先。
  TextSpan highlight(String source, {int? start, int? end}) {
    final effectiveStart = start ?? 0;
    final effectiveEnd = end ?? source.length;
    if (source.isEmpty || effectiveEnd <= effectiveStart) {
      return TextSpan(text: '', style: theme.body);
    }
    try {
      return _highlightRange(source, effectiveStart, effectiveEnd);
    } catch (_) {
      return TextSpan(text: source.substring(effectiveStart, effectiveEnd), style: theme.body);
    }
  }

  TextSpan _highlightRange(String source, int start, int end) {
    // 行首偏移表：把行号映射回源码下标。
    //
    // 注意末尾换行：`"a\n"` 的行首表必须是 [0, 2]。若写成 `i + 1 < end`，
    // 末尾换行会被漏掉，整段内容就被当成"一行"，行级语法（标题/列表/表格）
    // 全部失效——这是一个非常隐蔽的 off-by-one。
    final lineStarts = <int>[start];
    for (var i = start; i < end; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        lineStarts.add(i + 1);
      }
    }
    if (lineStarts.length > maxHighlightedLines) {
      return TextSpan(text: source.substring(start, end), style: theme.body);
    }

    // 第一遍：行级扫描，标记出 frontmatter 与围栏代码块
    final states = <_LineState>[];
    var inFrontmatter = false;
    var fenceChar = '';
    var fenceLength = 0;

    for (var i = 0; i < lineStarts.length; i++) {
      final lineStart = lineStarts[i];
      // lineEnd 指向换行符本身（不含），行级正则因此总能拿到干净的行尾
      final lineEnd = i + 1 < lineStarts.length ? lineStarts[i + 1] - 1 : end;
      // 换行单独补一个 span，保证拼接后与源码逐字符一致
      final hasNewline = lineEnd < end && source.codeUnitAt(lineEnd) == 0x0A;
      final line = source.substring(lineStart, lineEnd);

      if (i == 0 && line.trimRight() == '---') {
        inFrontmatter = true;
        states.add(
          _LineState(
            kind: _LineKind.frontmatterFence,
            lineStart: lineStart,
            lineEnd: lineEnd,
            hasNewline: hasNewline,
          ),
        );
        continue;
      }
      if (inFrontmatter) {
        final trimmed = line.trimRight();
        if (trimmed == '---' || trimmed == '...') {
          inFrontmatter = false;
          states.add(
            _LineState(
              kind: _LineKind.frontmatterFence,
              lineStart: lineStart,
              lineEnd: lineEnd,
              hasNewline: hasNewline,
            ),
          );
          continue;
        }
        states.add(
          _LineState(
            kind: _LineKind.frontmatter,
            lineStart: lineStart,
            lineEnd: lineEnd,
            hasNewline: hasNewline,
          ),
        );
        continue;
      }

      if (fenceChar.isNotEmpty) {
        final trimmed = line.trimLeft();
        final isClosing = _isFence(trimmed, fenceChar, fenceLength);
        states.add(
          _LineState(
            kind: isClosing ? _LineKind.codeFence : _LineKind.codeBlock,
            lineStart: lineStart,
            lineEnd: lineEnd,
            hasNewline: hasNewline,
          ),
        );
        if (isClosing) {
          fenceChar = '';
          fenceLength = 0;
        }
        continue;
      }

      final opening = _openingFence(line);
      if (opening != null) {
        fenceChar = opening.$1;
        fenceLength = opening.$2;
        states.add(
          _LineState(
            kind: _LineKind.codeFence,
            lineStart: lineStart,
            lineEnd: lineEnd,
            hasNewline: hasNewline,
          ),
        );
        continue;
      }

      states.add(
        _LineState(
          kind: _LineKind.normal,
          lineStart: lineStart,
          lineEnd: lineEnd,
          hasNewline: hasNewline,
        ),
      );
    }

    // 第二遍：按行产出 span
    final spans = <TextSpan>[];
    for (final state in states) {
      spans.addAll(_lineSpans(source, state));
    }
    return TextSpan(style: theme.body, children: spans);
  }

  /// 返回 (围栏字符, 长度)，非围栏行返回 null。
  static (String, int)? _openingFence(String line) {
    var i = 0;
    while (i < line.length && i < 4 && line[i] == ' ') {
      i++;
    }
    if (i >= line.length) return null;
    final ch = line[i];
    if (ch != '`' && ch != '~') return null;
    var length = 0;
    while (i + length < line.length && line[i + length] == ch) {
      length++;
    }
    if (length < 3) return null;
    return (ch, length);
  }

  static bool _isFence(String trimmed, String char, int length) {
    if (trimmed.isEmpty || trimmed[0] != char) return false;
    var count = 0;
    while (count < trimmed.length && trimmed[count] == char) {
      count++;
    }
    if (count < length) return false;
    return trimmed.substring(count).trim().isEmpty;
  }

  List<TextSpan> _lineSpans(String source, _LineState state) {
    final line = source.substring(state.lineStart, state.lineEnd);

    List<TextSpan> spans;
    switch (state.kind) {
      case _LineKind.frontmatterFence:
        spans = <TextSpan>[TextSpan(text: line, style: theme.frontmatterFence)];
      case _LineKind.frontmatter:
        spans = _frontmatterSpans(line);
      case _LineKind.codeFence:
        spans = <TextSpan>[TextSpan(text: line, style: theme.codeFence)];
      case _LineKind.codeBlock:
        spans = <TextSpan>[TextSpan(text: line, style: theme.codeBlock)];
      case _LineKind.normal:
        spans = _normalLineSpans(line);
    }

    if (state.hasNewline) {
      spans = <TextSpan>[...spans, const TextSpan(text: '\n')];
    }
    return spans;
  }

  List<TextSpan> _frontmatterSpans(String line) {
    final comment = line.indexOf('#');
    final content = comment >= 0 ? line.substring(0, comment) : line;
    final spans = <TextSpan>[];
    final colon = content.indexOf(':');

    if (colon > 0) {
      // `  - key: value` 这种列表项也要正确着色
      final leading = RegExp(r'^\s*-\s*').firstMatch(content);
      if (leading != null) {
        spans.add(TextSpan(text: leading.group(0), style: theme.frontmatterFence));
      }
      final keyStart = leading?.end ?? 0;
      spans.add(
        TextSpan(text: content.substring(keyStart, colon), style: theme.frontmatterKey),
      );
      spans.add(TextSpan(text: ':', style: theme.frontmatterFence));
      if (colon + 1 < content.length) {
        spans.add(TextSpan(text: content.substring(colon + 1), style: theme.frontmatterValue));
      }
    } else if (content.isNotEmpty) {
      spans.add(TextSpan(text: content, style: theme.frontmatterValue));
    }

    if (comment >= 0) {
      spans.add(TextSpan(text: line.substring(comment), style: theme.frontmatterComment));
    }
    return spans;
  }

  /// 行级元素（标题 / 引用 / 列表 / 分隔线 / 表格）与行内元素。
  List<TextSpan> _normalLineSpans(String line) {
    if (line.isEmpty) return <TextSpan>[TextSpan(text: '', style: theme.body)];

    // 分隔线
    if (RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
      return <TextSpan>[TextSpan(text: line, style: theme.rule)];
    }

    final heading = RegExp(r'^(\s{0,3})(#{1,6})(\s+)(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(2)!.length;
      final textStart = heading.end - heading.group(4)!.length;
      // 闭合式标题 `## 标题 ##`：尾部的 # 只作为标记着色，不参与行内解析
      final trailing = RegExp(r'(\s+)(#+)\s*$').firstMatch(line);
      final hasTrailingFence = trailing != null && trailing.start >= textStart;
      final contentEnd = hasTrailingFence ? trailing.start : line.length;

      final spans = <TextSpan>[
        TextSpan(text: heading.group(1), style: theme.body),
        TextSpan(text: heading.group(2), style: theme.punctuation),
        TextSpan(text: heading.group(3), style: theme.body),
      ];
      if (contentEnd > textStart) {
        spans.addAll(
          _inlineSpans(
            line.substring(textStart, contentEnd),
            base: theme.heading(level),
            offset: textStart,
            line: line,
          ),
        );
      }
      if (hasTrailingFence) {
        spans.add(TextSpan(text: line.substring(trailing.start), style: theme.punctuation));
      }
      return spans;
    }

    // 引用
    final quote = RegExp(r'^(\s{0,3})(>+\s?)(.*)$').firstMatch(line);
    if (quote != null) {
      final marker = quote.group(2)!;
      final rest = quote.group(3)!;
      final restStart = quote.end - rest.length;
      final spans = <TextSpan>[
        TextSpan(text: quote.group(1), style: theme.body),
        TextSpan(text: marker, style: theme.listMarker),
      ];
      spans.addAll(
        _inlineSpans(rest, base: theme.quote, offset: restStart, line: line),
      );
      return spans;
    }

    // 列表项（无序 / 有序 / 任务列表）
    final list = RegExp(r'^(\s*)([-*+]|\d+[.)])(\s+)(.*)$').firstMatch(line);
    if (list != null) {
      final rest = list.group(4)!;
      final restStart = list.end - rest.length;
      final spans = <TextSpan>[
        TextSpan(text: list.group(1), style: theme.body),
        TextSpan(text: list.group(2), style: theme.listMarker),
        TextSpan(text: list.group(3), style: theme.body),
      ];
      // 任务列表复选框
      final task = RegExp(r'^(\[[ xX]\])(\s*)(.*)$').firstMatch(rest);
      if (task != null) {
        spans.add(TextSpan(text: task.group(1), style: theme.listMarker));
        spans.add(TextSpan(text: task.group(2), style: theme.body));
        final text = task.group(3)!;
        final textStart = restStart + task.end - text.length;
        spans.addAll(_inlineSpans(text, base: theme.body, offset: textStart, line: line));
        return spans;
      }
      spans.addAll(_inlineSpans(rest, base: theme.body, offset: restStart, line: line));
      return spans;
    }

    // 表格行：以 `|` 开头的整行按单元格着色
    if (line.trimLeft().startsWith('|') && line.contains('|', line.indexOf('|') + 1)) {
      return _tableSpans(line);
    }

    return _inlineSpans(line, base: theme.body, offset: 0, line: line);
  }

  List<TextSpan> _tableSpans(String line) {
    final spans = <TextSpan>[];
    final isDelimiter = RegExp(r'^\s*\|?[\s:|-]+\|?\s*$').hasMatch(line) && line.contains('-');
    final style = isDelimiter ? theme.tableDelimiter : theme.body;
    var index = 0;
    while (index < line.length) {
      final pipe = line.indexOf('|', index);
      if (pipe < 0) {
        spans.addAll(_inlineSpans(line.substring(index), base: style, offset: index, line: line));
        break;
      }
      if (pipe > index) {
        spans.addAll(_inlineSpans(line.substring(index, pipe), base: style, offset: index, line: line));
      }
      spans.add(TextSpan(text: '|', style: theme.tableDelimiter));
      index = pipe + 1;
    }
    return spans;
  }

  /// 行内扫描：代码 > 图片 > 链接 > 粗斜体 > 强调 > 删除线 > 数学。
  ///
  /// [offset] 是 [text] 在整行中的起始下标，仅用于文档说明（本实现按片段局部扫描）。
  List<TextSpan> _inlineSpans(
    String text, {
    required TextStyle base,
    required int offset,
    required String line,
  }) {
    if (text.isEmpty) return <TextSpan>[TextSpan(text: '', style: base)];

    final pattern = RegExp(
      r'(`+)([\s\S]*?)\1' // 1,2 行内代码
      r'|!\[([^\]]*)\]\(([^)]*)\)' // 3,4 图片
      r'|\[([^\]]*)\]\(([^)]*)\)' // 5,6 链接
      r'|\*\*\*([^*\n]+)\*\*\*' // 7 粗斜体
      r'|\*\*([^*\n]+)\*\*' // 8 粗体
      r'|__([^_\n]+)__' // 9 粗体（下划线式）
      r'|\*([^*\n]+)\*' // 10 斜体
      r'|~~([^~\n]+)~~' // 11 删除线
      r'|\$([^$\n]+)\$', // 12 行内数学
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        final plain = text.substring(cursor, match.start);
        final link = _autolink(plain, base);
        if (link != null) {
          spans.add(link);
        } else {
          spans.add(TextSpan(text: plain, style: base));
        }
      }
      spans.add(_styledMatch(match, base, text));
      cursor = match.end;
    }
    if (cursor < text.length) {
      final plain = text.substring(cursor);
      final link = _autolink(plain, base);
      if (link != null) {
        spans.add(link);
      } else {
        spans.add(TextSpan(text: plain, style: base));
      }
    }
    return spans;
  }

  TextSpan _styledMatch(RegExpMatch match, TextStyle base, String text) {
    // 行内代码
    if (match.group(1) != null) {
      final ticks = match.group(1)!;
      final code = match.group(2) ?? '';
      return TextSpan(
        children: <TextSpan>[
          TextSpan(text: ticks, style: theme.punctuation),
          TextSpan(
            text: code,
            style: theme.inlineCode.copyWith(backgroundColor: theme.inlineCodeBackground),
          ),
          TextSpan(text: ticks, style: theme.punctuation),
        ],
      );
    }

    // 图片
    if (match.group(3) != null) {
      return TextSpan(
        children: <TextSpan>[
          const TextSpan(text: '!['),
          TextSpan(text: match.group(3), style: theme.image),
          const TextSpan(text: ']('),
          TextSpan(text: match.group(4), style: theme.linkUrl),
          const TextSpan(text: ')'),
        ],
        style: theme.punctuation,
      );
    }

    // 链接
    if (match.group(5) != null) {
      return TextSpan(
        children: <TextSpan>[
          const TextSpan(text: '['),
          TextSpan(text: match.group(5), style: theme.link),
          const TextSpan(text: ']('),
          TextSpan(text: match.group(6), style: theme.linkUrl),
          const TextSpan(text: ')'),
        ],
        style: theme.punctuation,
      );
    }

    // 粗体 / 斜体 / 删除线 / 行内数学：保留标记符号但弱化
    final (marker, content, style) = switch (match) {
      _ when match.group(7) != null => ('***', match.group(7)!, base.merge(theme.emphasis).merge(theme.italic)),
      _ when match.group(8) != null => ('**', match.group(8)!, base.merge(theme.emphasis)),
      _ when match.group(9) != null => ('__', match.group(9)!, base.merge(theme.emphasis)),
      _ when match.group(10) != null => ('*', match.group(10)!, base.merge(theme.italic)),
      _ when match.group(11) != null => ('~~', match.group(11)!, base.merge(theme.strikethrough)),
      _ => (r'$', match.group(12)!, base.merge(theme.math)),
    };

    if (marker == r'$') {
      return TextSpan(
        children: <TextSpan>[
          TextSpan(text: marker, style: theme.punctuation),
          TextSpan(text: content, style: style),
          TextSpan(text: marker, style: theme.punctuation),
        ],
      );
    }

    return TextSpan(
      children: <TextSpan>[
        TextSpan(text: marker, style: theme.punctuation),
        TextSpan(text: content, style: style),
        TextSpan(text: marker, style: theme.punctuation),
      ],
    );
  }

  static final RegExp _bareUrl = RegExp(r'^(https?://\S+)$');

  /// 裸链接（GFM 自动链接）单独着色。
  TextSpan? _autolink(String text, TextStyle base) {
    final match = _bareUrl.firstMatch(text.trim());
    if (match == null) return null;
    return TextSpan(text: text, style: base.merge(theme.link));
  }
}

enum _LineKind { normal, frontmatter, frontmatterFence, codeBlock, codeFence }

class _LineState {
  const _LineState({
    required this.kind,
    required this.lineStart,
    required this.lineEnd,
    required this.hasNewline,
  });

  final _LineKind kind;
  final int lineStart;

  /// 行尾下标（不含换行符）。
  final int lineEnd;

  /// 该行是否以换行符结束——换行要单独补一个 span，不能丢。
  final bool hasNewline;
}
