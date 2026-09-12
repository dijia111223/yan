import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/frontmatter.dart';

void main() {
  group('FrontmatterCodec.parse', () {
    test('没有 frontmatter 时正文原样返回', () {
      const content = '# 标题\n\n正文\n';
      final fm = FrontmatterCodec.parse(content);
      expect(fm.hasFrontmatter, isFalse);
      expect(fm.body, content);
      expect(fm.fields, isEmpty);
    });

    test('解析字段并把正文与 frontmatter 分离', () {
      const content = '---\n'
          'title: 高数笔记\n'
          'tags: [考研, 数学]\n'
          'created: 2026-09-09\n'
          '---\n'
          '\n'
          '# 极限\n'
          '内容\n';
      final fm = FrontmatterCodec.parse(content);

      expect(fm.hasFrontmatter, isTrue);
      expect(fm.string('title'), '高数笔记');
      expect(fm.stringList('tags'), <String>['考研', '数学']);
      expect(fm.dateTime('created'), DateTime(2026, 9, 9));
      // 分隔符后的第一个空行被吃掉，正文从标题开始
      expect(fm.body, '# 极限\n内容\n');
    });

    test('CRLF 行尾也能解析', () {
      const content = '---\r\ntitle: A\r\n---\r\n正文';
      final fm = FrontmatterCodec.parse(content);
      expect(fm.hasFrontmatter, isTrue);
      expect(fm.string('title'), 'A');
      expect(fm.body, '正文');
    });

    test('未闭合的 frontmatter 视为普通正文（不吞掉用户内容）', () {
      const content = '---\ntitle: A\n\n# 正文\n';
      final fm = FrontmatterCodec.parse(content);
      expect(fm.hasFrontmatter, isFalse);
      expect(fm.body, content);
    });

    test('YAML 语法错误不抛异常，raw 仍保留', () {
      const content = '---\ntitle: [未闭合\n---\n正文\n';
      final fm = FrontmatterCodec.parse(content);
      expect(fm.hasFrontmatter, isTrue);
      expect(fm.fields, isEmpty);
      expect(fm.raw, 'title: [未闭合');
      expect(fm.body, '正文\n');
    });

    test('... 也可作为结束分隔符', () {
      const content = '---\ntitle: A\n...\n正文';
      final fm = FrontmatterCodec.parse(content);
      expect(fm.hasFrontmatter, isTrue);
      expect(fm.string('title'), 'A');
      expect(fm.body, '正文');
    });

    test('空内容不崩', () {
      final fm = FrontmatterCodec.parse('');
      expect(fm.hasFrontmatter, isFalse);
      expect(fm.body, '');
    });
  });

  group('FrontmatterCodec.update', () {
    test('字段级更新保留其它字段与注释', () {
      const content = '---\n'
          '# 这是注释\n'
          'title: 旧标题\n'
          'tags: [a]\n'
          'source: ""\n'
          'lineage:\n'
          '  derived_from: []\n'
          '---\n'
          '正文\n';

      final updated = FrontmatterCodec.update(content, updates: <String, Object?>{'title': '新标题'});
      final fm = FrontmatterCodec.parse(updated);

      expect(fm.string('title'), '新标题');
      expect(fm.stringList('tags'), <String>['a']);
      expect(fm.fields.containsKey('lineage'), isTrue);
      expect(updated.contains('# 这是注释'), isTrue, reason: '注释必须保留');
      expect(fm.body, '正文\n');
    });

    test('更新 tags 写成 YAML 列表', () {
      const content = '---\ntitle: A\n---\n正文';
      final updated = FrontmatterCodec.update(
        content,
        updates: <String, Object?>{
          'tags': <String>['考研', '数学'],
        },
      );
      expect(FrontmatterCodec.parse(updated).stringList('tags'), <String>['考研', '数学']);
    });

    test('removeKeys 删除字段', () {
      const content = '---\ntitle: A\nsource: x\n---\n正文';
      final updated = FrontmatterCodec.update(content, removeKeys: <String>{'source'});
      final fm = FrontmatterCodec.parse(updated);
      expect(fm.fields.containsKey('source'), isFalse);
      expect(fm.string('title'), 'A');
    });

    test('没有 frontmatter 时按需创建', () {
      const content = '# 只 有 正 文\n';
      final updated = FrontmatterCodec.update(
        content,
        updates: <String, Object?>{'title': '新建'},
      );
      final fm = FrontmatterCodec.parse(updated);
      expect(fm.hasFrontmatter, isTrue);
      expect(fm.string('title'), '新建');
      expect(fm.body, content);
    });

    test('含冒号的值会被正确加引号', () {
      const content = '---\ntitle: A\n---\n';
      final updated = FrontmatterCodec.update(
        content,
        updates: <String, Object?>{'source': '《数学分析》: 第一章'},
      );
      expect(FrontmatterCodec.parse(updated).string('source'), '《数学分析》: 第一章');
    });

    test('YAML 已损坏时退化为整体重写，不丢用户输入', () {
      const content = '---\ntitle: [未闭合\n---\n正文\n';
      final updated = FrontmatterCodec.update(content, updates: <String, Object?>{'source': 'x'});
      final fm = FrontmatterCodec.parse(updated);
      expect(fm.hasFrontmatter, isTrue);
      expect(fm.string('source'), 'x');
      expect(fm.body, '正文\n');
    });
  });

  group('FrontmatterCodec.ensureFrontmatter', () {
    test('缺失时补齐语料层规范字段', () {
      const content = '# 我的笔记\n\n内容\n';
      final filled = FrontmatterCodec.ensureFrontmatter(content);
      final fm = FrontmatterCodec.parse(filled);

      expect(fm.hasFrontmatter, isTrue);
      for (final field in Frontmatter.corpusFields) {
        if (field == 'lineage') continue; // lineage 以注释形式预留
        expect(fm.fields.containsKey(field), isTrue, reason: '缺少规范字段 $field');
      }
      expect(fm.string('title'), '我的笔记');
      expect(filled.contains('lineage'), isTrue, reason: 'lineage 血缘字段应预留');
      expect(fm.body, content);
    });

    test('已有 frontmatter 时原样返回', () {
      const content = '---\ntitle: A\n---\n正文';
      expect(FrontmatterCodec.ensureFrontmatter(content), content);
    });

    test('标题从第一行文本推断，去掉 # 号', () {
      const content = '## 二级标题开头\n';
      final fm = FrontmatterCodec.parse(FrontmatterCodec.ensureFrontmatter(content));
      // 推断出的是标题的**文字**，`##` 标记被剥掉
      expect(fm.string('title'), '二级标题开头');
      expect(fm.body, content, reason: '正文必须原样保留');
    });

    test('推断出的超长标题截断到 60 字', () {
      final long = '标' * 100;
      final fm = FrontmatterCodec.parse(FrontmatterCodec.ensureFrontmatter('# $long\n'));
      expect(fm.string('title')!.length, 60);
    });
  });
}
