import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../core/latex_to_unicode.dart';
import '../core/markdown_theme.dart';
import '../core/math_text.dart';

/// Markdown 预览：GFM（表格 / 任务列表 / 删除线 / 自动链接）+ LaTeX 公式。
///
/// 设计要点（踩过坑，别改回去）
/// --------------------------
/// **只替换 `pre` / `code` / `blockquote` 这三类块级元素，绝不替换 `p` 或标题。**
///
/// `flutter_markdown` 的 `MarkdownBuilder` 用一个 `_inlines` 栈来拼行内片段，
/// 并在 `build()` 结尾断言 `_inlines.isEmpty`。当自定义 builder 替换掉 `<p>`
/// 这类**内含行内子节点**的块时，它自己 pop 出来的 inline 不会被正常出栈，
/// 断言随即失败——表现是**一打开有正文的笔记就崩**。
///
/// 因此：
/// * 行内公式在 `MathExtractor` 阶段就转成 Unicode 文本，交给库正常排版；
/// * 行间公式被预处理成 `> <占位符>` 块引用，这里用 `blockquote` builder
///   整体替换成公式组件（块引用没有行内子节点，替换是安全的）。
class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({
    super.key,
    required this.source,
    required this.fragments,
    required this.mdTheme,
    this.onTapLink,
    this.padding = const EdgeInsets.fromLTRB(28, 20, 28, 140),
  });

  /// 已由 [MathExtractor.extract] 处理过的 Markdown。
  final String source;

  /// 行间公式表。
  final Map<String, MathFragment> fragments;

  final MarkdownTheme mdTheme;
  final void Function(String href)? onTapLink;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: source,
      selectable: true,
      styleSheet: _styleSheet(context, mdTheme),
      extensionSet: md.ExtensionSet.gitHubWeb,
      onTapLink: (text, href, title) {
        if (href != null && onTapLink != null) onTapLink!(href);
      },
      builders: <String, MarkdownElementBuilder>{
        'pre': _CodeCardBuilder(mdTheme),
        'code': _InlineCodeWithLanguageBuilder(mdTheme),
        'blockquote': _DisplayMathBuilder(mdTheme, fragments),
      },
    );
  }

  static MarkdownStyleSheet _styleSheet(BuildContext context, MarkdownTheme t) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      p: t.body,
      h1: t.heading(1),
      h2: t.heading(2),
      h3: t.heading(3),
      h4: t.heading(4),
      h5: t.heading(5),
      h6: t.heading(6),
      h1Padding: const EdgeInsets.only(top: 24, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 4),
      pPadding: const EdgeInsets.only(bottom: 10),
      a: t.link,
      em: t.italic,
      strong: t.emphasis,
      del: t.strikethrough,
      code: t.inlineCode,
      codeblockDecoration: BoxDecoration(
        color: t.codeBlockBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: EdgeInsets.zero,
      blockquote: t.quote,
      blockquoteDecoration: BoxDecoration(
        color: t.codeBlockBackground.withValues(alpha: 0.7),
        border: Border(left: BorderSide(color: t.listMarker.color!, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      listBullet: t.listMarker,
      listIndent: 22,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.rule.color!, width: 1)),
      ),
      tableBorder: TableBorder.all(
        color: t.punctuation.color!.withValues(alpha: 0.45),
        width: 1,
      ),
      tableHead: t.body.copyWith(fontWeight: FontWeight.w700),
      tableBody: t.body,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      tableColumnWidth: const IntrinsicColumnWidth(),
    );
  }
}

/// 行间公式：预处理阶段生成的 `> <占位符>` 块引用在这里被整体替换成公式组件。
class _DisplayMathBuilder extends MarkdownElementBuilder {
  _DisplayMathBuilder(this.theme, this.fragments);

  final MarkdownTheme theme;
  final Map<String, MathFragment> fragments;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final index = MathExtractor.placeholderIndex(element.textContent);
    // 不是公式块引用：返回 null，交回库按普通引用渲染
    if (index == null) return null;
    final fragment = fragments[MathExtractor.placeholder(index)];
    if (fragment == null) return null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _Formula(tex: fragment.tex, theme: theme),
    );
  }
}

/// 块级代码卡片：语言标签 + 自研轻量高亮。
class _CodeCardBuilder extends MarkdownElementBuilder {
  _CodeCardBuilder(this.theme);

  final MarkdownTheme theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // `<pre>` 里通常是一个带 language-xxx 的 <code>
    String language = '';
    var code = element.textContent;
    final children = element.children;
    if (children != null && children.isNotEmpty && children.first is md.Element) {
      final inner = children.first as md.Element;
      language = (inner.attributes['class'] ?? '').replaceFirst('language-', '');
      code = inner.textContent;
    }
    // 末尾换行会多撑出一行空白
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);

    return _CodeCard(code: code, language: language, theme: theme);
  }
}

/// 带语言标记的 `<code>` 仍按卡片渲染；真正的行内代码返回 null 交回库处理。
class _InlineCodeWithLanguageBuilder extends MarkdownElementBuilder {
  _InlineCodeWithLanguageBuilder(this.theme);

  final MarkdownTheme theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final language = (element.attributes['class'] ?? '').replaceFirst('language-', '');
    if (language.isEmpty) return null;

    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return _CodeCard(code: code, language: language, theme: theme);
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.language, required this.theme});

  final String code;
  final String language;
  final MarkdownTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.codeBlockBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.punctuation.color!.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(
                language,
                style: theme.codeFence.copyWith(fontSize: 11.5, letterSpacing: 0.4),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, language.isEmpty ? 14 : 6, 14, 14),
            child: Text.rich(
              CodeHighlighter(theme, language).highlight(code),
              style: theme.codeBlock,
            ),
          ),
        ],
      ),
    );
  }
}

/// 轻量代码高亮（零依赖）。
///
/// 不做完整词法分析——只覆盖注释 / 字符串 / 数字 / 关键字，
/// 对"看代码时能分清结构"这个目标足够，也符合宪章"小而锋利"的原则。
class CodeHighlighter {
  const CodeHighlighter(this.theme, this.language);

  final MarkdownTheme theme;
  final String language;

  static const Map<String, Set<String>> keywords = <String, Set<String>>{
    'dart': <String>{
      'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class', 'const',
      'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export',
      'extends', 'extension', 'external', 'factory', 'false', 'final', 'finally', 'for', 'get',
      'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library', 'mixin',
      'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'set', 'show',
      'static', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var',
      'void', 'while', 'with', 'yield',
    },
    'python': <String>{
      'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif',
      'else', 'except', 'false', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
      'lambda', 'none', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'true', 'try',
      'while', 'with', 'yield',
    },
    'javascript': <String>{
      'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'false', 'finally', 'for',
      'function', 'if', 'import', 'in', 'instanceof', 'let', 'new', 'null', 'return', 'super',
      'switch', 'this', 'throw', 'true', 'try', 'typeof', 'undefined', 'var', 'void', 'while',
      'yield',
    },
    'typescript': <String>{
      'abstract', 'any', 'as', 'async', 'await', 'boolean', 'break', 'case', 'catch', 'class',
      'const', 'continue', 'default', 'delete', 'do', 'else', 'enum', 'export', 'extends',
      'false', 'finally', 'for', 'from', 'function', 'if', 'implements', 'import', 'in',
      'interface', 'let', 'new', 'null', 'number', 'private', 'protected', 'public', 'readonly',
      'return', 'static', 'string', 'super', 'switch', 'this', 'throw', 'true', 'try', 'type',
      'undefined', 'var', 'void', 'while',
    },
    'java': <String>{
      'abstract', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const',
      'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'false', 'final',
      'finally', 'float', 'for', 'if', 'implements', 'import', 'instanceof', 'int', 'interface',
      'long', 'new', 'null', 'package', 'private', 'protected', 'public', 'return', 'short',
      'static', 'super', 'switch', 'this', 'throw', 'throws', 'true', 'try', 'void', 'while',
    },
    'c': <String>{
      'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double', 'else',
      'enum', 'extern', 'float', 'for', 'goto', 'if', 'int', 'long', 'register', 'return',
      'short', 'signed', 'sizeof', 'static', 'struct', 'switch', 'typedef', 'union', 'unsigned',
      'void', 'volatile', 'while',
    },
    'cpp': <String>{
      'auto', 'bool', 'break', 'case', 'catch', 'char', 'class', 'const', 'constexpr',
      'continue', 'default', 'delete', 'do', 'double', 'else', 'enum', 'explicit', 'extern',
      'false', 'float', 'for', 'friend', 'if', 'inline', 'int', 'long', 'namespace', 'new',
      'nullptr', 'operator', 'private', 'protected', 'public', 'return', 'short', 'sizeof',
      'static', 'struct', 'switch', 'template', 'this', 'throw', 'true', 'try', 'typename',
      'using', 'virtual', 'void', 'while',
    },
    'rust': <String>{
      'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn', 'else', 'enum',
      'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop', 'match', 'mod', 'move',
      'mut', 'pub', 'ref', 'return', 'self', 'static', 'struct', 'super', 'trait', 'true',
      'type', 'unsafe', 'use', 'where', 'while',
    },
    'go': <String>{
      'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough',
      'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range',
      'return', 'select', 'struct', 'switch', 'type', 'var',
    },
    'bash': <String>{
      'case', 'do', 'done', 'elif', 'else', 'esac', 'fi', 'for', 'function', 'if', 'in', 'local',
      'return', 'then', 'until', 'while', 'export', 'source',
    },
    'sql': <String>{
      'alter', 'and', 'as', 'by', 'create', 'delete', 'drop', 'from', 'group', 'having',
      'insert', 'into', 'join', 'left', 'limit', 'not', 'null', 'on', 'or', 'order', 'select',
      'set', 'table', 'update', 'values', 'where',
    },
  };

  static const Map<String, String> aliases = <String, String>{
    'py': 'python',
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'c++': 'cpp',
    'cc': 'cpp',
    'h': 'c',
    'hpp': 'cpp',
    'rs': 'rust',
    'golang': 'go',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'console': 'bash',
  };

  /// 归一化后的语言名（无法识别时返回空串）。
  String get normalizedLanguage {
    final lang = language.toLowerCase().trim();
    if (keywords.containsKey(lang)) return lang;
    return aliases[lang] ?? '';
  }

  TextSpan highlight(String code) {
    final lang = normalizedLanguage;
    if (lang.isEmpty) return TextSpan(text: code, style: theme.codeBlock);

    final words = keywords[lang]!;
    final keywordColor = theme.link.color!;
    final stringColor = theme.image.color!;
    final commentColor = theme.punctuation.color!;
    final numberColor = theme.listMarker.color!;

    final pattern = RegExp(
      r'(//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/)' // 1 注释
      r'|("(?:[^"\\\n]|\\.)*"|'
      r"'(?:[^'\\\n]|\\.)*')" // 2 字符串
      r'|(\b\d+(?:\.\d+)?(?:[eE][-+]?\d+)?\b)' // 3 数字
      r'|([A-Za-z_][A-Za-z0-9_]*)', // 4 标识符
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(code)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: code.substring(cursor, match.start), style: theme.codeBlock));
      }
      final text = match.group(0)!;
      if (match.group(1) != null) {
        spans.add(TextSpan(text: text, style: theme.codeBlock.copyWith(color: commentColor)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: text, style: theme.codeBlock.copyWith(color: stringColor)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: text, style: theme.codeBlock.copyWith(color: numberColor)));
      } else if (words.contains(text.toLowerCase())) {
        spans.add(
          TextSpan(
            text: text,
            style: theme.codeBlock.copyWith(color: keywordColor, fontWeight: FontWeight.w600),
          ),
        );
      } else {
        spans.add(TextSpan(text: text, style: theme.codeBlock));
      }
      cursor = match.end;
    }
    if (cursor < code.length) {
      spans.add(TextSpan(text: code.substring(cursor), style: theme.codeBlock));
    }
    return TextSpan(style: theme.codeBlock, children: spans);
  }
}

/// 行间公式组件。渲染失败时优雅退化为可读文本（绝不红屏）。
class _Formula extends StatelessWidget {
  const _Formula({required this.tex, required this.theme});

  final String tex;
  final MarkdownTheme theme;

  @override
  Widget build(BuildContext context) {
    // 兜底：渲染不了时把公式**转成 Unicode 可读文本**，
    // 而不是原样吐 LaTeX 源码——后者对用户几乎没有价值。
    final readable = latexToUnicode(tex) ?? tex;
    final fallback = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.inlineCodeBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(readable, style: theme.math.copyWith(fontSize: 15)),
    );

    return Center(
      child: Math.tex(
        tex,
        mathStyle: MathStyle.display,
        textStyle: theme.body.copyWith(fontSize: 17),
        onErrorFallback: (FlutterMathException error) => fallback,
      ),
    );
  }
}
