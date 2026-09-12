import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/state/workspace.dart';
import 'src/state/workspace_scope.dart';
import 'src/ui/shell.dart';
import 'src/ui/window_title.dart';

/// 砚（Yan）——纯文件、本地优先的 Markdown 编辑器。
class YanApp extends StatefulWidget {
  const YanApp({super.key});

  @override
  State<YanApp> createState() => _YanAppState();
}

class _YanAppState extends State<YanApp> {
  final WorkspaceState _state = WorkspaceState();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _state.bootstrap().whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  /// 单色种子，接近墨色——"砚"的视觉基调。
  static const Color _seed = Color(0xFF2F6F62);

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll<double>(8),
        radius: Radius.circular(4),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        title: WindowTitle.appName,
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        home: const _Splash(),
      );
    }

    return WorkspaceScope(
      state: _state,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          final doc = _state.activeDocument;
          return MaterialApp(
            title: WindowTitle.appName,
            onGenerateTitle: (context) {
              // 桌面端窗口标题：文件名 + 库名
              if (!WindowTitle.supported) return WindowTitle.appName;
              return WindowTitle.compose(
                filePath: doc?.path,
                isDirty: doc?.isDirty ?? false,
                libraryName: _state.library?.name,
              );
            },
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
            scrollBehavior: const _DesktopScrollBehavior(),
            home: const Shell(),
          );
        },
      ),
    );
  }
}

/// 桌面端允许鼠标拖动滚动条、显示滚动条。
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
