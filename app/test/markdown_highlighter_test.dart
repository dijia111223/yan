import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/markdown_highlighter.dart';
import 'package:yan_note/src/core/markdown_theme.dart';
import 'package:yan_note/src/state/editor_controller.dart';

/// 把高亮结果拍平成 (文本, 颜色) 列表，便于断言。
List<(String, Color?)> flatten(TextSpan span, [List<(String, Color?)>? out]) {
  final result = out ?? <(String, Color?)>[];
  if (span.text != null) {
    result.add((span.text!, span.style?.color));
  }
  final children = span.children;
  if (children != null) {
    for (final child in children) {
      if (child is TextSpan) flatten(child, result);
    }
  }
  return result;
}

String fullText(TextSpan span) =>
    flatten(span).map((e) => e.$1).join();

void main() {
  const highlighter = MarkdownHighlighter(MarkdownTheme.light);
  final theme = MarkdownTheme.light;

  group('高亮不丢字', () {
    test('各种语法混排后文本完全一致', () {
      const source = '---\n'
          'title: 测试\n'
          '# 注释\n'
          '---\n'
          '\n'
          '# 一级标题\n'
          '## 二级标题 ##\n'
          '\n'
          '普通 **粗体** 与 *斜体* 与 ~~删除~~ 与 `代码` 与 \$x^2\$。\n'
          '\n'
          '> 引用一行\n'
          '\n'
          '- [ ] 待办\n'
          '- [x] 完成\n'
          '1. 有序\n'
          '\n'
          '| 列 A | 列 B |\n'
          '| --- | --- |\n'
          '| 1 | 2 |\n'
          '\n'
          '```dart\n'
          'void main() { print("hi"); }\n'
          '```\n'
          '\n'
          '---\n'
          '\n'
          '[链接](https://example.com) 与 ![图](a.png) 与 https://bare.example\n';

      final span = highlighter.highlight(source);
      expect(fullText(span), source, reason: '高亮绝不能丢字或增字');
    });

    test('增量区间高亮与整体一致', () {
      const source = '# 标题\n\n正文 **粗体**\n';
      final whole = fullText(highlighter.highlight(source));
      final fromStart = fullText(highlighter.highlight(source, start: 0, end: source.length));
      expect(whole, source);
      expect(fromStart, source);
    });

    test('空文本返回空 span', () {
      expect(fullText(highlighter.highlight('')), '');
      expect(fullText(highlighter.highlight('abc', start: 2, end: 2)), '');
    });

    test('超长文本退化为纯文本但仍完整', () {
      final long = List<String>.generate(
        MarkdownHighlighter.maxHighlightedLines + 10,
        (i) => '第 $i 行 **粗体**',
      ).join('\n');
      final span = highlighter.highlight(long);
      expect(fullText(span), long);
    });
  });

  group('按语义着色', () {
    test('frontmatter 键与值分开着色', () {
      const source = '---\ntitle: 高数\n# 注释\n---\n正文';
      final parts = flatten(highlighter.highlight(source));

      expect(parts.any((p) => p.$1 == 'title' && p.$2 == theme.frontmatterKey.color), isTrue);
      // 值的着色范围是冒号之后的文本
      expect(parts.any((p) => p.$1 == ' 高数' && p.$2 == theme.frontmatterValue.color), isTrue);
      expect(parts.any((p) => p.$1 == '# 注释' && p.$2 == theme.frontmatterComment.color), isTrue);
      expect(parts.any((p) => p.$1 == '正文' && p.$2 == theme.body.color), isTrue);
    });

    test('代码块内容不按 Markdown 解析', () {
      const source = '```\n# 这不是标题\n**不是粗体**\n```\n';
      final parts = flatten(highlighter.highlight(source));
      expect(parts.any((p) => p.$1 == '# 这不是标题' && p.$2 == theme.codeBlock.color), isTrue);
      expect(parts.any((p) => p.$1 == '**不是粗体**' && p.$2 == theme.codeBlock.color), isTrue);
    });

    test('标题应用对应层级样式', () {
      final parts = flatten(highlighter.highlight('# 标题一\n'));
      expect(parts.any((p) => p.$1 == '标题一' && p.$2 == theme.heading(1).color), isTrue);
      expect(parts.any((p) => p.$1 == '#' && p.$2 == theme.punctuation.color), isTrue);
    });

    test('嵌套列表也能识别标记', () {
      final parts = flatten(highlighter.highlight('  - 子项\n'));
      expect(parts.any((p) => p.$1 == '-' && p.$2 == theme.listMarker.color), isTrue);
      expect(parts.any((p) => p.$1 == '子项'), isTrue);
    });

    test('粗体内容用 emphasis 样式', () {
      final parts = flatten(highlighter.highlight('这是 **重点** 内容\n'));
      expect(parts.any((p) => p.$1 == '重点' && p.$2 == theme.emphasis.color), isTrue);
    });

    test('未闭合的代码围栏不会让后续文本消失', () {
      const source = '```\n没有闭合\n后续行\n';
      expect(fullText(highlighter.highlight(source)), source);
    });
  });

  group('MarkdownEditingController', () {
    test('jumpToLine 把光标放到目标行且正文不变', () {
      final controller = MarkdownEditingController(
        theme: theme,
        text: '第一行\n第二行\n第三行\n',
      );
      addTearDown(controller.dispose);

      controller.jumpToLine(3);
      expect(controller.text, '第一行\n第二行\n第三行\n', reason: '正文必须不变');
      // 光标落在第三行行首
      expect(controller.selection.baseOffset, '第一行\n第二行\n'.length);
    });

    test('jumpToLine 支持列偏移并做边界收敛', () {
      final controller = MarkdownEditingController(theme: theme, text: 'abc\ndefg\n');
      addTearDown(controller.dispose);

      controller.jumpToLine(2, column: 3);
      expect(controller.selection.baseOffset, 6);

      controller.jumpToLine(99);
      expect(controller.selection.baseOffset, 'abc\ndefg\n'.length);

      controller.jumpToLine(1, column: 99);
      expect(controller.selection.baseOffset, 3);
    });

    test('buildTextSpan 不丢字且带高亮', () {
      final controller = MarkdownEditingController(theme: theme, text: '# 标题\n\n**粗体**\n');
      addTearDown(controller.dispose);

      final highlighterSpan = highlighter.highlight(
        controller.text,
        start: 0,
        end: controller.text.length,
      );
      expect(fullText(highlighterSpan), controller.text);
    });
  });

  group('TextStats', () {
    test('中英混排分别计数', () {
      final stats = TextStats.of('你好世界 hello world');
      expect(stats.cjkCharacters, 4);
      expect(stats.words, 6, reason: '4 个汉字 + 2 个英文词');
      expect(stats.lines, 1);
    });

    test('空文本统计为零', () {
      final stats = TextStats.of('');
      expect(stats.words, 0);
      expect(stats.lines, 0);
      expect(stats.characters, 0);
    });

    test('行数按换行符计算', () {
      expect(TextStats.of('a\nb\nc').lines, 3);
      expect(TextStats.of('a\nb\nc\n').lines, 4);
    });
  });
}
