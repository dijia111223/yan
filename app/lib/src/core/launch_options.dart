/// 命令行启动参数。
///
/// 支持从终端或"发送到"菜单直接打开库与笔记：
///
/// ```
/// yan_note.exe --library "D:\notes"
/// yan_note.exe --library "D:\notes" --open "D:\notes\CUDA.md"
/// yan_note.exe "D:\notes\CUDA.md"          # 位置参数也当作要打开的笔记
/// ```
///
/// 命令行参数**优先于**上次会话恢复的状态——用户这次显式指定的意图，
/// 不该被历史状态覆盖。
class LaunchOptions {
  const LaunchOptions({this.libraryPath, this.openFiles = const <String>[]});

  /// 显式指定的库目录。
  final String? libraryPath;

  /// 要打开的笔记（绝对路径）。
  final List<String> openFiles;

  bool get isEmpty => libraryPath == null && openFiles.isEmpty;

  /// 解析进程参数。
  static LaunchOptions parse(List<String> args) {
    String? library;
    final files = <String>[];

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--library':
        case '-l':
          // 取值不能是另一个开关，否则 `--library --open x` 会把 `--open` 当路径
          if (i + 1 < args.length && !_isSwitch(args[i + 1])) library = args[++i];
        case '--open':
        case '-o':
          if (i + 1 < args.length && !_isSwitch(args[i + 1])) files.add(args[++i]);
        default:
          // 位置参数：按后缀判断是不是可打开的笔记
          if (!_isSwitch(arg) && _looksLikeNote(arg)) files.add(arg);
      }
    }
    return LaunchOptions(libraryPath: library, openFiles: files);
  }

  static bool _isSwitch(String arg) => arg.startsWith('-');

  static bool _looksLikeNote(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.mdown') ||
        lower.endsWith('.mkd') ||
        lower.endsWith('.txt');
  }

  @override
  String toString() => 'LaunchOptions(library: $libraryPath, open: $openFiles)';
}
