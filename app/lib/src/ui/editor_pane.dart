import 'package:flutter/material.dart';

import '../state/workspace.dart';
import 'markdown_editor.dart';

/// 编辑区：标签页 + 格式工具条 + 源码编辑器。
class EditorPane extends StatelessWidget {
  const EditorPane({super.key, required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = state.activeDocument;
    final md = state.markdownTheme;

    return Column(
      children: <Widget>[
        if (state.documents.isNotEmpty)
          _TabStrip(state: state),
        if (doc != null)
          _FormatBar(state: state),
        Expanded(
          child: doc == null
              ? _EmptyEditor(state: state)
              : MarkdownEditor(
                  key: ValueKey<String>(doc.path),
                  controller: doc.controller,
                  textStyle: md.body.copyWith(fontSize: 15.5, height: 1.62),
                  // 行号栏字号小一档，行高按比例缩放以与正文对齐
                  gutterStyle: md.punctuation.copyWith(
                    fontSize: 12,
                    height: 1.62 * 15.5 / 12,
                  ),
                  backgroundColor: scheme.surface,
                  gutterBackgroundColor: scheme.surfaceContainerLow,
                  dividerColor: scheme.outlineVariant,
                  selectionColor: scheme.primary,
                ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: state.documents.length,
        itemBuilder: (context, index) {
          final doc = state.documents[index];
          final active = index == state.activeIndex;
          return InkWell(
            onTap: () => state.activate(index),
            child: Container(
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: active ? scheme.surface : null,
                border: Border(
                  right: BorderSide(color: scheme.outlineVariant),
                  bottom: BorderSide(
                    color: active ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (doc.isDirty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.circle, size: 7, color: scheme.primary),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      doc.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '关闭标签 (Ctrl+W)',
                    onPressed: () => state.closeDocument(index),
                    visualDensity: VisualDensity.compact,
                    iconSize: 13,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 格式工具条：把常用 Markdown 语法做成按钮，插入到光标处。
class _FormatBar extends StatelessWidget {
  const _FormatBar({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: <Widget>[
          _btn(context, Icons.title_rounded, '一级标题', '# '),
          _btn(context, Icons.format_bold_rounded, '粗体  **粗体**', '**粗体**'),
          _btn(context, Icons.format_italic_rounded, '斜体  *斜体*', '*斜体*'),
          _btn(context, Icons.strikethrough_s_rounded, '删除线  ~~文本~~', '~~文本~~'),
          _btn(context, Icons.code_rounded, '行内代码  `code`', '`code`'),
          _btn(context, Icons.data_object_rounded, '代码块', '\n```dart\n\n```\n'),
          _btn(context, Icons.link_rounded, '链接', '[标题](https://)'),
          _btn(context, Icons.image_outlined, '图片', '![说明](图片路径)'),
          _btn(context, Icons.format_quote_rounded, '引用', '> '),
          _btn(context, Icons.checklist_rounded, '任务列表', '- [ ] 待办\n'),
          _btn(context, Icons.table_chart_outlined, '表格', _tableSnippet),
          _btn(context, Icons.functions_rounded, '行内公式', r'$E = mc^2$'),
          _btn(
            context,
            Icons.integration_instructions_rounded,
            '行间公式',
            '\n${r'$$'}\n${r'\int_0^1 x^2\,dx'}\n${r'$$'}\n',
          ),
          _btn(context, Icons.horizontal_rule_rounded, '分隔线', '\n---\n'),
        ],
      ),
    );
  }

  static const String _tableSnippet =
      '\n| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |\n';

  Widget _btn(BuildContext context, IconData icon, String tooltip, String snippet) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
      icon: Icon(icon),
      onPressed: () => state.insertAtCursor(snippet),
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final library = state.library;

    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.edit_note_rounded, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text('从左侧选择一篇笔记开始编辑', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            library == null ? '先打开一个文件夹作为库' : library.rootPath,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => state.createNote(),
                icon: const Icon(Icons.note_add_outlined, size: 16),
                label: const Text('新建笔记'),
              ),
              OutlinedButton.icon(
                onPressed: () => state.createFolder(),
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('新建文件夹'),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _ShortcutHints(),
        ],
      ),
    );
  }
}

class _ShortcutHints extends StatelessWidget {
  const _ShortcutHints();

  static const List<(String, String)> _hints = <(String, String)>[
    ('Ctrl+O', '打开文件夹作为库'),
    ('Ctrl+N', '新建笔记'),
    ('Ctrl+S', '保存'),
    ('Ctrl+F', '全文搜索'),
    ('Ctrl+B', '文件树'),
    ('Ctrl+P', '预览'),
    ('Ctrl+E', 'frontmatter 面板'),
    ('Ctrl+W', '关闭标签'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final (key, label) in _hints)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    key,
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 5),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}
