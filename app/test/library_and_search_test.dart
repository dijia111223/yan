import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yan_note/src/core/library.dart';
import 'package:yan_note/src/core/models.dart';
import 'package:yan_note/src/core/search.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('yan_lib_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String relative, String content) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  group('Library.listChildren', () {
    test('目录排在文件前，跳过隐藏与忽略目录', () async {
      write('a.md', 'x');
      write('b.md', 'y');
      Directory(p.join(root.path, '子目录')).createSync();
      write('.hidden.md', 'x');
      Directory(p.join(root.path, '.git')).createSync();
      write('.git/config', 'x');
      Directory(p.join(root.path, 'attachments')).createSync();
      write('attachments/img.png', 'x');
      write('notes.txt', '普通文本');

      final library = Library(root.path);
      final entries = await library.listChildren(root.path);

      expect(entries.first.isDirectory, isTrue, reason: '目录必须排在文件前');
      expect(entries.first.name, '子目录');
      expect(entries.map((e) => e.name), isNot(contains('.hidden.md')));
      expect(entries.map((e) => e.name), isNot(contains('.git')));
      expect(entries.map((e) => e.name), isNot(contains('attachments')));
      expect(entries.map((e) => e.name), contains('notes.txt'));
    });

    test('按名称 A→Z 排序（忽略大小写）', () async {
      write('Beta.md', '');
      write('alpha.md', '');
      write('gamma.md', '');
      final entries = await Library(root.path).listChildren(root.path);
      expect(entries.map((e) => e.name), <String>['alpha.md', 'Beta.md', 'gamma.md']);
    });

    test('按修改时间倒序排序', () async {
      write('old.md', '');
      final old = File(p.join(root.path, 'old.md'));
      old.setLastModifiedSync(DateTime(2020));
      write('new.md', '');
      File(p.join(root.path, 'new.md')).setLastModifiedSync(DateTime(2026));

      final entries = await Library(root.path)
          .listChildren(root.path, sort: LibrarySort.modifiedDesc);
      expect(entries.first.name, 'new.md');
    });

    test('目录不存在时返回空列表而不是抛异常', () async {
      final entries = await Library(root.path).listChildren(p.join(root.path, '不存在'));
      expect(entries, isEmpty);
    });
  });

  group('LibraryEntry', () {
    test('识别 Markdown 文件', () {
      expect(
        const LibraryEntry(name: 'a.md', path: 'a.md', isDirectory: false).isMarkdown,
        isTrue,
      );
      expect(
        const LibraryEntry(name: 'a.markdown', path: 'a', isDirectory: false).isMarkdown,
        isTrue,
      );
      expect(
        const LibraryEntry(name: 'a.png', path: 'a', isDirectory: false).isMarkdown,
        isFalse,
      );
      expect(
        const LibraryEntry(name: 'dir', path: 'd', isDirectory: true).isMarkdown,
        isFalse,
      );
    });

    test('displayName 去掉扩展名', () {
      expect(
        const LibraryEntry(name: '高数笔记.md', path: 'a', isDirectory: false).displayName,
        '高数笔记',
      );
    });
  });

  group('Library.collectMarkdownFiles', () {
    test('递归收集，跳过忽略目录', () async {
      write('a.md', '');
      write('子/深/b.markdown', '');
      write('.git/c.md', '');
      write('子/图片.png', '');

      final files = await Library(root.path).collectMarkdownFiles();
      final names = files.map((f) => f.name).toList()..sort();
      expect(names, <String>['a.md', 'b.markdown']);
    });
  });

  group('Library 写操作', () {
    test('createNote 自动避免重名', () async {
      final library = Library(root.path);
      final first = await library.createNote(baseName: '笔记');
      final second = await library.createNote(baseName: '笔记');
      expect(p.basename(first), '笔记.md');
      expect(p.basename(second), '笔记 1.md');
      expect(File(first).existsSync(), isTrue);
      expect(File(second).existsSync(), isTrue);
    });

    test('createFolder 自动避免重名', () async {
      final library = Library(root.path);
      final first = await library.createFolder(baseName: '目录');
      final second = await library.createFolder(baseName: '目录');
      expect(p.basename(first), '目录');
      expect(p.basename(second), '目录 1');
      expect(Directory(second).existsSync(), isTrue);
    });

    test('rename 改名文件', () async {
      write('旧.md', '内容');
      final library = Library(root.path);
      final newPath = await library.rename(p.join(root.path, '旧.md'), '新.md');
      expect(p.basename(newPath), '新.md');
      expect(File(newPath).readAsStringSync(), '内容');
      expect(File(p.join(root.path, '旧.md')).existsSync(), isFalse);
    });

    test('rename 遇到同名文件时抛异常，不覆盖', () async {
      write('a.md', 'A');
      write('b.md', 'B');
      final library = Library(root.path);
      expect(
        () => library.rename(p.join(root.path, 'a.md'), 'b.md'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(p.join(root.path, 'b.md')).readAsStringSync(), 'B');
    });

    test('delete 删除文件与目录', () async {
      write('a.md', '');
      write('目录/b.md', '');
      final library = Library(root.path);
      await library.delete(p.join(root.path, 'a.md'));
      expect(File(p.join(root.path, 'a.md')).existsSync(), isFalse);
      await library.delete(p.join(root.path, '目录'));
      expect(Directory(p.join(root.path, '目录')).existsSync(), isFalse);
    });

    test('relative 输出以 / 分隔的库内相对路径', () {
      final library = Library(root.path);
      final absolute = p.join(root.path, '考研', '数学', '高数.md');
      expect(library.relative(absolute), '考研/数学/高数.md');
    });
  });

  group('SearchEngine', () {
    test('文件名命中排在最前，得分更高', () async {
      write('数据结构.md', '这是一篇没有关键词的正文。');
      write('其它.md', '正文里提到了数据结构这四个字。');

      final hits = await SearchEngine(Library(root.path)).search('数据结构');
      expect(hits.length, 2);
      expect(hits.first.isFileNameMatch, isTrue);
      expect(hits.first.name, '数据结构.md');
      expect(hits.last.isFileNameMatch, isFalse);
    });

    test('内容命中带行号与片段', () async {
      write('笔记.md', '第一行\n第二行\n第三行有目标词\n第四行\n');
      final hits = await SearchEngine(Library(root.path)).search('目标词');
      expect(hits.length, 1);
      expect(hits.first.line, 3);
      expect(hits.first.snippet, contains('目标词'));
      expect(hits.first.location, '第 3 行');
      // “第三行有目标词”：目标词从第 5 个字符开始（1 基列号）
      expect(hits.first.column, 5);
    });

    test('片段高亮下标能对上匹配串', () async {
      write('长文.md', '${'前缀' * 40}魔法关键词${'后缀' * 40}');
      final hits = await SearchEngine(Library(root.path)).search('魔法关键词');
      expect(hits.length, 1);
      final hit = hits.first;
      final start = hit.matchStart!;
      final end = hit.matchEnd!;
      expect(hit.snippet!.substring(start, end), '魔法关键词');
    });

    test('搜索大小写不敏感', () async {
      write('Code.md', 'Flutter 与 DART');
      final hits = await SearchEngine(Library(root.path)).search('flutter');
      expect(hits, isNotEmpty);
      expect(hits.first.name, 'Code.md');
    });

    test('scope=fileName 只匹配文件名', () async {
      write('目标.md', '正文里也有目标两个字');
      write('其它.md', '只有正文提到目标');
      final hits = await SearchEngine(Library(root.path))
          .search('目标', scope: SearchScope.fileName);
      expect(hits.length, 1);
      expect(hits.first.isFileNameMatch, isTrue);
    });

    test('searchFrontmatter=false 时跳过 frontmatter', () async {
      write(
        'a.md',
        '---\ntitle: 独有词\n---\n正文没有那个词\n',
      );
      final withFm = await SearchEngine(Library(root.path)).search('独有词');
      expect(withFm, isNotEmpty);

      final withoutFm = await SearchEngine(Library(root.path))
          .search('独有词', searchFrontmatter: false);
      expect(withoutFm, isEmpty);
    });

    test('空查询返回空结果', () async {
      write('a.md', '内容');
      expect(await SearchEngine(Library(root.path)).search('   '), isEmpty);
    });

    test('标题行命中获得额外加分', () async {
      write('a.md', '普通一行包含关键词\n# 关键词\n');
      final hits = await SearchEngine(Library(root.path)).search('关键词');
      final bodyHits = hits.where((h) => !h.isFileNameMatch).toList();
      expect(bodyHits.length, 2);
      expect(bodyHits.first.line, 2, reason: '标题行应排在普通行之前');
    });
  });
}
