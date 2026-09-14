// 端侧补全里不依赖模型、不依赖原生库的那部分逻辑。
//
// 送进模型的前缀怎么截，直接决定补全质量与延迟，边界必须钉住：
// 取错位置（比如整篇文档而不是光标前）会让每次建议都慢好几秒。

import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/state/ai_controller.dart';

void main() {
  group('补全前缀截取', () {
    test('空文本没有前缀', () {
      expect(completionPrefix('', 0), '');
    });

    test('光标在文首时没有前缀可送', () {
      expect(completionPrefix('这是正文', 0), '');
    });

    test('只取光标之前的内容，光标后的不动', () {
      // 光标在"碁"之前，后面那半句不该进提示词
      expect(completionPrefix('前半句后半句', 3), '前半句');
    });

    test('光标在文末时取全文', () {
      expect(completionPrefix('全部内容', 4), '全部内容');
    });

    test('超长时只保留末尾一段（补全只关心光标附近）', () {
      final long = 'a' * 1000;
      final prefix = completionPrefix(long, 1000, limit: 600);
      expect(prefix.length, 600);
      expect(prefix, 'a' * 600);
    });

    test('截断位置以光标为基准，而不是取文档开头', () {
      // 这是最容易写错的地方：取开头会导致光标附近的上下文被丢掉
      final long = '${'x' * 900}光标附近';
      final prefix = completionPrefix(long, long.length, limit: 10);
      expect(prefix, 'x' * 6 + '光标附近');
    });

    test('光标位置越界时按边界处理，不抛异常', () {
      // 编辑器刷新时序上可能短暂出现越界位置，崩了比返回空更糟
      expect(completionPrefix('正文', -5), '');
      expect(completionPrefix('正文', 999), '正文');
    });

    test('恰好等于上限时不截断', () {
      final exact = 'b' * 600;
      expect(completionPrefix(exact, 600, limit: 600), exact);
    });

    test('默认上限不会把整篇长文送进模型', () {
      // 原生上下文 512 token，整篇塞进去光 prefill 就要好几秒
      final huge = 'c' * 50000;
      expect(completionPrefix(huge, 50000).length, AiController.maxPrefixChars);
    });
  });

  group('建议校验', () {
    test('空建议一律不要', () {
      expect(suggestionLooksValid('', '正文'), isFalse);
      expect(suggestionLooksValid('   ', '正文'), isFalse);
    });

    test('普通段落里任何非空建议都收下', () {
      expect(suggestionLooksValid('继续写下去', '今天天气很好，我打算去'), isTrue);
    });

    test('表格行里残缺的建议被拒（这是实测会遇到的情况）', () {
      // 0.6B 写表格行时经常不输出行尾的 |
      const prefix = '| 平台 | 状态 |\n| --- | --- |\n| Windows | 已发布 |\n|';
      expect(suggestionLooksValid(' Linux | 已发布', prefix), isFalse);
    });

    test('表格行里完整的建议被收下', () {
      const prefix = '| 平台 | 状态 |\n| --- | --- |\n| Windows | 已发布 |\n|';
      expect(suggestionLooksValid(' Linux | 已发布 |', prefix), isTrue);
    });

    test('表格行建议含多行时每行都要完整', () {
      const prefix = '| a | b |\n| --- | --- |\n|';
      expect(suggestionLooksValid(' 1 | 2 |\n| 3 | 4 |', prefix), isTrue);
      // 第二行缺收尾竖线 → 整份建议都不要，避免只写进去半张表
      expect(suggestionLooksValid(' 1 | 2 |\n| 3 | 4 ', prefix), isFalse);
    });

    test('行尾空格不该影响判断', () {
      const prefix = '| a | b |\n| --- | --- |\n|';
      expect(suggestionLooksValid(' 1 | 2 |   ', prefix), isTrue);
    });

    test('列表行不受表格规则约束', () {
      const prefix = '- 支持 Windows\n-';
      expect(suggestionLooksValid(' 支持鸿蒙', prefix), isTrue);
    });
  });
}
