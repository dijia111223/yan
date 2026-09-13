/// Markdown 编辑增强 —— 纯函数，不依赖 Flutter，便于单测覆盖边界。
///
/// 这些都是**确定性**行为，不是 AI：回车续列表、围栏自动闭合、成对符号自动配对、
/// 表格 Tab 跳格。确定性实现零延迟、零内存，而且比语言模型更准
/// （模型会凭空多写格式符号）。
///
/// 设计原则：**任何拿不准的情况都不动文本**。编辑器悄悄改用户内容比不帮忙更糟。
library;

/// 一次编辑请求。
enum EditKind { insert, newline, backspace, tab }

/// 编辑结果；[text] 为 null 表示无需改动，交给默认行为处理。
class EditResult {
  const EditResult({this.text, this.selection});

  final String? text;
  final TextSelectionRange? selection;
}

/// 与 Flutter 的 TextSelection 对应，避免本文件依赖 Flutter。
class TextSelectionRange {
  const TextSelectionRange(this.start, this.end);

  const TextSelectionRange.collapsed(int offset) : start = offset, end = offset;

  final int start;
  final int end;

  bool get isCollapsed => start == end;

  @override
  bool operator ==(Object other) =>
      other is TextSelectionRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start,$end)';
}

/// 成对符号：左 -> 右。
const Map<String, String> _pairs = <String, String>{
  '*': '*',
  '_': '_',
  '`': '`',
  '~': '~',
  '(': ')',
  '[': ']',
  '"': '"',
  "'": "'",
};

/// 需要成对补齐的字符（连续两个才构成 Markdown 语义，交给 [_autoPair] 判断）。
const Set<String> _pairable = <String>{'*', '_', '`', '~'};

const String _fence = '```';

/// 行首列表标记：`- `、`* `、`+ `、`1. `、`1) `、`- [ ] `、`- [x] `。
final RegExp _listMarker = RegExp(r'^(\s*)([-*+]|\d+[.)])(\s+)(\[[ xX]\]\s+)?');

/// 处理一次编辑。[kind] 为 insert 时用 [inserted]。
///
/// 返回 null 表示"不介入"，让编辑器走默认逻辑。
EditResult? applyEdit({
  required String text,
  required TextSelectionRange selection,
  EditKind kind = EditKind.insert,
  String inserted = '',
}) {
  switch (kind) {
    case EditKind.newline:
      return _onNewline(text, selection);
    case EditKind.backspace:
      return _onBackspace(text, selection);
    case EditKind.tab:
      return _onTab(text, selection);
    case EditKind.insert:
      return _onInsert(text, selection, inserted);
  }
}

// ---------------------------------------------------------------- 回车

EditResult? _onNewline(String text, TextSelectionRange sel) {
  final lineStart = _lineStart(text, sel.start);
  final lineEnd = _lineEnd(text, sel.start);
  final line = text.substring(lineStart, lineEnd);
  final marker = _listMarker.firstMatch(line);
  if (marker == null) return null;

  final indent = marker.group(1)!;
  final bullet = marker.group(2)!;
  final space = marker.group(3)!;
  final checkbox = marker.group(4);

  // 光标前只有标记本身（空条目）→ 再按回车就退出列表
  final contentStart = lineStart + marker.end;
  final beforeCursor = text.substring(contentStart, sel.start);
  if (beforeCursor.trim().isEmpty && sel.isCollapsed) {
    return EditResult(
      text: text.replaceRange(lineStart, sel.start, ''),
      selection: TextSelectionRange.collapsed(lineStart),
    );
  }

  // 任务列表续行时回到未勾选状态
  final nextMarker = checkbox != null
      ? '$indent$bullet$space[ ] '
      : '$indent${_nextBullet(bullet)}$space';

  final insertText = '\n$nextMarker';
  final newText = text.replaceRange(sel.start, sel.end, insertText);
  return EditResult(
    text: newText,
    selection: TextSelectionRange.collapsed(sel.start + insertText.length),
  );
}

/// 有序列表递增；无序列表保持原符号。
String _nextBullet(String bullet) {
  final m = RegExp(r'^(\d+)([.)])$').firstMatch(bullet);
  if (m == null) return bullet;
  final n = int.tryParse(m.group(1)!);
  if (n == null) return bullet;
  return '${n + 1}${m.group(2)}';
}

// ---------------------------------------------------------------- 输入

EditResult? _onInsert(String text, TextSelectionRange sel, String inserted) {
  if (inserted.isEmpty) return null;

  // 有选区时输入成对符号 → 包裹选区，而不是替换掉
  if (!sel.isCollapsed && inserted.length == 1 && _pairs.containsKey(inserted)) {
    final close = _pairs[inserted]!;
    final selected = text.substring(sel.start, sel.end);
    // 只对 Markdown 有意义的成对符号做包裹，括号/引号交给编辑器默认行为
    if (!_pairable.contains(inserted)) return null;
    final wrapped = '$inserted$selected$close';
    return EditResult(
      text: text.replaceRange(sel.start, sel.end, wrapped),
      selection: TextSelectionRange(sel.start + inserted.length,
          sel.start + inserted.length + selected.length),
    );
  }

  if (!sel.isCollapsed || inserted.length != 1) return null;

  // 围栏：行首反引号 → 直接给出闭合围栏
  if (inserted == '`' && _isFenceStart(text, sel.start)) {
    return _autoCloseFence(
        text, sel, text.substring(_lineStart(text, sel.start), sel.start));
  }

  // 光标右侧就是同一个符号 → 跳过，不要重复插入（常见于连续按两次 `*`）
  if (sel.start < text.length && text[sel.start] == inserted) {
    final next = sel.start + 1;
    // 成对符号跳过时，若再右侧还是同一个符号就整对跳过（处理 ** 与 __）
    final pairSkip = next < text.length && text[next] == inserted ? next + 1 : next;
    return EditResult(
      text: text,
      selection: TextSelectionRange.collapsed(pairSkip),
    );
  }

  if (!_pairable.contains(inserted)) return null;

  // 自动配对：奇数个已存在时不补（避免把 `**bold**` 弄乱）
  final lineStart = _lineStart(text, sel.start);
  final before = text.substring(lineStart, sel.start);
  final count = _countChar(before, inserted);
  if (count.isOdd) return null;

  final newText = text.replaceRange(sel.start, sel.start, inserted + inserted);
  return EditResult(
    text: newText,
    selection: TextSelectionRange.collapsed(sel.start + 1),
  );
}

/// 判定这次反引号输入是否正在起一个围栏（行首、且行首到光标只有空白）。
bool _isFenceStart(String text, int offset) {
  final lineStart = _lineStart(text, offset);
  final before = text.substring(lineStart, offset);
  return before.trim().isEmpty;
}

EditResult? _autoCloseFence(String text, TextSelectionRange sel, String before) {
  // 只在行首（光标前整行都是空白）且还没有闭合围栏时补
  if (before.trim().isNotEmpty) return null;

  final rest = text.substring(sel.start);
  // 文档后面已经有闭合围栏就不重复补
  if (rest.contains(_fence)) return null;

  final insertText = '$_fence\n\n$_fence';
  final newText = text.replaceRange(sel.start, sel.end, insertText);
  // 光标落在两个围栏之间的空行上
  return EditResult(
    text: newText,
    selection: TextSelectionRange.collapsed(sel.start + _fence.length + 1),
  );
}

// ---------------------------------------------------------------- 退格

EditResult? _onBackspace(String text, TextSelectionRange sel) {
  if (!sel.isCollapsed || sel.start == 0) return null;

  // 成对符号之间退格 → 一次删掉两侧（自动补出来的那一对）
  if (sel.start < text.length) {
    final left = text[sel.start - 1];
    final right = text[sel.start];
    if (left == right && _pairs.containsKey(left)) {
      return EditResult(
        text: text.replaceRange(sel.start - 1, sel.start + 1, ''),
        selection: TextSelectionRange.collapsed(sel.start - 1),
      );
    }
  }

  // 光标前是列表标记留下的整段缩进+标记 → 一次删掉，而不是逐字符
  final lineStart = _lineStart(text, sel.start);
  final line = text.substring(lineStart, sel.start);
  final marker = _listMarker.firstMatch(line);
  if (marker != null && marker.end == line.length) {
    return EditResult(
      text: text.replaceRange(lineStart, sel.start, ''),
      selection: TextSelectionRange.collapsed(lineStart),
    );
  }

  return null;
}

// ---------------------------------------------------------------- Tab

EditResult? _onTab(String text, TextSelectionRange sel) {
  final lineStart = _lineStart(text, sel.start);
  final lineEnd = _lineEnd(text, sel.start);
  final line = text.substring(lineStart, lineEnd);

  // 表格行：跳到下一个单元格
  if (line.trimLeft().startsWith('|')) {
    final rel = sel.start - lineStart;
    final next = line.indexOf('|', rel + 1);
    if (next >= 0) {
      return EditResult(
        text: text,
        selection: TextSelectionRange.collapsed(lineStart + next + 1),
      );
    }
  }

  // 列表项：缩进两格
  final marker = _listMarker.firstMatch(line);
  if (marker != null) {
    final newLine = '  $line';
    return EditResult(
      text: text.replaceRange(lineStart, lineEnd, newLine),
      selection: TextSelectionRange.collapsed(sel.start + 2),
    );
  }

  return null;
}

// ---------------------------------------------------------------- 工具

int _lineStart(String text, int offset) {
  // offset 可能为 0（光标在文首）。lastIndexOf 的 start 参数不能为负，
  // 否则抛 RangeError —— 这是很容易漏的边界。
  if (offset <= 0) return 0;
  final from = offset > text.length ? text.length : offset;
  final i = text.lastIndexOf('\n', from - 1);
  return i < 0 ? 0 : i + 1;
}

int _lineEnd(String text, int offset) {
  if (offset >= text.length) return text.length;
  final from = offset < 0 ? 0 : offset;
  final i = text.indexOf('\n', from);
  return i < 0 ? text.length : i;
}

int _countChar(String s, String ch) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ch) n++;
  }
  return n;
}
