import 'package:flutter/material.dart';

import '../core/markdown_highlighter.dart';
import '../core/markdown_theme.dart';

/// 编辑器文本控制器：把 Markdown 源码渲染成带语法高亮的富文本。
///
/// 这是"源码编辑 + 语法高亮"的核心——`EditableText` 允许我们完全接管
/// 文本的绘制，所以高亮不需要任何第三方组件。
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({required MarkdownTheme theme, String? text})
      : _theme = theme,
        _highlighter = MarkdownHighlighter(theme),
        super(text: text);

  MarkdownTheme _theme;
  MarkdownHighlighter _highlighter;

  /// 光标位置变化时通知（用于状态栏显示行列号）。
  final ValueNotifier<TextSelection> selectionNotifier =
      ValueNotifier<TextSelection>(const TextSelection.collapsed(offset: 0));

  MarkdownTheme get theme => _theme;

  set theme(MarkdownTheme value) {
    if (identical(value, _theme) || value == _theme) return;
    _theme = value;
    _highlighter = MarkdownHighlighter(value);
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = newValue;
    if (selectionNotifier.value != newValue.selection) {
      selectionNotifier.value = newValue.selection;
    }
  }

  /// 搜索命中跳转用的锚点。
  ///
  /// 由 [MarkdownEditor] 挂到 `TextField` 上。[TextEditingController] 没有
  /// "滚动到某一行"的公开 API，而 `EditableTextState` 实现了 `ScrollableState`，
  /// 因此这里通过它调用 `bringIntoView` 把光标位置滚进视口。
  final GlobalKey<EditableTextState> editableKey = GlobalKey<EditableTextState>();

  /// 把 [offset] 对应的光标位置滚进可见区域。
  void _bringOffsetIntoView(int offset) {
    final state = editableKey.currentState;
    if (state == null) return;
    try {
      // EditableTextState.bringIntoView 会把光标位置滚进视口
      state.bringIntoView(TextPosition(offset: offset));
    } on Object {
      // 布局尚未完成或实现变更时忽略——跳转失败不该影响编辑
    }
  }

  /// 跳到指定行（1 基）并把光标放到行首（或指定列）。
  ///
  /// 正文**不会被修改**：只移动选区，再让视口滚到光标处。
  void jumpToLine(int line, {int? column}) {
    final text = this.text;
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final targetLine = line.clamp(1, lines.length);
    var offset = 0;
    for (var i = 0; i < targetLine - 1; i++) {
      offset += lines[i].length + 1;
    }
    final lineLength = lines[targetLine - 1].length;
    final columnOffset = column == null ? 0 : (column - 1).clamp(0, lineLength);
    final target = (offset + columnOffset).clamp(0, text.length);

    final position = TextSelection.collapsed(offset: target);
    if (value.selection == position) {
      // 选区没变时 TextField 不会重绘，直接滚过去
      _bringOffsetIntoView(target);
      return;
    }

    // 只移动选区：正文一个字符都不动
    value = TextEditingValue(
      text: text,
      selection: position,
      composing: TextRange.empty,
    );
    // 等一帧，让光标位置先反映到布局上再滚动。
    // 纯 Dart 环境（如单元测试）可能没有绑定，这里做保护，跳转失败不影响编辑。
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bringOffsetIntoView(target));
    } on Object {
      // 无 WidgetsBinding 时忽略
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = value.composing;
    final base = style ?? _theme.body;
    // TextSpan 没有 copyWith，用一层外层 span 承载基础样式即可
    TextSpan styled(int start, int end) => TextSpan(
          style: base,
          children: <TextSpan>[_highlighter.highlight(text, start: start, end: end)],
        );

    // 输入法候选区间需要独立下划线，此时分段处理，避免破坏 IME 体验
    if (withComposing && composing.isValid && !composing.isCollapsed) {
      return TextSpan(
        style: base,
        children: <TextSpan>[
          styled(0, composing.start),
          TextSpan(
            text: text.substring(composing.start, composing.end),
            style: base.copyWith(decoration: TextDecoration.underline),
          ),
          styled(composing.end, text.length),
        ],
      );
    }

    return styled(0, text.length);
  }

  @override
  void dispose() {
    selectionNotifier.dispose();
    super.dispose();
  }
}

/// 文本统计。
class TextStats {
  const TextStats({
    required this.characters,
    required this.words,
    required this.lines,
    required this.cjkCharacters,
  });

  final int characters;
  final int words;
  final int lines;

  /// 中日韩表意文字数量——中英混排时比"词数"更有参考价值。
  final int cjkCharacters;

  static const TextStats empty =
      TextStats(characters: 0, words: 0, lines: 0, cjkCharacters: 0);

  /// 统计一段文本。CJK 逐字计数，拉丁文按空白分词。
  static TextStats of(String text) {
    if (text.isEmpty) return empty;
    final cjk = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]');
    final cjkCount = cjk.allMatches(text).length;
    final cjkStripped = text.replaceAll(cjk, ' ');
    final latinWords =
        RegExp(r"[A-Za-z0-9_'’-]+").allMatches(cjkStripped).length;
    return TextStats(
      characters: text.runes.length,
      words: cjkCount + latinWords,
      lines: '\n'.allMatches(text).length + 1,
      cjkCharacters: cjkCount,
    );
  }
}
