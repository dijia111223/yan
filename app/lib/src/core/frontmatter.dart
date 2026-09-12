import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// frontmatter 解析结果。
///
/// 宪章第 7 节：编辑器的 frontmatter 字段 = 统一语料层规范，
/// 是"体用组合"的焊接点。因此这里必须做到 **无损**：
/// 未识别的字段、注释、字段顺序在回写时都要保留。
class Frontmatter {
  const Frontmatter({
    required this.hasFrontmatter,
    required this.fields,
    required this.raw,
    required this.body,
  });

  /// 文件中是否存在 frontmatter 块（`---` 开头并以 `---`/`...` 结束）。
  final bool hasFrontmatter;

  /// 解析出的字段（顶层映射）。解析失败时为只读空映射。
  final Map<String, Object?> fields;

  /// frontmatter 的原始文本（不含两侧分隔符行）。
  final String raw;

  /// 去掉 frontmatter 之后的正文。
  final String body;

  static const Frontmatter none = Frontmatter(
    hasFrontmatter: false,
    fields: <String, Object?>{},
    raw: '',
    body: '',
  );

  bool get isEmpty => !hasFrontmatter || fields.isEmpty;

  /// frontmatter + 正文重新拼成完整文件内容。
  String reconstruct(String newRaw, String newBody) {
    final buffer = StringBuffer('---\n');
    var rawText = newRaw;
    if (!rawText.endsWith('\n')) rawText = '$rawText\n';
    buffer.write(rawText);
    buffer.write('---\n');
    if (newBody.isNotEmpty) {
      // 分隔符与正文之间保留一个空行，读起来更像文档
      if (!newBody.startsWith('\n')) buffer.write('\n');
      buffer.write(newBody);
    }
    return buffer.toString();
  }

  /// 取字符串字段。
  String? string(String key) {
    final value = fields[key];
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  /// 取字段并统一成字符串列表（兼容 `tags: a` 与 `tags: [a, b]` 两种写法）。
  List<String> stringList(String key) {
    final value = fields[key];
    return switch (value) {
      null => const <String>[],
      String s => s.trim().isEmpty ? const <String>[] : <String>[s.trim()],
      List<Object?> list => list
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      _ => <String>[value.toString()],
    };
  }

  /// 取日期字段，兼容 `2026-09-09` 与 `2026-09-09T20:50:31Z`。
  DateTime? dateTime(String key) {
    final value = fields[key];
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString().trim());
  }

  /// 语料层规范字段（与知识库蓝图统一，血缘字段先预留）。
  static const List<String> corpusFields = <String>[
    'title',
    'created',
    'updated',
    'tags',
    'source',
    'lineage',
  ];

  /// 生成一份符合语料层规范的缺省 frontmatter（新建笔记时使用）。
  static String defaultTemplate({
    required String title,
    DateTime? now,
  }) {
    final stamp = _isoDate(now ?? DateTime.now());
    return <String>[
      'title: ${_quoteIfNeeded(title)}',
      'created: $stamp',
      'updated: $stamp',
      'tags: []',
      'source: ""',
      '# lineage: 血缘字段预留，与知识库蓝图统一语料层规范对齐（宪章 §7）',
      '# lineage:',
      '#   derived_from: []',
    ].join('\n');
  }

  static String _isoDate(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  static String _quoteIfNeeded(String value) {
    if (value.isEmpty) return '""';
    final needsQuote = RegExp(r'''^[\s]|[\s]$|[:#\[\]{}",&*?|<>=!%@`]''').hasMatch(value);
    if (!needsQuote) return value;
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}

/// frontmatter 读写工具。
class FrontmatterCodec {
  const FrontmatterCodec._();

  /// 分隔符行。
  static final RegExp _fence = RegExp(r'^(---|\.\.\.)\s*$');

  /// 解析 [content] 中的 frontmatter。
  ///
  /// 容忍这几种情况：完全没有 frontmatter、YAML 语法错误（[fields] 退化为空）、
  /// CRLF 行尾、文件开头有空行。永不抛异常——编辑器的容错优先于严格。
  static Frontmatter parse(String content) {
    if (content.isEmpty) {
      return const Frontmatter(
        hasFrontmatter: false,
        fields: <String, Object?>{},
        raw: '',
        body: '',
      );
    }

    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    // 允许 BOM 与开头空行
    var start = 0;
    while (start < lines.length && lines[start].trim().isEmpty) {
      start++;
    }
    if (start >= lines.length || !_isOpeningFence(lines[start])) {
      return Frontmatter(
        hasFrontmatter: false,
        fields: const <String, Object?>{},
        raw: '',
        body: normalized,
      );
    }

    var end = -1;
    for (var i = start + 1; i < lines.length; i++) {
      if (_fence.hasMatch(lines[i])) {
        end = i;
        break;
      }
    }
    if (end == -1) {
      // 未闭合的 frontmatter 视为普通正文，避免"吃掉"用户内容
      return Frontmatter(
        hasFrontmatter: false,
        fields: const <String, Object?>{},
        raw: '',
        body: normalized,
      );
    }

    final raw = lines.sublist(start + 1, end).join('\n');
    var bodyLines = lines.sublist(end + 1);
    // 去掉分隔符后的第一个空行，保持正文干净
    if (bodyLines.isNotEmpty && bodyLines.first.trim().isEmpty) {
      bodyLines = bodyLines.sublist(1);
    }

    Map<String, Object?> fields = const <String, Object?>{};
    try {
      final doc = loadYaml(raw.isEmpty ? '{}' : raw);
      if (doc is YamlMap) {
        fields = _toPlainMap(doc);
      } else if (doc is Map) {
        fields = _toPlainMap(doc);
      }
    } on YamlException {
      // YAML 写坏了也不能让编辑器崩：字段退化为空，raw 仍然保留原样
      fields = const <String, Object?>{};
    }

    return Frontmatter(
      hasFrontmatter: true,
      fields: fields,
      raw: raw,
      body: bodyLines.join('\n'),
    );
  }

  static bool _isOpeningFence(String line) => line.trim() == '---';

  /// YamlMap -> 普通 Map（递归），便于 UI 层安全读取。
  static Map<String, Object?> _toPlainMap(Map<Object?, Object?> source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key?.toString();
      if (key == null) continue;
      result[key] = _plainValue(entry.value);
    }
    return result;
  }

  static Object? _plainValue(Object? value) {
    return switch (value) {
      YamlMap map => _toPlainMap(map),
      YamlList list => list.map(_plainValue).toList(growable: false),
      _ => value,
    };
  }

  /// 用 [updates] 更新 [content] 中的 frontmatter，**保留其它字段与注释**。
  ///
  /// [removeKeys] 中的字段会被删除。frontmatter 不存在时按需创建。
  /// 返回新的完整文件内容；失败时返回原内容（编辑器的容错优先）。
  static String update(
    String content, {
    Map<String, Object?> updates = const <String, Object?>{},
    Set<String> removeKeys = const <String>{},
  }) {
    final parsed = parse(content);
    if (!parsed.hasFrontmatter) {
      if (updates.isEmpty) return parsed.body;
      final fresh = <String, Object?>{...updates};
      final raw = _dumpMap(fresh);
      return Frontmatter.none.reconstruct(raw, parsed.body);
    }

    var raw = parsed.raw;
    try {
      final editor = YamlEditor(raw.isEmpty ? '{}' : raw);
      for (final key in removeKeys) {
        if (updates.containsKey(key)) continue;
        // orElse 必须返回一个 YamlNode，这里用空标量表示"字段不存在"
        final existing = editor.parseAt(
          <String>[key],
          orElse: () => YamlScalar.wrap(null),
        );
        if (existing.value != null) {
          editor.remove(<String>[key]);
        }
      }
      for (final entry in updates.entries) {
        editor.update(<String>[entry.key], entry.value);
      }
      raw = editor.toString();
    } on YamlException {
      // 原始 YAML 有语法错误时退化为整体重写，保证用户至少能存下字段
      raw = _dumpMap(<String, Object?>{...parsed.fields, ...updates});
    } on ArgumentError {
      raw = _dumpMap(<String, Object?>{...parsed.fields, ...updates});
    }

    return parsed.reconstruct(raw, parsed.body);
  }

  /// 保证 [content] 含有 frontmatter；缺失时按语料层规范补齐。
  static String ensureFrontmatter(String content, {String? title}) {
    final parsed = parse(content);
    if (parsed.hasFrontmatter) return content;

    final inferred = title ?? _inferTitle(parsed.body);
    final raw = Frontmatter.defaultTemplate(title: inferred);
    return Frontmatter.none.reconstruct(raw, parsed.body);
  }

  /// 从正文推断标题：第一个 H1，否则第一行非空文本（过长时截断）。
  static String _inferTitle(String body) {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final text = trimmed.startsWith('#')
          ? trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim()
          : trimmed;
      if (text.isEmpty) continue;
      return text.length > 60 ? text.substring(0, 60) : text;
    }
    return '未命名';
  }

  /// 把 Map 序列化成 YAML（只在无法做字段级编辑时使用）。
  static String _dumpMap(Map<String, Object?> values) {
    final buffer = StringBuffer();
    for (final entry in values.entries) {
      final value = entry.value;
      switch (value) {
        case null:
          buffer.writeln('${entry.key}:');
        case List<Object?> list:
          if (list.isEmpty) {
            buffer.writeln('${entry.key}: []');
          } else {
            buffer.writeln('${entry.key}:');
            for (final item in list) {
              buffer.writeln('  - ${_scalar(item)}');
            }
          }
        case Map<Object?, Object?> map:
          buffer.writeln('${entry.key}:');
          for (final sub in map.entries) {
            buffer.writeln('  ${sub.key}: ${_scalar(sub.value)}');
          }
        default:
          buffer.writeln('${entry.key}: ${_scalar(value)}');
      }
    }
    return buffer.toString().trimRight();
  }

  static String _scalar(Object? value) {
    if (value == null) return '';
    if (value is num || value is bool) return value.toString();
    if (value is DateTime) return value.toIso8601String();
    final text = value.toString();
    if (text.isEmpty) return '""';
    final needsQuote = RegExp(r'''[:#\[\]{}",&*?|<>=!%@`]|^\s|\s$''').hasMatch(text);
    if (!needsQuote) return text;
    return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}
