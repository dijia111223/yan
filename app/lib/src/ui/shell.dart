import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../state/workspace.dart';
import '../state/workspace_scope.dart';
import 'editor_pane.dart';
import 'file_tree.dart';
import 'frontmatter_panel.dart';
import 'markdown_preview.dart';
import 'platform_file_picker.dart';
import 'search_panel.dart';
import 'status_bar.dart';
import 'welcome_view.dart';

/// 主界面：库侧栏 / 编辑器 / 预览 三栏 + 状态栏。
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  double _sidebarWidth = 248;

  /// 预览栏默认宽度：再窄表格 / 公式 / 代码块就要横向滚动。
  double _previewWidth = 620;
  bool _searchOpen = false;

  void _toggleSearch() => setState(() => _searchOpen = !_searchOpen);

  @override
  Widget build(BuildContext context) {
    final state = WorkspaceScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions(state),
        child: Focus(
          autofocus: true,
          child: Scaffold(            body: Column(
              children: <Widget>[
                _TopBar(
                  state: state,
                  searchOpen: _searchOpen,
                  onToggleSearch: _toggleSearch,
                ),
                if (_searchOpen)
                  SearchPanel(state: state, onClose: () => setState(() => _searchOpen = false)),
                Expanded(
                  child: !state.hasLibrary
                      ? const WelcomeView()
                      : Row(
                          children: <Widget>[
                            if (state.showSidebar) ...<Widget>[
                              SizedBox(
                                width: _sidebarWidth,
                                child: FileTree(state: state),
                              ),
                              _Splitter(
                                onDrag: (delta) => setState(() {
                                  _sidebarWidth = (_sidebarWidth + delta).clamp(170.0, 460.0);
                                }),
                              ),
                            ] else
                              _EdgeToggle(
                                icon: Icons.chevron_right_rounded,
                                tooltip: '显示文件树 (Ctrl+B)',
                                onPressed: state.toggleSidebar,
                              ),
                            Expanded(child: EditorPane(state: state)),
                            if (state.showPreview) ...<Widget>[
                              _Splitter(
                                onDrag: (delta) => setState(() {
                                  _previewWidth = (_previewWidth - delta).clamp(240.0, 900.0);
                                }),
                              ),
                              SizedBox(
                                width: _previewWidth,
                                child: _PreviewPane(state: state),
                              ),
                            ],
                            if (state.showFrontmatter) FrontmatterPanel(state: state),
                          ],
                        ),
                ),
                Container(height: 1, color: scheme.outlineVariant),
                StatusBar(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static final Map<ShortcutActivator, Intent> _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SaveIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true): const _SaveIntent(),
    const SingleActivator(LogicalKeyboardKey.keyO, control: true): const _OpenFolderIntent(),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): const _NewNoteIntent(),
    const SingleActivator(LogicalKeyboardKey.keyW, control: true): const _CloseTabIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): const _SearchIntent(),
    const SingleActivator(LogicalKeyboardKey.keyB, control: true): const _ToggleSidebarIntent(),
    const SingleActivator(LogicalKeyboardKey.keyP, control: true): const _TogglePreviewIntent(),
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): const _ToggleFrontmatterIntent(),
  };

  Map<Type, Action<Intent>> _actions(WorkspaceState state) {
    return <Type, Action<Intent>>{
      _SaveIntent: CallbackAction<_SaveIntent>(
        onInvoke: (intent) {
          state.saveActive();
          return null;
        },
      ),
      _OpenFolderIntent: CallbackAction<_OpenFolderIntent>(
        onInvoke: (intent) {
          pickLibraryFolder(state);
          return null;
        },
      ),
      _NewNoteIntent: CallbackAction<_NewNoteIntent>(
        onInvoke: (intent) {
          state.createNote();
          return null;
        },
      ),
      _CloseTabIntent: CallbackAction<_CloseTabIntent>(
        onInvoke: (intent) {
          state.closeDocument(state.activeIndex);
          return null;
        },
      ),
      _SearchIntent: CallbackAction<_SearchIntent>(
        onInvoke: (intent) {
          if (!_searchOpen) setState(() => _searchOpen = true);
          return null;
        },
      ),
      _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
        onInvoke: (intent) {
          state.toggleSidebar();
          return null;
        },
      ),
      _TogglePreviewIntent: CallbackAction<_TogglePreviewIntent>(
        onInvoke: (intent) {
          state.togglePreview();
          return null;
        },
      ),
      _ToggleFrontmatterIntent: CallbackAction<_ToggleFrontmatterIntent>(
        onInvoke: (intent) {
          state.toggleFrontmatterPanel();
          return null;
        },
      ),
    };
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _OpenFolderIntent extends Intent {
  const _OpenFolderIntent();
}

class _NewNoteIntent extends Intent {
  const _NewNoteIntent();
}

class _CloseTabIntent extends Intent {
  const _CloseTabIntent();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _TogglePreviewIntent extends Intent {
  const _TogglePreviewIntent();
}

class _ToggleFrontmatterIntent extends Intent {
  const _ToggleFrontmatterIntent();
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.searchOpen,
    required this.onToggleSearch,
  });

  final WorkspaceState state;
  final bool searchOpen;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 860;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '文件树 (Ctrl+B)',
            onPressed: state.hasLibrary ? state.toggleSidebar : null,
            icon: const Icon(Icons.menu_rounded, size: 19),
            visualDensity: VisualDensity.compact,
          ),
          _Logo(state: state),
          const SizedBox(width: 6),
          if (narrow) ...<Widget>[
            _OverflowMenu(state: state, onSearch: onToggleSearch),
          ] else ...<Widget>[
            _LibraryLabel(state: state),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: '把文件夹作为库打开 (Ctrl+O)',
              onPressed: () => pickLibraryFolder(state),
            ),
            _ActionButton(
              icon: Icons.note_add_outlined,
              tooltip: '新建笔记 (Ctrl+N)',
              onPressed: state.hasLibrary ? () => state.createNote() : null,
            ),
            _ActionButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: '新建文件夹',
              onPressed: state.hasLibrary ? () => state.createFolder() : null,
            ),
            const SizedBox(width: 6),
            _SortDropdown(state: state),
          ],
          const Spacer(),
          if (!narrow)
            _ActionButton(
              icon: Icons.search,
              tooltip: '搜索 (Ctrl+F)',
              active: searchOpen,
              onPressed: onToggleSearch,
            ),
          _ActionButton(
            icon: Icons.sell_outlined,
            tooltip: 'Frontmatter 面板 (Ctrl+E)',
            active: state.showFrontmatter,
            onPressed: state.hasLibrary ? state.toggleFrontmatterPanel : null,
          ),
          _ActionButton(
            icon: Icons.vertical_split_rounded,
            tooltip: '预览 (Ctrl+P)',
            active: state.showPreview,
            onPressed: state.hasLibrary ? state.togglePreview : null,
          ),
          _ActionButton(
            icon: state.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            tooltip: state.darkMode ? '浅色主题' : '深色主题',
            onPressed: state.toggleDarkMode,
          ),
          _ActionButton(
            icon: Icons.save_outlined,
            tooltip: '保存 (Ctrl+S)',
            onPressed: state.activeDocument?.isDirty ?? false ? state.saveActive : null,
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Text(
              '砚',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 860) ...<Widget>[
            const SizedBox(width: 7),
            Text(
              'Yan',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryLabel extends StatelessWidget {
  const _LibraryLabel({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = state.library;
    if (library == null) return const SizedBox.shrink();
    return Tooltip(
      message: library.rootPath,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.folder_open_rounded, size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                library.name,
                style: theme.textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '文件排序',
      child: DropdownButton<LibrarySort>(
        value: state.sort,
        isDense: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(8),
        style: theme.textTheme.labelMedium,
        icon: const Icon(Icons.sort_rounded, size: 15),
        onChanged: (value) {
          if (value != null) state.setSort(value);
        },
        items: <DropdownMenuItem<LibrarySort>>[
          for (final sort in LibrarySort.values)
            DropdownMenuItem<LibrarySort>(value: sort, child: Text(sort.label)),
        ],
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.state, required this.onSearch});

  final WorkspaceState state;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert_rounded, size: 19),
      onSelected: (value) async {
        switch (value) {
          case 'open':
            await pickLibraryFolder(state);
          case 'newNote':
            await state.createNote();
          case 'newFolder':
            await state.createFolder();
          case 'search':
            onSearch();
          case 'save':
            await state.saveActive();
          case 'closeTab':
            await state.closeDocument(state.activeIndex);
          case 'sortName':
            state.setSort(LibrarySort.nameAsc);
          case 'sortTime':
            state.setSort(LibrarySort.modifiedDesc);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'open', child: Text('打开文件夹作为库')),
        const PopupMenuItem<String>(value: 'newNote', child: Text('新建笔记')),
        const PopupMenuItem<String>(value: 'newFolder', child: Text('新建文件夹')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'search', child: Text('搜索')),
        const PopupMenuItem<String>(value: 'save', child: Text('保存')),
        const PopupMenuItem<String>(value: 'closeTab', child: Text('关闭当前标签')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'sortName', child: Text('按名称排序')),
        const PopupMenuItem<String>(value: 'sortTime', child: Text('按修改时间排序')),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18),
      style: active
          ? IconButton.styleFrom(
              backgroundColor: scheme.primary.withValues(alpha: 0.14),
              foregroundColor: scheme.primary,
            )
          : null,
    );
  }
}

class _Splitter extends StatelessWidget {
  const _Splitter({required this.onDrag});

  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 5,
          color: scheme.surfaceContainerLow,
          alignment: Alignment.center,
          child: Container(width: 1, color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

class _EdgeToggle extends StatelessWidget {
  const _EdgeToggle({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = state.activeDocument;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.visibility_outlined, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('预览', style: theme.textTheme.labelMedium),
                const Spacer(),
                Text(
                  state.previewLive ? '实时' : '手动',
                  style: theme.textTheme.labelSmall,
                ),
                Switch(
                  value: state.previewLive,
                  onChanged: state.setPreviewLive,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          Expanded(
            child: doc == null
                ? Center(child: Text('没有打开的文件', style: theme.textTheme.bodySmall))
                : MarkdownPreview(
                    source: state.previewSourceFor(doc),
                    fragments: state.mathFragmentsFor(doc),
                    mdTheme: state.markdownTheme,
                    onTapLink: (href) => _openLink(context, href),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String href) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (href.startsWith('#')) {
      state.showToast('v1 暂不支持文档内锚点跳转');
      return;
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text('链接：$href'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<void> pickLibraryFolder(WorkspaceState state) async {
  try {
    final selected = await pickDirectoryPath();
    if (selected == null) return;
    await state.openFolder(selected);
  } on DirectoryPickException catch (e) {
    state.showToast(e.message);
  }
}
