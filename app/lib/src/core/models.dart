import 'package:flutter/foundation.dart';

/// 库中的一条目录项：文件或文件夹。
@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.modified,
    this.size,
  });

  final String name;

  final String path;

  final bool isDirectory;

  /// 目录项为目录时为 null。
  final DateTime? modified;

  /// 目录项为目录时为 null。
  final int? size;

  /// 不含扩展名的显示名。
  String get displayName {
    if (isDirectory) return name;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String get extension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot).toLowerCase() : '';
  }

  bool get isMarkdown =>
      !isDirectory && const {'.md', '.markdown', '.mdown', '.mkd', '.txt'}.contains(extension);

  @override
  bool operator ==(Object other) =>
      other is LibraryEntry && other.path == path && other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(path, isDirectory);

  @override
  String toString() => '${isDirectory ? 'dir' : 'file'}($path)';
}

/// 排序方式：先目录后文件。
enum LibrarySort {
  nameAsc('名称 A→Z'),
  nameDesc('名称 Z→A'),
  modifiedDesc('最近修改'),
  modifiedAsc('最早修改');

  const LibrarySort(this.label);

  final String label;
}
