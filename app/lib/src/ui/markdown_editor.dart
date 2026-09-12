import 'package:flutter/material.dart';

import '../state/editor_controller.dart';

/// 源码编辑器：行号栏 + 语法高亮文本域。
///
/// 高亮由 [MarkdownEditingController] 在绘制阶段完成，这里只负责
/// 排版、滚动同步与外观。
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

  /// 行号栏宽度约束：数字位数变化时正文不应左右晃动。
  static const double gutterMinWidth = 46;
  static const double gutterDigitWidth = 8.2;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_syncGutter);
  }

  /// 行号栏跟随正文滚动。
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
              // 搜索跳转需要按行滚动，锚点挂在 EditableText 上
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
              // 源码模式：不做任何输入过滤，Markdown 原样进出
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

/// 行号栏。
///
/// 不参与滚动交互，只被动跟随正文的滚动偏移，避免出现两条滚动条的怪状。
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
