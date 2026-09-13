import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 窗口/任务标题工具：标题交给 [MaterialApp.onGenerateTitle]，不引窗口管理插件。
class WindowTitle {
  const WindowTitle._();

  static const String appName = '砚 Yan';

  static bool get supported {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// 组合标题：`● 笔记.md — 库名 — 砚 Yan`。
  static String compose({
    String? filePath,
    bool isDirty = false,
    String? libraryName,
  }) {
    final parts = <String>[];
    if (filePath != null) {
      parts.add('${isDirty ? '● ' : ''}${p.basename(filePath)}');
    } else {
      parts.add('未打开文件');
    }
    if (libraryName != null && libraryName.isNotEmpty) parts.add(libraryName);
    parts.add(appName);
    return parts.join(' — ');
  }
}
