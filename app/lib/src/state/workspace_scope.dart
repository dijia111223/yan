import 'package:flutter/material.dart';

import '../state/workspace.dart';

class WorkspaceScope extends InheritedNotifier<WorkspaceState> {
  const WorkspaceScope({
    super.key,
    required WorkspaceState state,
    required super.child,
  }) : super(notifier: state);

  static WorkspaceState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WorkspaceScope>();
    assert(scope != null, 'WorkspaceScope 未找到：请把界面放在 WorkspaceScope 之内');
    return scope!.notifier!;
  }
}
