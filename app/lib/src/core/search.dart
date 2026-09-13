import 'dart:io';

import 'package:path/path.dart' as p;

import 'frontmatter.dart';
import 'library.dart';
import 'models.dart';

/// 单条搜索命中。
class SearchHit {
  const SearchHit({
    required this.path,
    required this.relativePath,
    required this.name,
    required this.isFileNameMatch,
    required this.score,
    this.line,
    this.column,
    this.snippet,
    this.matchStart,
    this.matchEnd,
  });

  final String path;

  final String relativePath;

  final String name;

  final bool isFileNameMatch;

  final int score;

  /// 命中的行号（1 基）；文件名命中时为 null。
  final int? line;

  final int? column;

  final String? snippet;

  /// [snippet] 中匹配串的起止下标，用于高亮。
  final int? matchStart;
  final int? matchEnd;

  String get location => line == null ? '' : '第 $line 行';
}

enum SearchScope {
  both('文件名 + 内容'),
  fileName('仅文件名'),
  content('仅内容');

  const SearchScope(this.label);

  final String label;
}

/// 全文搜索引擎：直接遍历磁盘，没有索引文件、没有数据库。
class SearchEngine {
  const SearchEngine(this.library);

  final Library library;

  /// 单次搜索最多返回的命中数。
  static const int maxHits = 300;

  static const int maxFilesScanned = 8000;

  /// 单个文件最多返回的命中行数（避免一个长文件刷屏）。
  static const int maxHitsPerFile = 20;

  /// [query] 大小写不敏感；返回按得分排序的命中。
  Future<List<SearchHit>> search(
    String query, {
    SearchScope scope = SearchScope.both,
    bool searchFrontmatter = true,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <SearchHit>[];

    final files = await library.collectMarkdownFiles();
    // 先按路径排序，保证同名得分的结果顺序可复现
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    final hits = <SearchHit>[];
    var scanned = 0;

    for (final file in files) {
      if (hits.length >= maxHits) break;

      final relative = library.relative(file.path);

      if (scope != SearchScope.content) {
        final nameHit = _matchFileName(file, relative, needle);
        if (nameHit != null) hits.add(nameHit);
      }

      if (scope == SearchScope.fileName) continue;
      if (scanned >= maxFilesScanned) continue;
      scanned++;

      final contentHits = await _searchContent(file, relative, needle, searchFrontmatter);
      for (final hit in contentHits) {
        if (hits.length >= maxHits) break;
        hits.add(hit);
      }
    }

    hits.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      final byPath = a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
      if (byPath != 0) return byPath;
      return (a.line ?? 0).compareTo(b.line ?? 0);
    });

    return hits;
  }

  SearchHit? _matchFileName(LibraryEntry file, String relative, String needle) {
    final name = file.name.toLowerCase();
    final index = name.indexOf(needle);
    if (index < 0) return null;

    // 完全相等 > 前缀命中 > 中间命中
    final score = switch (index) {
      0 when name.length - p.extension(name).length == needle.length => 1000,
      0 => 800,
      _ => 600,
    };

    return SearchHit(
      path: file.path,
      relativePath: relative,
      name: file.name,
      isFileNameMatch: true,
      score: score,
      snippet: file.name,
      matchStart: index,
      matchEnd: index + needle.length,
    );
  }

  Future<List<SearchHit>> _searchContent(
    LibraryEntry file,
    String relative,
    String needle,
    bool searchFrontmatter,
  ) async {
    final String content;
    try {
      content = await File(file.path).readAsString();
    } on FileSystemException {
      return const <SearchHit>[];
    } on FormatException {
      // 非 UTF-8 文件跳过，v1 不做编码嗅探
      return const <SearchHit>[];
    }

    final lines = content.split('\n');
    // 正文起始行 = frontmatter 原始行数 + 两行分隔符
    var bodyStartLine = 0;
    if (!searchFrontmatter) {
      final parsed = FrontmatterCodec.parse(content);
      if (parsed.hasFrontmatter) {
        bodyStartLine = parsed.raw.split('\n').length + 2;
      }
    }

    final hits = <SearchHit>[];
    for (var i = 0; i < lines.length; i++) {
      if (hits.length >= maxHitsPerFile) break;
      if (i < bodyStartLine) continue;

      final lineText = lines[i];
      final index = lineText.toLowerCase().indexOf(needle);
      if (index < 0) continue;

      final windowStart = index - 40 < 0 ? 0 : index - 40;
      final windowEnd = index + needle.length + 60 > lineText.length
          ? lineText.length
          : index + needle.length + 60;
      final prefix = windowStart > 0 ? '…' : '';
      final suffix = windowEnd < lineText.length ? '…' : '';
      final raw = lineText.substring(windowStart, windowEnd);
      final trimmed = raw.trimLeft();
      final dropped = raw.length - trimmed.length;
      final snippet = '$prefix$trimmed$suffix';
      final matchStart = (prefix.length + (index - windowStart) - dropped).clamp(0, snippet.length);
      final matchEnd = (matchStart + needle.length).clamp(0, snippet.length);

      hits.add(
        SearchHit(
          path: file.path,
          relativePath: relative,
          name: file.name,
          isFileNameMatch: false,
          // 正文命中永远排在文件名命中之后
          score: 100 + _lineBonus(lineText, index),
          line: i + 1,
          column: index + 1,
          snippet: snippet,
          matchStart: matchStart,
          matchEnd: matchEnd,
        ),
      );
    }
    return hits;
  }

  /// 标题行 / 行首命中给一点加成，让"真正相关的行"更靠前。
  static int _lineBonus(String line, int index) {
    var bonus = 0;
    if (line.trimLeft().startsWith('#')) bonus += 30;
    if (index == 0) bonus += 10;
    return bonus;
  }
}
