import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// frontmatter 解析结果。回写必须无损，未识别的字段、注释、字段顺序都要保留。
class Frontmatter {
  const Frontmatter({
    required this.hasFrontmatter,
    required this.fields,
    required this.raw,
    required this.body,
  });

  final bool hasFrontmatter;

  final Map<String, Object?> fields;

  final String raw;

  final String body;

  static const Frontmatter none = Frontmatter(
    hasFrontmatter: false,
    fields: <String, Object?>{},
    raw: '',
    body: '',
  );

  bool get isEmpty => !hasFrontmatter || fields.isEmpty;

  /// frontmatter + 正文拼成完整文件内容。
  String reconstruct(String newRaw, String newBody) {
    final buffer = StringBuffer('---\n');
    var rawText = newRaw;
    if (!rawText.endsWith('\n')) rawText = '$rawText\n';
    buffer.write(rawText);
    buffer.write('---\n');
    if (newBody.isNotEmpty) {
      if (!newBody.startsWith('\n')) buffer.write('\n');
      buffer.write(newBody);
    }
    return buffer.toString();
  }

  String? string(String key) {
    final value = fields[key];
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  /// 兼容 `tags: a` 与 `tags: [a, b]` 两种写法。
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

  /// 语料层规范字段。
  static const List<String> corpusFields = <String>[
    'title',
    'created',
    'updated',
    'tags',
    'source',
    'lineage',
  ];

  /// 缺省 frontmatter，新建笔记时用。
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

  static final RegExp _fence = RegExp(r'^(---|\.\.\.)\s*$');

  /// 解析 [content] 中的 frontmatter；永不抛异常，容错优先。
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

  /// 更新 [content] 中的 frontmatter，保留其它字段与注释。
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
      raw = _dumpMap(<String, Object?>{...parsed.fields, ...updates});
    } on ArgumentError {
      // yaml_edit 对非法键路径抛 ArgumentError，同样退化为整体重写
      raw = _dumpMap(<String, Object?>{...parsed.fields, ...updates});
    }

    return parsed.reconstruct(raw, parsed.body);
  }

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

  /// 把 Map 序列化成 YAML。
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
