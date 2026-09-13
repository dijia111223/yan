import 'package:flutter/material.dart';

import '../state/editor_controller.dart';

/// 源码编辑器：行号栏 + 语法高亮文本域。
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.textStyle,
    required this.gutterStyle,
    required this.backgroundColor,
    required this.gutterBackgroundColor,
    required this.dividerColor,
    required this.selectionColor,
    this.showLineNumbers = true,
    this.padding = const EdgeInsets.fromLTRB(10, 16, 28, 120),
  });

  final MarkdownEditingController controller;
  final TextStyle textStyle;
  final TextStyle gutterStyle;
  final Color backgroundColor;
  final Color gutterBackgroundColor;
  final Color dividerColor;
  final Color selectionColor;
  final bool showLineNumbers;
  final EdgeInsets padding;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _gutter = ScrollController();
  bool _syncing = false;

  static const double gutterMinWidth = 46;
  static const double gutterDigitWidth = 8.2;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_syncGutter);
  }

  void _syncGutter() {
    if (_syncing || !_gutter.hasClients) return;
    _syncing = true;
    final target = _vertical.offset.clamp(
      _gutter.position.minScrollExtent,
      _gutter.position.maxScrollExtent,
    );
    if ((_gutter.offset - target).abs() > 0.5) {
      _gutter.jumpTo(target);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _vertical.removeListener(_syncGutter);
    _vertical.dispose();
    _gutter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.showLineNumbers) ...<Widget>[
            _LineNumberGutter(
              controller: widget.controller,
              scrollController: _gutter,
              style: widget.gutterStyle,
              backgroundColor: widget.gutterBackgroundColor,
              padding: EdgeInsets.only(
                top: widget.padding.top,
                bottom: widget.padding.bottom,
                right: 10,
                left: 12,
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: widget.dividerColor),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              // 搜索跳转按行滚动，锚点挂在这个 key 上
              key: widget.controller.editableKey,
              scrollController: _vertical,
              maxLines: null,
              expands: false,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              style: widget.textStyle,
              cursorColor: widget.selectionColor,
              cursorWidth: 2,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              autofocus: false,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                contentPadding: widget.padding,
                hintText: null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 行号栏被动跟随正文滚动偏移，自身不参与滚动交互。
class _LineNumberGutter extends StatelessWidget {
  const _LineNumberGutter({
    required this.controller,
    required this.scrollController,
    required this.style,
    required this.backgroundColor,
    required this.padding,
  });

  final MarkdownEditingController controller;
  final ScrollController scrollController;
  final TextStyle style;
  final Color backgroundColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final lineCount = _countLines(value.text);
        final digits = lineCount.toString().length;
        final width = (_MarkdownEditorState.gutterDigitWidth * digits + 30)
            .clamp(_MarkdownEditorState.gutterMinWidth, 80.0);
        return Container(
          width: width,
          color: backgroundColor,
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (var i = 1; i <= lineCount; i++)
                  Text('$i', style: style, textAlign: TextAlign.right),
              ],
            ),
          ),
        );
      },
    );
  }

  static int _countLines(String text) {
    if (text.isEmpty) return 1;
    var count = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }
}
