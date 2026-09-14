import 'package:flutter/material.dart';

import 'ai_controller.dart';

/// 把 [AiController] 注入子树。
class AiScope extends InheritedNotifier<AiController> {
  const AiScope({
    super.key,
    required AiController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 取控制器；不在 [AiScope] 之内时返回 null。
  ///
  /// 返回可空而不是断言：端侧补全是可选能力，缺少它时界面应当安静地少一块，
  /// 而不是把整个应用崩掉。
  static AiController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AiScope>()?.notifier;
  }
}
