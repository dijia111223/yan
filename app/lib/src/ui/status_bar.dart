import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../state/workspace.dart';

/// 状态栏：光标位置、字数、保存状态与提示。
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = state.activeDocument;
    final style = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          if (doc == null)
            Text('未打开文件', style: style)
          else ...<Widget>[
            _item(
              style,
              doc.isDirty ? Icons.circle : Icons.check_circle_outline,
              doc.isDirty ? '未保存' : '已保存',
              color: doc.isDirty ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Text('行 ${doc.cursorLine}，列 ${doc.cursorColumn}', style: style),
            const SizedBox(width: 14),
            Text('${doc.stats.words} 字', style: style),
            const SizedBox(width: 10),
            Text('${doc.stats.characters} 字符', style: style),
            const SizedBox(width: 10),
            Text('${doc.stats.lines} 行', style: style),
            const SizedBox(width: 14),
            Text(p.extension(doc.name).replaceFirst('.', '').toUpperCase(), style: style),
          ],
          const Spacer(),
          if (state.toast != null)
            Flexible(
              child: Text(
                state.toast!,
                style: style?.copyWith(color: scheme.error),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else if (state.library != null)
            Text('${state.library!.name} · 纯文件库', style: style),
          const SizedBox(width: 12),
          Text('v0.1.0', style: style),
        ],
      ),
    );
  }

  Widget _item(TextStyle? style, IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
  }
}
