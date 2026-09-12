import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../state/workspace.dart';

/// 文件树：文件夹即库，按层懒加载，不做任何索引。
///
/// 目录列举走**同步**读盘（`listChildrenSync`）。理由：树天然是按需展开的，
/// 一次只列一层，开销可以忽略；而同步渲染路径没有"加载中"中间态，树不会闪，
/// 也让界面行为完全可预测。
class FileTree extends StatefulWidget {
  const FileTree({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  /// 已展开的目录路径。
  final Set<String> _expanded = <String>{};

  /// 目录路径 → 子项（按层缓存，展开时按需读取）。
  final Map<String, List<LibraryEntry>> _children = <String, List<LibraryEntry>>{};

  int _cacheRevision = -1;
  String? _lastReveal;

  WorkspaceState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _ensureLoaded(state.library?.rootPath);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyReveal());
  }

  @override
  void didUpdateWidget(FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyReveal();
  }

  /// 读取某一层（已缓存则直接返回）。
  List<LibraryEntry> _childrenOf(String path) {
    final library = state.library;
    if (library == null) return const <LibraryEntry>[];
    return _children.putIfAbsent(
      path,
      () => library.listChildrenSync(path, sort: state.sort),
    );
  }

  void _ensureLoaded(String? path) {
    if (path == null || _children.containsKey(path)) return;
    _children[path] =
        state.library?.listChildrenSync(path, sort: state.sort) ?? const <LibraryEntry>[];
  }

  void _invalidate() {
    _children.clear();
    _lastReveal = null;
    _ensureLoaded(state.library?.rootPath);
  }

  /// 响应"在树中显示某文件"：展开它所有的父目录。
  void _applyReveal() {
    final reveal = state.revealPath;
    if (reveal == null || reveal == _lastReveal) return;
    final library = state.library;
    if (library == null) return;
    _lastReveal = reveal;

    final toExpand = <String>{};
    var current = p.dirname(reveal);
    while (current.length >= library.rootPath.length) {
      toExpand.add(current);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    toExpand.add(library.rootPath);

    setState(() {
      for (final path in toExpand) {
        _expanded.add(path);
        _ensureLoaded(path);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) state.clearReveal();
    });
  }

  Future<void> _createNote(String? parentPath) async {
    await state.createNote(parentPath: parentPath);
    if (mounted) setState(_invalidate);
  }

  Future<void> _createFolder(String? parentPath) async {
    await state.createFolder(parentPath: parentPath);
    if (mounted) setState(_invalidate);
  }

  Future<void> _rename(LibraryEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == entry.name) return;
    await state.renameEntry(entry.path, newName);
    if (mounted) setState(_invalidate);
  }

  Future<void> _delete(LibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: Text(
          entry.isDirectory
              ? '删除文件夹「${entry.name}」及其中的全部内容？此操作不可撤销。'
              : '删除「${entry.name}」？此操作不可撤销。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.deleteEntry(entry.path);
    if (mounted) setState(_invalidate);
  }

  @override
  Widget build(BuildContext context) {
    final library = state.library;
    if (library == null) return const SizedBox.shrink();

    if (state.treeRevision != _cacheRevision) {
      _cacheRevision = state.treeRevision;
      _invalidate();
    }

    final scheme = Theme.of(context).colorScheme;
    final entries = _childrenOf(library.rootPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LibraryHeader(state: state, onNewNote: () => _createNote(null)),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: entries.isEmpty
              ? _EmptyLibrary(onCreateNote: () => _createNote(null))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _Tile(
                    state: state,
                    entry: entries[index],
                    depth: 0,
                    expanded: _expanded,
                    revealPath: state.revealPath,
                    childrenOf: _childrenOf,
                    onToggle: (path) => setState(() {
                      if (_expanded.remove(path)) {
                        // 收起：保留缓存，重新展开时立刻可见
                        return;
                      }
                      _expanded.add(path);
                      // 展开时丢弃该层缓存，保证看到的是磁盘当前状态
                      _children.remove(path);
                    }),
                    onCreateNote: _createNote,
                    onCreateFolder: _createFolder,
                    onRename: _rename,
                    onDelete: _delete,
                  ),
                ),
        ),
      ],
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.state, required this.onNewNote});

  final WorkspaceState state;
  final VoidCallback onNewNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.folder_open_rounded, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Tooltip(
              message: state.libraryPath ?? '',
              child: Text(
                state.library?.name ?? '未打开库',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            tooltip: '新建笔记',
            onPressed: onNewNote,
            icon: const Icon(Icons.note_add_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onCreateNote});

  final VoidCallback onCreateNote;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('这个文件夹是空的', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onCreateNote,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建第一篇笔记'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.state,
    required this.entry,
    required this.depth,
    required this.expanded,
    required this.revealPath,
    required this.childrenOf,
    required this.onToggle,
    required this.onCreateNote,
    required this.onCreateFolder,
    required this.onRename,
    required this.onDelete,
  });

  final WorkspaceState state;
  final LibraryEntry entry;
  final int depth;
  final Set<String> expanded;
  final String? revealPath;
  final List<LibraryEntry> Function(String) childrenOf;
  final void Function(String) onToggle;
  final Future<void> Function(String?) onCreateNote;
  final Future<void> Function(String?) onCreateFolder;
  final Future<void> Function(LibraryEntry) onRename;
  final Future<void> Function(LibraryEntry) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpanded = expanded.contains(entry.path);
    final isActive = state.activeDocument?.path == entry.path;
    final isRevealed = revealPath == entry.path;

    final row = InkWell(
      onTap: () {
        if (entry.isDirectory) {
          onToggle(entry.path);
        } else if (entry.isMarkdown) {
          state.openFile(entry.path);
        } else {
          state.showToast('v1 只打开 Markdown 文件：${entry.name}');
        }
      },
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      onLongPress: () {
        // 移动端：长按唤出同一个上下文菜单
        final box = context.findRenderObject() as RenderBox?;
        final position = box == null
            ? Offset.zero
            : box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
        _showContextMenu(context, position);
      },
      child: Container(
        color: isRevealed
            ? theme.colorScheme.primary.withValues(alpha: 0.16)
            : (isActive ? theme.colorScheme.primary.withValues(alpha: 0.10) : null),
        padding: EdgeInsets.only(left: 8 + depth * 14.0, right: 4, top: 5, bottom: 5),
        child: Row(
          children: <Widget>[
            _icon(theme, isExpanded),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                entry.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: entry.isMarkdown || entry.isDirectory ? null : theme.disabledColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (!entry.isDirectory || !isExpanded) return row;

    final children = childrenOf(entry.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        row,
        if (children.isEmpty)
          Padding(
            padding: EdgeInsets.only(left: 30 + depth * 14.0, top: 4, bottom: 4),
            child: Text('（空）', style: theme.textTheme.bodySmall),
          )
        else
          for (final child in children)
            _Tile(
              state: state,
              entry: child,
              depth: depth + 1,
              expanded: expanded,
              revealPath: revealPath,
              childrenOf: childrenOf,
              onToggle: onToggle,
              onCreateNote: onCreateNote,
              onCreateFolder: onCreateFolder,
              onRename: onRename,
              onDelete: onDelete,
            ),
      ],
    );
  }

  Widget _icon(ThemeData theme, bool isExpanded) {
    if (entry.isDirectory) {
      return Icon(
        isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
        size: 15,
        color: theme.colorScheme.primary.withValues(alpha: 0.85),
      );
    }
    if (entry.isMarkdown) {
      return Icon(
        Icons.description_outlined,
        size: 15,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    return Icon(Icons.insert_drive_file_outlined, size: 15, color: theme.disabledColor);
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final parentPath = entry.isDirectory ? entry.path : p.dirname(entry.path);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
      items: <PopupMenuEntry<String>>[
        if (entry.isDirectory) ...<PopupMenuEntry<String>>[
          const PopupMenuItem<String>(value: 'newNote', child: Text('在此新建笔记')),
          const PopupMenuItem<String>(value: 'newFolder', child: Text('在此新建子文件夹')),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    );

    switch (selected) {
      case 'newNote':
        await onCreateNote(parentPath);
      case 'newFolder':
        await onCreateFolder(parentPath);
      case 'rename':
        await onRename(entry);
      case 'delete':
        await onDelete(entry);
    }
  }
}
