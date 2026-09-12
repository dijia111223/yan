import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/latex_to_unicode.dart';
import 'package:yan_note/src/core/math_text.dart';

void main() {
  group('MathExtractor.extract · 行内公式转 Unicode', () {
    test('简单行内公式随文排版，源码里不再有美元号', () {
      final result = MathExtractor.extract(r'质能方程 $E = mc^2$ 很重要');

      expect(result.fragments, isEmpty, reason: '行内公式不进公式表');
      expect(result.markdown, contains('质能方程'));
      expect(result.markdown, contains('mc²'), reason: '上标要转成 Unicode');
      expect(result.markdown.contains(r'$'), isFalse, reason: '美元号应被消耗掉');
    });

    test('希腊字母与关系符转成 Unicode', () {
      final result = MathExtractor.extract(r'设 $\alpha \le \beta$ 成立');
      expect(result.markdown.contains('α'), isTrue);
      expect(result.markdown.contains('≤'), isTrue);
      expect(result.markdown.contains('β'), isTrue);
    });

    test('分式与根号退化成可读文本', () {
      final fraction = MathExtractor.extract(r'$\frac{a}{b}$');
      expect(fraction.markdown.contains('a/b'), isTrue);

      final root = MathExtractor.extract(r'$\sqrt{2}$');
      expect(root.markdown.contains('√2'), isTrue);
    });

    test('无法可靠转换的公式保留原始 LaTeX，绝不输出错公式', () {
      const source = r'复杂结构 $\begin{matrix} a & b \\ c & d \end{matrix}$ 结束';
      final result = MathExtractor.extract(source);
      // 无法转换 → 原样保留（含美元号），用户能立刻看出并改写
      expect(result.markdown.contains('begin{matrix}'), isTrue);
      expect(result.markdown.contains('结束'), isTrue);
    });

    test('未配对或空公式保持原样，不吞掉整段文字', () {
      final unpaired = MathExtractor.extract(r'这里有 $ 一个孤立的美元号');
      expect(unpaired.fragments, isEmpty);
      expect(unpaired.markdown.contains('一个孤立的美元号'), isTrue);

      final empty = MathExtractor.extract(r'空公式 $$ 之后还有文字');
      expect(empty.fragments, isEmpty);
      expect(empty.markdown.contains('之后还有文字'), isTrue);
    });

    test(r'转义的 \$ 变成普通美元号且不产生公式', () {
      final result = MathExtractor.extract(r'价格是 \$5');
      expect(result.fragments, isEmpty);
      // 输出里应是不带反斜杠的字面量美元号
      expect(result.markdown, '价格是 \$5'.replaceAll(r'\$', r'$'));
    });
  });

  group('MathExtractor.extract · 行间公式转块引用', () {
    test('行间公式变成块引用占位符并登记到公式表', () {
      final result = MathExtractor.extract('前文\n\$\$\n\\int_0^1 x\\,dx\n\$\$\n后文');

      expect(result.fragments.length, 1);
      expect(result.fragments.values.first.tex, r'\int_0^1 x\,dx');
      // 块引用形式，预览层据此整体替换成公式组件
      expect(result.markdown.contains('> ${MathExtractor.placeholder(0)}'), isTrue);
      expect(result.markdown.contains(r'$$'), isFalse);
    });

    test('多行行间公式可用（不跨空行）', () {
      final ok = MathExtractor.extract('\$\$a\n+b\$\$');
      expect(ok.fragments.length, 1);

      final blankLine = MathExtractor.extract('\$\$a\n\n+b\$\$');
      expect(blankLine.fragments, isEmpty, reason: '空行分段不构成公式');
    });

    test(r'\[...\] 与 \(...\) 两种写法都支持', () {
      final result = MathExtractor.extract(r'行内 \(a+b\) 与行间 \[c+d\]');
      // \(..\) 是行内 → 转 Unicode，不进公式表
      expect(result.fragments.length, 1);
      expect(result.fragments.values.first.tex, 'c+d');
      expect(result.markdown.contains('a+b'), isTrue);
    });

    test('多个行间公式编号递增且可反查', () {
      final result = MathExtractor.extract('\$\$a\$\$\n\n\$\$b\$\$');
      expect(result.fragments.length, 2);
      for (var i = 0; i < 2; i++) {
        final key = MathExtractor.placeholder(i);
        expect(result.fragments.containsKey(key), isTrue);
        expect(MathExtractor.placeholderIndex(key), i);
      }
    });
  });

  group('MathExtractor.extract · 代码块保护', () {
    test('代码块里的美元号与反斜杠一个字符都不动', () {
      const source = r'''```bash
echo "\$HOME"
let x = \$5
```

正文 $b$ 结束''';
      expect(source.contains(r'\$HOME'), isTrue, reason: '前置条件：代码块里是反斜杠+美元号');

      final result = MathExtractor.extract(source);
      // 代码块原样保留（含反斜杠与美元号）
      expect(result.markdown.contains(r'echo "\$HOME"'), isTrue);
      expect(result.markdown.contains(r'let x = \$5'), isTrue);
      // 正文里的 $b$ 被转换，源码里不再有美元号
      expect(result.markdown.contains('正文 b 结束'), isTrue);
      expect(result.fragments, isEmpty);
    });

    test('行内代码里的美元号不动', () {
      final result = MathExtractor.extract(r'用 `$a$` 表示公式，真正的公式是 $b$');
      expect(result.markdown.contains(r'`$a$`'), isTrue);
      expect(result.markdown.contains('真正的公式是 b'), isTrue);
    });

    test('~ 围栏代码块同样被跳过', () {
      const source = '~~~\n\$x\$\n~~~\n真公式 \$y\$';
      final result = MathExtractor.extract(source);
      expect(result.markdown.contains(r'$x$'), isTrue, reason: '围栏内原样');
      expect(result.markdown.contains('真公式 y'), isTrue);
    });

    test('没有公式的文本原样返回', () {
      const source = '# 普通 Markdown\n\n没有公式。';
      final result = MathExtractor.extract(source);
      expect(result.fragments, isEmpty);
      expect(result.markdown, source);
    });
  });

  group('latexToUnicode', () {
    test('上下标逐字符映射', () {
      expect(latexToUnicode('x^2'), 'x²');
      expect(latexToUnicode('a_1'), 'a₁');
      expect(latexToUnicode(r'x^{10}'), 'x¹⁰');
      // 下标 "i=1" 三个字符都有 Unicode 下标形式
      expect(latexToUnicode(r'\sum_{i=1}'), 'Σᵢ₌₁');
      // 上标 n 同样有对应字符
      expect(latexToUnicode(r'\sum^{n}'), 'Σⁿ');
      expect(latexToUnicode(r'\int_0^1'), '∫₀¹');
    });

    test('命令边界正确：\\in 不会吃掉 \\infty', () {
      expect(latexToUnicode(r'\infty'), '∞');
      expect(latexToUnicode(r'a \in A'), 'a ∈ A');
    });

    test('未知命令返回 null（上层退回原始 LaTeX）', () {
      expect(latexToUnicode(r'\notARealCommand{x}'), isNull);
      expect(latexToUnicode(r'\begin{matrix}'), isNull);
    });

    test('没有对应上下标字符时返回 null，不硬猜', () {
      // 大写 Q 没有 Unicode 上标形式
      expect(latexToUnicode('Q^Q'), isNull);
      // 下标字符表里没有箭头，因此不能把 \to 塞进下标
      expect(latexToUnicode(r'a_{x \to 0}'), isNull);
    });

    test('空白与花括号被规整', () {
      expect(latexToUnicode(r'{a}'), 'a');
      // \, 是"细空格"命令，本身不产出字符，两侧原有空格保留
      expect(latexToUnicode(r'a \, b'), 'a  b');
      expect(latexToUnicode('  '), isNull);
    });

    test('常见函数名保留为文本', () {
      expect(latexToUnicode(r'\sin x'), 'sin x');
      expect(latexToUnicode(r'\lim_{x}'), 'limₓ');
      expect(latexToUnicode(r'\log_2 n'), 'log₂ n');
    });
  });

  group('MathExtractor.findPlaceholders', () {
    test('找出文本中的占位符及其下标', () {
      final key0 = MathExtractor.placeholder(0);
      final key1 = MathExtractor.placeholder(1);
      final text = '前$key0中$key1后';
      final found = MathExtractor.findPlaceholders(text);
      expect(found.length, 2);
      expect(found[0].$3, 0);
      expect(found[1].$3, 1);
      expect(text.substring(found[0].$1, found[0].$2), key0);
    });

    test('普通文本不误判为占位符', () {
      expect(MathExtractor.findPlaceholders('普通文本'), isEmpty);
      expect(MathExtractor.placeholderIndex('YANMATH0'), isNull);
      expect(MathExtractor.placeholderIndex('\u0000YANMATHx\u0000'), isNull);
      expect(MathExtractor.placeholderIndex('  \u0000YANMATH3\u0000  '), 3);
    });
  });
}
