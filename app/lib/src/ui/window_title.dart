import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 窗口/任务标题的工具函数。
///
/// 不引入窗口管理插件：把标题交给 [MaterialApp.onGenerateTitle]，
/// 由 Flutter 引擎在桌面端写进原生窗口标题。
class WindowTitle {
  const WindowTitle._();

  /// 应用名（与宪章命名一致）。
  static const String appName = '砚 Yan';

  /// 是否支持原生窗口标题。
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
