import 'package:flutter/material.dart';

import '../core/markdown_highlighter.dart';
import '../core/markdown_theme.dart';

/// 把 Markdown 源码渲染成带语法高亮的富文本。
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({required MarkdownTheme theme, String? text})
      : _theme = theme,
        _highlighter = MarkdownHighlighter(theme),
        super(text: text);

  MarkdownTheme _theme;
  MarkdownHighlighter _highlighter;

  /// 选区变化通知，状态栏用它显示行列号。
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

  /// 由 [MarkdownEditor] 挂到 `TextField`：bringIntoView 要拿它取 state，
  /// 纯 Dart 环境下可能为 null。
  final GlobalKey<EditableTextState> editableKey = GlobalKey<EditableTextState>();

  void _bringOffsetIntoView(int offset) {
    final state = editableKey.currentState;
    if (state == null) return;
    try {
      state.bringIntoView(TextPosition(offset: offset));
    } on Object {
      // 布局未完成或实现变更时忽略，跳转失败不该影响编辑
    }
  }

  /// 跳到指定行（1 基），只动选区，不改正文。
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
      // 选区没变 TextField 不重绘，得自己滚
      _bringOffsetIntoView(target);
      return;
    }

    value = TextEditingValue(
      text: text,
      selection: position,
      composing: TextRange.empty,
    );
    // 等一帧让布局反映光标位置；纯 Dart 环境没有 binding，要保护。
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bringOffsetIntoView(target));
    } on Object {
      // 没有 WidgetsBinding 时忽略
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
    TextSpan styled(int start, int end) => TextSpan(
          style: base,
          children: <TextSpan>[_highlighter.highlight(text, start: start, end: end)],
        );

    // 输入法候选区间要独立下划线，分段渲染
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

/// 正文统计。[words] 里汉字按字计、拉丁文按词计。
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

  final int cjkCharacters;

  static const TextStats empty =
      TextStats(characters: 0, words: 0, lines: 0, cjkCharacters: 0);

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
