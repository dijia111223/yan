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

  /// 相对库根的路径，例如 `考研/数学/高数.md`。
  final String relativePath;

  final String name;

  /// 是否命中了文件名（文件名命中优先展示）。
  final bool isFileNameMatch;

  /// 匹配得分，越大越靠前。
  final int score;

  /// 命中的行号（1 基）。文件名命中时为 null。
  final int? line;

  /// 命中的列号（1 基）。
  final int? column;

  /// 命中行附近的片段（前后各留若干字符）。
  final String? snippet;

  /// [snippet] 中匹配串的起止下标，用于高亮。
  final int? matchStart;
  final int? matchEnd;

  String get location => line == null ? '' : '第 $line 行';
}

/// 搜索范围。
enum SearchScope {
  both('文件名 + 内容'),
  fileName('仅文件名'),
  content('仅内容');

  const SearchScope(this.label);

  final String label;
}

/// 全文搜索引擎。
///
/// 宪章 v1 的"全文搜索（文件名+内容）"就是这一块：
/// 纯文件、无索引文件、无数据库——直接遍历磁盘。
/// 库规模在数万文件以内时足够快（读文件上限 + 命中数上限双重保护）。
class SearchEngine {
  const SearchEngine(this.library);

  final Library library;

  /// 单次搜索最多返回的命中数。
  static const int maxHits = 300;

  /// 单次搜索最多读取的文件数。
  static const int maxFilesScanned = 8000;

  /// 单个文件最多返回的命中行数（避免一个长文件刷屏）。
  static const int maxHitsPerFile = 20;

  /// 执行搜索。
  ///
  /// [query] 大小写不敏感。返回按得分排序的命中列表。
  Future<List<SearchHit>> search(
    String query, {
    SearchScope scope = SearchScope.both,
    bool searchFrontmatter = true,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <SearchHit>[];

    final files = await library.collectMarkdownFiles();
    // 文件名命中优先，同时稳定排序保证结果可复现
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
      // 非 UTF-8 文件跳过（v1 不做编码嗅探）
      return const <SearchHit>[];
    }

    final lines = content.split('\n');
    // 判断 frontmatter 占据的行区间，用于按开关跳过
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

      // 截取命中点前后的一段文本；两端截断时补省略号
      final windowStart = index - 40 < 0 ? 0 : index - 40;
      final windowEnd = index + needle.length + 60 > lineText.length
          ? lineText.length
          : index + needle.length + 60;
      final prefix = windowStart > 0 ? '…' : '';
      final suffix = windowEnd < lineText.length ? '…' : '';
      // 只去掉左侧空白，并同步修正匹配串在片段中的下标
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
