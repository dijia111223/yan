import 'package:flutter/services.dart';

import 'markdown_edit_assist.dart';

/// 把 [applyEdit] 接到 `TextField` 上。
///
/// 只处理**不需要用户确认**的编辑（续列表、补围栏、配对符号、Tab 跳格）：
/// 这些是编辑器的"手感"，不是 AI 建议，所以直接改文本而不弹建议。
///
/// 输入法组合期间（中文拼音未上屏）一律不介入 —— 那时候改文本会打断输入法。
class MarkdownEditAssistFormatter extends TextInputFormatter {
  const MarkdownEditAssistFormatter({this.enabled = true});

  final bool enabled;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!enabled) return newValue;

    // 组合中不做任何事，交给输入法
    if (newValue.composing.isValid || oldValue.composing.isValid) {
      return newValue;
    }

    // 只在"插入"型编辑上动手：删除/替换交给默认逻辑
    if (newValue.text.length < oldValue.text.length) return newValue;

    final oldText = oldValue.text;
    final newText = newValue.text;

    // 关键：applyEdit 是按**旧文本**计算下标的，所以必须传旧值的选区。
    // 传新值的选区会越界 —— 新文本比旧文本长，下标落在旧文本之外。
    final sel = TextSelectionRange(
      oldValue.selection.start,
      oldValue.selection.end,
    );

    // 判断这次编辑是什么
    final EditKind kind;
    String inserted = '';
    if (newText == '$oldText\n' ||
        (newText.length == oldText.length + 1 && newText.contains('\n'))) {
      kind = EditKind.newline;
    } else if (newText.length == oldText.length + 1) {
      kind = EditKind.insert;
      inserted = _diff(oldText, newText);
      if (inserted == '\n') return newValue;
    } else {
      return newValue;
    }

    final result = applyEdit(
      text: oldText,
      selection: sel,
      kind: kind,
      inserted: inserted,
    );
    if (result?.text == null) return newValue;

    return TextEditingValue(
      text: result!.text!,
      selection: TextSelection(
        baseOffset: result.selection!.start,
        extentOffset: result.selection!.end,
      ),
      composing: TextRange.empty,
    );
  }

  /// 找出新文本相对旧文本多出来的那一个字符。
  static String _diff(String oldText, String newText) {
    var i = 0;
    while (i < oldText.length && i < newText.length && oldText[i] == newText[i]) {
      i++;
    }
    return newText.substring(i, i + 1);
  }
}
