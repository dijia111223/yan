import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

class DirectoryPickException implements Exception {
  const DirectoryPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 选择一个目录作为库。
///
/// Android 上 file_picker 走 SAF，拿到的是 `content://` URI（或 `/tree/...` 伪路径），
/// `dart:io` 读写不了；v1 不做伪文件系统抽象，直接抛 [DirectoryPickException]。
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
