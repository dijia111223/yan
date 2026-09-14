import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_controller.dart';

/// 建议栏当前要显示什么。
enum AiSuggestionPhase {
  /// 不显示
  hidden,

  /// 正在等模型
  thinking,

  /// 有一条建议待采纳
  ready,
}

/// 补全建议的触发与状态。
///
/// 与 [AiController] 分开：controller 管的是"功能能不能用"（开关、模型、会话），
/// 这里管的是"什么时候问、问什么、结果还算不算数"。混在一起会让
/// "用户继续打字"这类交互细节污染模型生命周期。
///
/// 三条时序规则，都是为了让建议**不干扰输入**：
///
/// 1. **防抖**：停止输入 [debounce] 之后才发请求。逐键请求既费电又永远慢半拍。
/// 2. **作废**：文本一变，在途请求的结果立刻作废（靠 [generation] 计数）。
///    否则会出现"建议是基于三段话之前的文本算的"。
/// 3. **取消**：用户继续打字时通知模型停下，别白烧 CPU。
class AiSuggestionController extends ChangeNotifier {
  AiSuggestionController({required AiController ai, this.debounce = const Duration(milliseconds: 600)})
      : _ai = ai;

  final AiController _ai;

  /// 停止输入多久后才请求补全。
  final Duration debounce;

  AiSuggestionPhase _phase = AiSuggestionPhase.hidden;
  String _text = '';
  String _prefix = '';
  Timer? _timer;
  bool _disposed = false;

  /// 请求代数。每次文本变化 +1，用来丢弃过期结果。
  int _generation = 0;

  AiSuggestionPhase get phase => _phase;

  /// 待采纳的建议。仅 [phase] 为 ready 时有效。
  String get suggestion => _phase == AiSuggestionPhase.ready ? _text : '';

  bool get visible => _phase != AiSuggestionPhase.hidden;

  /// 编辑器内容变化时调用。
  void onTextChanged(String text, int cursor) {
    _generation++;
    _timer?.cancel();

    // 取消在途推理：用户还在打字，上一次的结果已经没有意义
    _ai.cancelCompletion();
    _hide();

    if (!_ai.enabled || text.isEmpty || cursor <= 0) return;

    final prefix = completionPrefix(text, cursor);
    if (prefix.isEmpty) return;

    _timer = Timer(debounce, () => _request(text, cursor, _generation));
  }

  Future<void> _request(String text, int cursor, int generation) async {
    if (_disposed) return;
    _phase = AiSuggestionPhase.thinking;
    _notify();

    final result = await _ai.requestCompletion(text, cursor);

    // 过期结果直接丢：期间用户又打了字，或者已经关掉了功能
    if (_disposed || generation != _generation) return;
    if (result.isEmpty) {
      _hide();
      return;
    }

    _text = result;
    _prefix = completionPrefix(text, cursor);
    _phase = AiSuggestionPhase.ready;
    _notify();
  }

  /// 采纳当前建议：调用 [insert] 把建议内容写进文档。
  ///
  /// 返回被采纳的文本（空字符串表示没有可采纳的建议）。
  String accept(void Function(String inserted) insert) {
    final s = _text;
    if (_phase != AiSuggestionPhase.ready || s.isEmpty) return '';
    _dismissInternal();
    insert(s);
    return s;
  }

  /// 忽略当前建议（Esc）。
  void dismiss() {
    if (_phase == AiSuggestionPhase.hidden) return;
    _dismissInternal();
  }

  /// 文档切换时清掉建议，避免把上一篇的建议插到这一篇里。
  void reset() {
    _generation++;
    _timer?.cancel();
    _ai.cancelCompletion();
    _dismissInternal();
  }

  void _dismissInternal() {
    _timer?.cancel();
    _text = '';
    _prefix = '';
    _phase = AiSuggestionPhase.hidden;
    _notify();
  }

  void _hide() {
    if (_phase == AiSuggestionPhase.hidden && _text.isEmpty) return;
    _text = '';
    _prefix = '';
    _phase = AiSuggestionPhase.hidden;
    _notify();
  }

  /// 建议所属的前缀，供调试与界面提示使用。
  String get suggestionContext => _prefix;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
