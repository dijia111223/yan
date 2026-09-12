import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'src/core/launch_options.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面端支持从命令行直接打开库 / 笔记（见 LaunchOptions）。
  // 移动端拿不到命令行参数，按无参处理。
  final launch = Platform.isWindows || Platform.isLinux || Platform.isMacOS
      ? LaunchOptions.parse(args)
      : const LaunchOptions();
  runApp(YanApp(launchOptions: launch));
}
