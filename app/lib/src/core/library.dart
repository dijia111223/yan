import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

/// 一个"库" = 磁盘上的一个文件夹。没有索引、没有数据库，每次按需读盘。
class Library {
  Library(this.rootPath);

  /// 库根目录的绝对路径。
  final String rootPath;

  /// 库名（取文件夹名）。
  String get name => p.basename(rootPath);

  /// 扫描时需要跳过的目录名（版本控制、构建产物、其它笔记软件的私有目录）。
  static const Set<String> skippedDirectoryNames = <String>{
    '.git',
    '.svn',
    '.hg',
    '.obsidian',
    '.trash',
    '.github',
    '.dart_tool',
    'build',
    'node_modules',
    'oh_modules',
    'ephemeral',
    '.hvigor',
    '.idea',
    '.vscode',
    // 妙言（MiaoYan）把附件放在这里，避免把二进制资源当笔记列出来
    'attachments',
    '.yan',
  };

  /// 是否跳过这个目录项。
  static bool shouldSkip(String name) {
    if (name.startsWith('.')) return true;
    return skippedDirectoryNames.contains(name);
  }

  Directory get directory => Directory(rootPath);

  bool get exists => directory.existsSync();

  /// 列出 [directoryPath] 下的一层子项（不递归），供文件树懒加载。
  ///
  /// 目录排在文件前面；同一组内按 [sort] 排序。读盘失败返回空列表——
  /// 单个目录权限问题不应让整个文件树崩掉。
  Future<List<LibraryEntry>> listChildren(
    String directoryPath, {
    LibrarySort sort = LibrarySort.nameAsc,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const <LibraryEntry>[];

    final List<LibraryEntry> entries = <LibraryEntry>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (shouldSkip(name)) continue;

        final isDir = entity is Directory;
        if (isDir) {
          entries.add(LibraryEntry(name: name, path: entity.path, isDirectory: true));
        } else if (entity is File) {
          final stat = await entity.stat();
          entries.add(
            LibraryEntry(
              name: name,
              path: entity.path,
              isDirectory: false,
              modified: stat.modified,
              size: stat.size,
            ),
          );
        }
      }
    } on FileSystemException {
      return const <LibraryEntry>[];
    }

    _sort(entries, sort);
    return entries;
  }

  /// 同步列出一层子项。
  ///
  /// 文件树用它而不是异步版：目录树是**一次一层**的懒加载，单层 `listSync` 开销
  /// 可忽略，换来的是渲染路径上没有任何异步等待——树不会闪，也不会出现"加载中"
  /// 中间态。真正的递归扫描（全文搜索）仍然走异步。
  List<LibraryEntry> listChildrenSync(
    String directoryPath, {
    LibrarySort sort = LibrarySort.nameAsc,
  }) {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return const <LibraryEntry>[];

    final entries = <LibraryEntry>[];
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        final name = p.basename(entity.path);
        if (shouldSkip(name)) continue;

        if (entity is Directory) {
          entries.add(LibraryEntry(name: name, path: entity.path, isDirectory: true));
        } else if (entity is File) {
          final stat = entity.statSync();
          entries.add(
            LibraryEntry(
              name: name,
              path: entity.path,
              isDirectory: false,
              modified: stat.modified,
              size: stat.size,
            ),
          );
        }
      }
    } on FileSystemException {
      return const <LibraryEntry>[];
    }

    _sort(entries, sort);
    return entries;
  }

  static void _sort(List<LibraryEntry> entries, LibrarySort sort) {
    int byDirectory(LibraryEntry a, LibraryEntry b) {
      if (a.isDirectory == b.isDirectory) return 0;
      return a.isDirectory ? -1 : 1;
    }

    entries.sort((a, b) {
      final dir = byDirectory(a, b);
      if (dir != 0) return dir;
      final cmp = switch (sort) {
        LibrarySort.nameAsc => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        LibrarySort.nameDesc => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        LibrarySort.modifiedDesc => _compareTime(b, a),
        LibrarySort.modifiedAsc => _compareTime(a, b),
      };
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  static int _compareTime(LibraryEntry a, LibraryEntry b) {
    final ta = a.modified;
    final tb = b.modified;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return ta.compareTo(tb);
  }

  /// 递归收集库内所有 Markdown 文件路径（用于全文搜索）。
  ///
  /// 只返回 [LibraryEntry.isMarkdown] 为真的文件。
  Future<List<LibraryEntry>> collectMarkdownFiles({
    int maxFiles = 20000,
  }) async {
    final results = <LibraryEntry>[];
    if (!await directory.exists()) return results;

    final queue = <Directory>[directory];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      final List<FileSystemEntity> children;
      try {
        children = await current.list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      for (final entity in children) {
        final name = p.basename(entity.path);
        if (shouldSkip(name)) continue;
        if (entity is Directory) {
          queue.add(entity);
        } else if (entity is File) {
          final entry = LibraryEntry(name: name, path: entity.path, isDirectory: false);
          if (entry.isMarkdown) {
            results.add(entry);
            if (results.length >= maxFiles) return results;
          }
        }
      }
    }
    return results;
  }

  /// 在库内新建一个不重名的 Markdown 文件，返回其路径。
  Future<String> createNote({String baseName = '未命名笔记', String? parentPath}) async {
    final targetDir = Directory(parentPath ?? rootPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    var candidate = p.join(targetDir.path, '$baseName.md');
    var index = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(targetDir.path, '$baseName $index.md');
      index++;
    }
    await File(candidate).writeAsString('');
    return candidate;
  }

  /// 在库内新建子文件夹，返回其路径。
  Future<String> createFolder({String baseName = '新建文件夹', String? parentPath}) async {
    final targetDir = Directory(parentPath ?? rootPath);
    var candidate = p.join(targetDir.path, baseName);
    var index = 1;
    while (await Directory(candidate).exists() || await File(candidate).exists()) {
      candidate = p.join(targetDir.path, '$baseName $index');
      index++;
    }
    await Directory(candidate).create(recursive: true);
    return candidate;
  }

  /// 重命名（同目录内）。返回新路径；目标已存在时抛出 [FileSystemException]。
  Future<String> rename(String path, String newName) async {
    final parent = p.dirname(path);
    final target = p.join(parent, newName);
    if (target == path) return path;
    if (await File(target).exists() || await Directory(target).exists()) {
      throw FileSystemException('同名文件已存在', target);
    }
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      return (await Directory(path).rename(target)).path;
    }
    return (await File(path).rename(target)).path;
  }

  /// 删除文件（送到系统回收站之外——直接删除，UI 层必须二次确认）。
  Future<void> delete(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }

  /// 把库内的绝对路径转成相对路径（用于展示与搜索结果）。
  String relative(String absolutePath) {
    final rel = p.relative(absolutePath, from: rootPath);
    return rel.replaceAll(r'\', '/');
  }

  /// 目录项的直接子项数量（文件树展开前的粗略计数，读盘失败返回 null）。
  static Future<int?> childCount(String directoryPath) async {
    try {
      var count = 0;
      await for (final entity in Directory(directoryPath).list(followLinks: false)) {
        if (!shouldSkip(p.basename(entity.path))) count++;
      }
      return count;
    } on FileSystemException {
      return null;
    }
  }
}
