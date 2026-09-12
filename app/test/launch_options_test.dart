import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/launch_options.dart';

void main() {
  group('LaunchOptions.parse', () {
    test('空参数不产生任何意图', () {
      final o = LaunchOptions.parse(const <String>[]);
      expect(o.isEmpty, isTrue);
      expect(o.libraryPath, isNull);
      expect(o.openFiles, isEmpty);
    });

    test('--library 与 --open 都能解析', () {
      final o = LaunchOptions.parse(const <String>['--library', r'D:\notes', '--open', r'D:\notes\a.md']);
      expect(o.libraryPath, r'D:\notes');
      expect(o.openFiles, <String>[r'D:\notes\a.md']);
    });

    test('短参数 -l / -o 等价', () {
      final o = LaunchOptions.parse(const <String>['-l', r'D:\n', '-o', r'D:\n\a.md']);
      expect(o.libraryPath, r'D:\n');
      expect(o.openFiles, <String>[r'D:\n\a.md']);
    });

    test('位置参数里的笔记路径也会被采纳', () {
      final o = LaunchOptions.parse(const <String>[r'D:\notes\a.md', r'D:\notes\b.markdown']);
      expect(o.openFiles, <String>[r'D:\notes\a.md', r'D:\notes\b.markdown']);
      expect(o.libraryPath, isNull);
    });

    test('位置参数里的非笔记路径被忽略', () {
      final o = LaunchOptions.parse(const <String>[r'D:\notes\image.png', '--flag']);
      expect(o.openFiles, isEmpty);
    });

    test('多个 --open 按顺序累积（最后一个用于激活）', () {
      final o = LaunchOptions.parse(const <String>[
        '--open', r'D:\n\a.md',
        '--open', r'D:\n\b.md',
      ]);
      expect(o.openFiles, <String>[r'D:\n\a.md', r'D:\n\b.md']);
      expect(o.openFiles.last, r'D:\n\b.md');
    });

    test('缺少取值的参数不会崩溃', () {
      final o = LaunchOptions.parse(const <String>['--library', '--open']);
      expect(o.libraryPath, isNull, reason: '--library 后面跟的是另一个开关，不应被当作路径');
      expect(o.openFiles, isEmpty);
    });

    test('带空格与中文的路径原样保留', () {
      const path = r'C:\我的 笔记\CUDA · 线程.md';
      final o = LaunchOptions.parse(const <String>['--open', path]);
      expect(o.openFiles.single, path);
    });

    test('大小写不敏感的后缀识别', () {
      final o = LaunchOptions.parse(const <String>[r'D:\a.MD', r'D:\b.Markdown', r'D:\c.TXT']);
      expect(o.openFiles.length, 3);
    });
  });
}
