import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// 目录选择失败的原因。
class DirectoryPickException implements Exception {
  const DirectoryPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 选择一个目录作为库。
///
/// 桌面端：原生目录对话框，返回可直接读写的绝对路径。
/// Android：`file_picker` 走 SAF，返回的是 `content://` URI（或某些机型给出
/// `/tree/...` 形式的伪路径），无法直接用 `dart:io` 读写。v1 明确不做"伪文件系统"
/// 抽象，因此这里抛出 [DirectoryPickException] 并提示替代方案——宁可功能诚实缺失，
/// 也不做半截支持。
Future<String?> pickDirectoryPath() async {
  try {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: '选择文件夹作为库',
    );
    if (selected == null || selected.isEmpty) return null;

    if (selected.startsWith('content://')) {
      throw const DirectoryPickException(
        'Android 的 SAF 目录授权（content://）v1 尚未支持。'
        '请把库放在应用可访问的目录，或在 Windows / 鸿蒙端使用本应用。',
      );
    }
    if (!Directory(selected).existsSync()) {
      throw DirectoryPickException('目录不可访问：$selected');
    }
    return selected;
  } on DirectoryPickException {
    rethrow;
  } on Exception catch (e) {
    if (kDebugMode) debugPrint('选择目录失败：$e');
    throw DirectoryPickException('选择目录失败：$e');
  }
}
