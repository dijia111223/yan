import 'package:flutter/foundation.dart';

/// 库中的一条目录项：文件或文件夹。
///
/// 宪章原则：文件夹即库、纯文件。这里只描述磁盘上真实存在的东西，
/// 不引入任何私有索引/数据库。
@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.modified,
    this.size,
  });

  /// 文件名（不含路径），例如 `week-01.md`。
  final String name;

  /// 绝对路径。
  final String path;

  final bool isDirectory;

  /// 最后修改时间（目录为 null）。
  final DateTime? modified;

  /// 字节大小（目录为 null）。
  final int? size;

  /// 不含扩展名的显示名，用于排序与展示。
  String get displayName {
    if (isDirectory) return name;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 扩展名（小写，含点），目录返回空串。
  String get extension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot).toLowerCase() : '';
  }

  /// 是否为 Markdown 文件——只有它能进编辑器。
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

/// 排序方式：先目录后文件，再按名称或时间。
enum LibrarySort {
  nameAsc('名称 A→Z'),
  nameDesc('名称 Z→A'),
  modifiedDesc('最近修改'),
  modifiedAsc('最早修改');

  const LibrarySort(this.label);

  final String label;
}
