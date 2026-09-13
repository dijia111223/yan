/// 命令行启动参数。
///
/// ```
/// yan_note.exe --library D:\notes
/// yan_note.exe --library D:\notes --open D:\notes\CUDA.md
/// yan_note.exe D:\notes\CUDA.md
/// ```
///
/// 命令行参数优先于会话恢复状态。
class LaunchOptions {
  const LaunchOptions({this.libraryPath, this.openFiles = const <String>[]});

  final String? libraryPath;

  /// 绝对路径。
  final List<String> openFiles;

  bool get isEmpty => libraryPath == null && openFiles.isEmpty;

  static LaunchOptions parse(List<String> args) {
    String? library;
    final files = <String>[];

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--library':
        case '-l':
          // 下一个参数是开关时不取值，否则 `--library --open x` 会把 `--open` 当路径
          if (i + 1 < args.length && !_isSwitch(args[i + 1])) library = args[++i];
        case '--open':
        case '-o':
          if (i + 1 < args.length && !_isSwitch(args[i + 1])) files.add(args[++i]);
        default:
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
