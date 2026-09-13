import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 目录选择失败；[message] 为空表示用户取消。
class DirectoryPickException implements Exception {
  const DirectoryPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 鸿蒙原生目录选择通道，实现见 ohos/entry/src/main/ets/entryability/EntryAbility.ets。
const MethodChannel _ohosDirPicker = MethodChannel('dev.yan/dir_picker');

/// 选择一个目录作为库。
///
/// 三个平台三条路：
/// * 鸿蒙 —— file_picker 的 pubspec 没有 ohos 平台声明，鸿蒙端一个插件都没注册，
///   所以走自建的 MethodChannel；选中的笔记会被复制进应用沙箱再返回路径。
/// * 桌面 —— file_picker 走原生目录对话框，返回真实路径。
/// * Android —— file_picker 走 SAF，拿到 `content://`，`dart:io` 读不了；
///   v1 不做伪文件系统抽象，直接抛 [DirectoryPickException]。
Future<String?> pickDirectoryPath() async {
  if (!kIsWeb && Platform.operatingSystem == 'ohos') {
    return _pickOnOhos();
  }

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

Future<String?> _pickOnOhos() async {
  try {
    final path = await _ohosDirPicker.invokeMethod<String>('pickDirectory');
    if (path == null || path.isEmpty) return null;
    if (!Directory(path).existsSync()) {
      throw DirectoryPickException('目录不可访问：$path');
    }
    return path;
  } on DirectoryPickException {
    rethrow;
  } on MissingPluginException {
    throw const DirectoryPickException('鸿蒙端未注册目录选择通道，无法打开文件夹');
  } on PlatformException catch (e) {
    throw DirectoryPickException(e.message ?? '选择目录失败');
  }
}

/// 鸿蒙沙箱里的库目录。保证存在并返回路径；其他平台返回 null。
///
/// 为什么需要：鸿蒙上库就是沙箱目录，而它原先只在"导入笔记"时才创建。
/// 用户还没导入过就点新建，会往一个不存在的目录写而失败。
Future<String?> ensureOhosLibraryDir() async {
  if (kIsWeb || Platform.operatingSystem != 'ohos') return null;
  try {
    return await _ohosDirPicker.invokeMethod<String>('ensureLibraryDir');
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    if (kDebugMode) debugPrint('创建库目录失败：${e.message}');
    return null;
  }
}

/// 把 [sourcePath] 的内容导出到用户选定的位置（鸿蒙上用系统保存对话框）。
///
/// 返回保存到的位置；用户取消返回 null。
/// 其他平台直接复制到同目录的 `-导出` 副本，避免覆盖原文件。
Future<String?> exportNoteFile(String name, String sourcePath) async {
  if (!kIsWeb && Platform.operatingSystem == 'ohos') {
    try {
      final dest = await _ohosDirPicker.invokeMethod<String>(
        'exportFile',
        <String, Object?>{'name': name},
      );
      return (dest == null || dest.isEmpty) ? null : dest;
    } on MissingPluginException {
      throw const DirectoryPickException('鸿蒙端未注册导出通道');
    } on PlatformException catch (e) {
      throw DirectoryPickException(e.message ?? '导出失败');
    }
  }

  // 桌面端：不弹对话框，复制一份到同目录，名字加后缀
  final src = File(sourcePath);
  if (!src.existsSync()) {
    throw DirectoryPickException('文件不存在：$name');
  }
  final dir = src.parent.path;
  final base = name.replaceAll(RegExp(r'\.[^.]+$'), '');
  final ext = name.substring(base.length);
  var dest = File('$dir${Platform.pathSeparator}$base-导出$ext');
  var n = 2;
  while (dest.existsSync()) {
    dest = File('$dir${Platform.pathSeparator}$base-导出$n$ext');
    n++;
  }
  await src.copy(dest.path);
  return dest.path;
}
