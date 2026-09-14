import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/ai_suggestion.dart';

/// 补全建议栏。挂在编辑器下方。
///
/// 为什么不做成"光标处的灰色幽灵文字"：那要精确计算光标在视口里的位置，
/// 还要处理滚动、换行、裁剪，任何一处算错都会让文字错位到别处。
/// 底栏没有这些问题，而且能放得下"采纳/忽略"的操作提示。
class AiSuggestionBar extends StatelessWidget {
  const AiSuggestionBar({
    super.key,
    required this.controller,
    required this.onAccept,
  });

  final AiSuggestionController controller;

  /// 采纳被点击时调用，参数是建议文本。
  final void Function(String suggestion) onAccept;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.visible) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final thinking = controller.phase == AiSuggestionPhase.thinking;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: thinking
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(Icons.auto_awesome, size: 13, color: scheme.primary),
              ),
              Expanded(
                child: thinking
                    ? Text(
                        '正在想…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : SelectableText(
                        controller.suggestion,
                        style: theme.textTheme.bodySmall,
                      ),
              ),
              if (!thinking) ...<Widget>[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => onAccept(controller.suggestion),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text('采纳 Tab'),
                ),
                IconButton(
                  tooltip: '忽略 Esc',
                  onPressed: controller.dismiss,
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 采纳建议的意图。
class _AcceptSuggestionIntent extends Intent {
  const _AcceptSuggestionIntent();
}

/// 把 Tab/Esc 绑定到建议操作上。
///
/// 用 `Shortcuts` + 自定义 `Intent` 而不是 `CallbackShortcuts`：
/// 后者会**同时**触发快捷键和默认处理，Tab 依然会把制表符插进文本里。
/// 前者只派发我们的 Intent，默认行为不会执行。
///
/// 只在**真的有建议**时注册 —— 否则会把编辑器里正常的 Tab 吃掉。
/// 漏了这个区分，表现是"Tab 突然不能用了"，且只在没有建议时出现。
class AiSuggestionShortcuts extends StatelessWidget {
  const AiSuggestionShortcuts({
    super.key,
    required this.controller,
    required this.onAccept,
    required this.child,
  });

  final AiSuggestionController controller;
  final VoidCallback onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (controller.phase != AiSuggestionPhase.ready) {
          return child!;
        }
        return Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.tab):
                const _AcceptSuggestionIntent(),
            const SingleActivator(LogicalKeyboardKey.escape):
                const DismissSuggestionIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _AcceptSuggestionIntent: CallbackAction<_AcceptSuggestionIntent>(
                onInvoke: (_) {
                  onAccept();
                  return null;
                },
              ),
              DismissSuggestionIntent: CallbackAction<DismissSuggestionIntent>(
                onInvoke: (_) {
                  controller.dismiss();
                  return null;
                },
              ),
            },
            // Shortcuts 默认只对**有焦点**的子树生效，而焦点在编辑器的
            // TextField 里、不在这一层。autofocus 让这一层进入焦点链，
            // 否则快捷键永远不会被派发（实测：Tab 毫无反应）。
            child: Focus(autofocus: true, child: child!),
          ),
        );
      },
      child: child,
    );
  }
}

/// 忽略建议的意图。
class DismissSuggestionIntent extends Intent {
  const DismissSuggestionIntent();
}
