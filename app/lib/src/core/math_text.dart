import 'latex_to_unicode.dart';

/// 从 Markdown 源码中抽出的**行间**公式（`$$...$$`）。
///
/// 行内公式不走这里——它会被 [MathExtractor] 直接转成 Unicode 文本随文排版，
/// 原因见 `latex_to_unicode.dart` 的说明。
class MathFragment {
  const MathFragment({required this.tex});

  /// LaTeX 源码（不含分隔符）。
  final String tex;

  @override
  String toString() => 'display: $tex';
}

/// 公式提取结果。
class MathExtraction {
  const MathExtraction({
    required this.markdown,
    required this.fragments,
  });

  /// 处理后的 Markdown：
  /// 行内公式已变成 Unicode 文本，行间公式已变成 `> <占位符>` 块引用。
  final String markdown;

  /// 占位符 → 行间公式。
  final Map<String, MathFragment> fragments;

  static const MathExtraction empty =
      MathExtraction(markdown: '', fragments: <String, MathFragment>{});
}

/// LaTeX 公式预处理。
///
/// 分两条路：
///
/// * **行内** `$...$`：转成 Unicode 文本（见 [latexToUnicode]），随正文排版。
///   无法转换时**保留原始 LaTeX**，绝不输出错误的公式。
/// * **行间** `$$...$$`：替换成 `> <占位符>` 形式的块引用，由预览层用
///   `flutter_math_fork` 完整排版。之所以借用块引用，是因为它是
///   `flutter_markdown` 处理得最干净的块级元素，替换它不会破坏库内部的
///   inline 记账（直接替换 `<p>` 会触发 `assert(_inlines.isEmpty)`）。
///
/// 两种写法 `\(...\)` / `\[...\]` 同样支持。代码块与行内代码里的 `$` 一律不动。
class MathExtractor {
  const MathExtractor._();

  /// 占位符前缀/后缀，用 NUL 包裹以保证不会与正文冲突。
  static const String _marker = '\u0000YANMATH';
  static const String _markerEnd = '\u0000';

  static String placeholder(int index) => '$_marker$index$_markerEnd';

  /// 判断一段文本是否是（纯）占位符。
  static int? placeholderIndex(String text) {
    final trimmed = text.trim();
    if (trimmed.length < _marker.length + _markerEnd.length + 1) return null;
    if (!trimmed.startsWith(_marker) || !trimmed.endsWith(_markerEnd)) return null;
    final digits = trimmed.substring(_marker.length, trimmed.length - _markerEnd.length);
    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;
    return int.tryParse(digits);
  }

  /// 在一段文本中查找所有占位符，返回 (起始下标, 结束下标, 序号)。
  static List<(int, int, int)> findPlaceholders(String text) {
    final results = <(int, int, int)>[];
    var cursor = 0;
    while (cursor < text.length) {
      final start = text.indexOf(_marker, cursor);
      if (start < 0) break;
      final end = text.indexOf(_markerEnd, start + _marker.length);
      if (end < 0) break;
      final digits = text.substring(start + _marker.length, end);
      if (RegExp(r'^\d+$').hasMatch(digits)) {
        results.add((start, end + _markerEnd.length, int.parse(digits)));
      }
      cursor = end + _markerEnd.length;
    }
    return results;
  }

  /// 处理 [source] 中的公式。
  static MathExtraction extract(String source) {
    if (source.isEmpty) return MathExtraction.empty;
    if (!source.contains(r'$') && !source.contains(r'\(') && !source.contains(r'\[')) {
      return MathExtraction(markdown: source, fragments: const <String, MathFragment>{});
    }

    final fragments = <String, MathFragment>{};
    final out = StringBuffer();

    var i = 0;
    var inFence = false;
    var fenceChar = '';
    var fenceLength = 0;
    var atLineStart = true;

    while (i < source.length) {
      // 行首：检查围栏代码块边界
      if (atLineStart) {
        final lineEnd = _lineEnd(source, i);
        final line = source.substring(i, lineEnd);
        if (inFence) {
          if (_isFence(line.trimLeft(), fenceChar, fenceLength)) {
            inFence = false;
            fenceChar = '';
            fenceLength = 0;
          }
          out.write(line);
          atLineStart = lineEnd < source.length;
          i = lineEnd < source.length ? lineEnd + 1 : lineEnd;
          if (lineEnd < source.length) out.write('\n');
          continue;
        }
        final opening = _openingFence(line);
        if (opening != null) {
          inFence = true;
          fenceChar = opening.$1;
          fenceLength = opening.$2;
          out.write(line);
          if (lineEnd < source.length) {
            out.write('\n');
            i = lineEnd + 1;
            atLineStart = true;
          } else {
            i = lineEnd;
            atLineStart = false;
          }
          continue;
        }
      }

      final ch = source[i];

      // 围栏代码块内部：一个字符都不动（代码里的 $ 和反斜杠都是字面量）
      if (inFence) {
        out.write(ch);
        atLineStart = ch == '\n';
        i++;
        continue;
      }

      // 行内代码：整段原样保留
      if (ch == '`') {
        var ticks = 0;
        while (i + ticks < source.length && source[i + ticks] == '`') {
          ticks++;
        }
        final closer = source.indexOf('`' * ticks, i + ticks);
        if (closer < 0) {
          out.write(source.substring(i, i + ticks));
          i += ticks;
        } else {
          out.write(source.substring(i, closer + ticks));
          i = closer + ticks;
        }
        atLineStart = false;
        continue;
      }

      // 转义序列：\$ 是字面量美元号；\( \) 与 \[ \] 是公式
      if (ch == r'\' && i + 1 < source.length) {
        final next = source[i + 1];
        if (next == r'$') {
          out.write(r'$');
          i += 2;
          atLineStart = false;
          continue;
        }
        if (next == '(' || next == '[') {
          final display = next == '[';
          final closing = display ? r'\]' : r'\)';
          final end = source.indexOf(closing, i + 2);
          if (end > 0) {
            final tex = source.substring(i + 2, end).trim();
            if (tex.isNotEmpty) {
              _emitMath(tex, display: display, out: out, fragments: fragments);
              i = end + 2;
              atLineStart = false;
              continue;
            }
          }
        }
        out.write(source.substring(i, i + 2));
        i += 2;
        atLineStart = false;
        continue;
      }

      if (ch == r'$') {
        final isDisplay = i + 1 < source.length && source[i + 1] == r'$';
        final delimLength = isDisplay ? 2 : 1;
        final searchFrom = i + delimLength;
        final end = _findClosingDollar(source, searchFrom, isDisplay);
        if (end > 0) {
          final tex = source.substring(searchFrom, end).trim();
          if (tex.isNotEmpty && !tex.contains('\n\n')) {
            _emitMath(tex, display: isDisplay, out: out, fragments: fragments);
            i = end + delimLength;
            atLineStart = false;
            continue;
          }
        }
        out.write(source.substring(i, i + delimLength));
        i += delimLength;
        atLineStart = false;
        continue;
      }

      out.write(ch);
      atLineStart = ch == '\n';
      i++;
    }

    return MathExtraction(markdown: out.toString(), fragments: fragments);
  }

  /// 写出一个公式：行内转 Unicode，行间转块引用占位符。
  static void _emitMath(
    String tex, {
    required bool display,
    required StringBuffer out,
    required Map<String, MathFragment> fragments,
  }) {
    if (!display) {
      final unicode = latexToUnicode(tex);
      // 转换不了就原样保留 LaTeX —— 宁可看到源码，也不要看到错的公式
      out.write(unicode ?? '\$$tex\$');
      return;
    }

    final key = placeholder(fragments.length);
    fragments[key] = MathFragment(tex: tex);
    // 独立成段的块引用，预览层按块渲染成完整公式
    out.write('\n> $key\n');
  }

  /// 找配对的 `$` / `$$`。返回结束分隔符的起始下标，找不到返回 -1。
  static int _findClosingDollar(String source, int from, bool display) {
    var i = from;
    while (i < source.length) {
      final ch = source[i];
      if (ch == r'\') {
        i += 2;
        continue;
      }
      if (ch == '\n' && display) {
        // 行间公式允许换行，但不能空行分段
        if (i + 1 < source.length && source[i + 1] == '\n') return -1;
        i++;
        continue;
      }
      if (ch == r'$') {
        if (!display) return i;
        if (i + 1 < source.length && source[i + 1] == r'$') return i;
        i++;
        continue;
      }
      i++;
    }
    return -1;
  }

  static int _lineEnd(String source, int from) {
    final index = source.indexOf('\n', from);
    return index < 0 ? source.length : index;
  }

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
}
