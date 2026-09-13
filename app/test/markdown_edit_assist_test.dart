// Markdown 编辑增强的边界测试。
//
// 这些行为直接改用户正在敲的内容，出错比不做还糟，所以边界要逐个钉住：
// 空条目退出列表、有序列表递增、任务列表重置勾选、成对符号不重复补、
// 退格一次删掉自动补的符号、以及"拿不准就不动文本"。

import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/markdown_edit_assist.dart';

/// 便捷构造：`|` 标记光标位置。
({String text, TextSelectionRange sel}) at(String marked) {
  final i = marked.indexOf('|');
  final text = marked.replaceFirst('|', '');
  return (text: text, sel: TextSelectionRange.collapsed(i));
}

void main() {
  group('回车续列表', () {
    test('无序列表续行', () {
      final s = at('- 第一条|');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '- 第一条\n- ');
      // 光标应落在新标记之后（这里正好也是文末）
      expect(r.selection, TextSelectionRange.collapsed(r.text!.length));
    });

    test('有序列表递增', () {
      final s = at('3. 第三|');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '3. 第三\n4. ');
    });

    test('右括号形式的有序列表也递增', () {
      final s = at('1) 甲|');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '1) 甲\n2) ');
    });

    test('缩进保留', () {
      final s = at('    - 深层|');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '    - 深层\n    - ');
    });

    test('任务列表续行回到未勾选', () {
      final s = at('- [x] 做完了|');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '- [x] 做完了\n- [ ] ');
    });

    test('空条目再回车 → 退出列表（删掉标记）', () {
      final s = at('- |');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '');
      expect(r.selection, const TextSelectionRange.collapsed(0));
    });

    test('任务列表空条目再回车 → 退出列表', () {
      final s = at('- [ ] |');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.newline)!;
      expect(r.text, '');
    });

    test('普通段落回车不介入', () {
      final s = at('就是一句话|');
      expect(
        applyEdit(text: s.text, selection: s.sel, kind: EditKind.newline),
        isNull,
      );
    });

    test('行内出现星号不算列表', () {
      final s = at('强调 *这里* 结束|');
      expect(
        applyEdit(text: s.text, selection: s.sel, kind: EditKind.newline),
        isNull,
      );
    });
  });

  group('成对符号自动配对', () {
    test('输入单个 * 补成 ** 并把光标放中间', () {
      final s = at('|');
      final r = applyEdit(
          text: s.text, selection: s.sel, inserted: '*')!;
      expect(r.text, '**');
      expect(r.selection, const TextSelectionRange.collapsed(1));
    });

    test('行内已有奇数个 * 时不补（避免弄乱）', () {
      final s = at('a *b|');
      expect(applyEdit(text: s.text, selection: s.sel, inserted: '*'), isNull);
    });

    test('光标右侧是同符号 → 跳过而不是重复插入', () {
      final s = at('**|**');
      final r = applyEdit(
          text: s.text, selection: s.sel, inserted: '*')!;
      expect(r.text, '**|**'.replaceFirst('|', '')); // 文本不变
      expect(r.selection!.start, greaterThan(s.sel.start));
    });

    test('有选区时输入 * → 包裹选区', () {
      const text = '粗体';
      const sel = TextSelectionRange(0, 2);
      final r = applyEdit(text: text, selection: sel, inserted: '*')!;
      expect(r.text, '*粗体*');
      expect(r.selection, const TextSelectionRange(1, 3));
    });

    test('括号不做自动配对（交给编辑器默认）', () {
      final s = at('|');
      expect(applyEdit(text: s.text, selection: s.sel, inserted: '('), isNull);
    });

    test('普通字母不介入', () {
      final s = at('|');
      expect(applyEdit(text: s.text, selection: s.sel, inserted: 'a'), isNull);
    });
  });

  group('代码围栏自动闭合', () {
    test('行首输入反引号 → 直接给出成对围栏，光标在中间', () {
      final r = applyEdit(
          text: '',
          selection: const TextSelectionRange.collapsed(0),
          inserted: '`')!;
      expect(r.text, '```\n\n```');
      // 光标落在两个围栏之间的空行
      expect(r.selection, const TextSelectionRange.collapsed(4));
    });

    test('行首只有空白时也触发', () {
      final s = at('  |');
      final r = applyEdit(text: s.text, selection: s.sel, inserted: '`')!;
      expect(r.text, '  ```\n\n```');
    });

    test('同一文档里已有闭合围栏时不重复补', () {
      const text = '```\ncode\n```\n';
      final r = applyEdit(
          text: text,
          selection: const TextSelectionRange.collapsed(0),
          inserted: '`');
      // 光标不在行首空白处的语义下不该再生成一对新的围栏
      if (r != null) {
        expect(r.text!.split('```').length - 1, lessThanOrEqualTo(2));
      }
    });

    test('不在行首时不触发围栏', () {
      final s = at('文字 |');
      final r = applyEdit(text: s.text, selection: s.sel, inserted: '`');
      if (r != null) expect(r.text!.contains('```'), isFalse);
    });
  });

  group('退格', () {
    test('成对符号之间退格一次删掉两侧', () {
      final s = at('*|*');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.backspace)!;
      expect(r.text, '');
      expect(r.selection, const TextSelectionRange.collapsed(0));
    });

    test('列表标记整段删掉而不是逐字符', () {
      final s = at('- 甲\n- |');
      final r = applyEdit(
          text: s.text, selection: s.sel, kind: EditKind.backspace)!;
      expect(r.text, '- 甲\n');
    });

    test('普通文字退格不介入', () {
      final s = at('abc|');
      expect(
        applyEdit(text: s.text, selection: s.sel, kind: EditKind.backspace),
        isNull,
      );
    });

    test('文首退格不介入', () {
      expect(
        applyEdit(
            text: 'abc',
            selection: const TextSelectionRange.collapsed(0),
            kind: EditKind.backspace),
        isNull,
      );
    });
  });

  group('Tab', () {
    test('表格行跳到下一格', () {
      // 注意：不能用 at() 辅助函数 —— 表格文本本身以 | 开头，
      // replaceFirst('|','') 会删掉表格的第一个竖线而不是光标标记。
      const text = '| 甲 | 乙 |';
      const sel = TextSelectionRange.collapsed(3); // 光标在「甲」右侧
      final r = applyEdit(text: text, selection: sel, kind: EditKind.tab)!;
      // 行内下一个 | 在索引 4，光标跳到它之后
      expect(r.text, text);
      expect(r.selection, const TextSelectionRange.collapsed(5));
    });

    test('列表项 Tab 缩进两格', () {
      final s = at('- 甲|');
      final r = applyEdit(text: s.text, selection: s.sel, kind: EditKind.tab)!;
      expect(r.text, '  - 甲');
      // 整行前移两格，光标跟着走：'- 甲' 末尾在 3，缩进后到 5
      expect(r.selection, const TextSelectionRange.collapsed(5));
    });

    test('普通行 Tab 不介入', () {
      final s = at('普通|');
      expect(applyEdit(text: s.text, selection: s.sel, kind: EditKind.tab), isNull);
    });
  });
}
