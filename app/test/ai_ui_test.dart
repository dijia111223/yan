// 端侧补全的界面接线测试。
//
// 为什么用 widget 测试而不是截图：截图只能证明"某次运行看起来对"，
// 而这里要钉住的是**交互与状态**（建议栏什么时候出现、Tab 什么时候被拦截、
// 设置面板能不能打开、缺原生库时是否安静降级）。这些用 tester 能精确断言，
// 而且能进 CI。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yan_note/src/core/ai_model_download.dart';
import 'package:yan_note/src/state/ai_controller.dart';
import 'package:yan_note/src/state/ai_scope.dart';
import 'package:yan_note/src/state/ai_suggestion.dart';
import 'package:yan_note/src/ui/ai_settings_panel.dart';
import 'package:yan_note/src/ui/ai_suggestion_bar.dart';

/// 一个只用于测试的 AiController：不碰原生库、不碰网络。
class _FakeAi extends AiController {
  _FakeAi({this.result = '', this.on = true, this.native = true})
      : super(nativeAvailable: Future<bool>.value(native));

  String result;

  /// 覆盖父类的 enabled，避免依赖偏好读取。
  final bool on;

  /// 原生库是否"存在"。真实实现要 spawn isolate 去试探，这里直接给定 ——
  /// 否则界面提示是否正确会取决于 isolate 的启动时序。
  final bool native;

  int requests = 0;
  int cancels = 0;

  @override
  bool get enabled => on;

  @override
  Future<String> requestCompletion(String text, int cursor) async {
    requests++;
    return result;
  }

  @override
  void cancelCompletion() => cancels++;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    // AiController.bootstrap 会读偏好；给个空的内存实现避免碰真实存储
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('建议栏', () {
    testWidgets('没有建议时不占空间', (tester) async {
      final ai = _FakeAi();
      final s = AiSuggestionController(ai: ai, debounce: Duration.zero);
      addTearDown(s.dispose);

      await tester.pumpWidget(_host(AiSuggestionBar(controller: s, onAccept: (_) {})));
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      expect(find.text('采纳 Tab'), findsNothing);
    });

    testWidgets('有建议时显示文本与采纳按钮', (tester) async {
      final ai = _FakeAi(result: ' 支持鸿蒙');
      final s = AiSuggestionController(ai: ai, debounce: Duration.zero);
      addTearDown(s.dispose);

      await tester.pumpWidget(_host(AiSuggestionBar(controller: s, onAccept: (_) {})));
      s.onTextChanged('- 支持 Windows\n-', 14);
      await tester.pumpAndSettle();

      expect(find.text(' 支持鸿蒙'), findsOneWidget);
      expect(find.text('采纳 Tab'), findsOneWidget);
    });
  });

  group('快捷键拦截', () {
    testWidgets('没有建议时 Tab 不被拦截（否则 Tab 会突然失效）', (tester) async {
      final ai = _FakeAi();
      final s = AiSuggestionController(ai: ai, debounce: Duration.zero);
      addTearDown(s.dispose);

      var accepted = 0;
      await tester.pumpWidget(
        _host(
          AiSuggestionShortcuts(
            controller: s,
            onAccept: () => accepted++,
            child: const TextField(),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(accepted, 0);
    });

    testWidgets('有建议时 Tab 触发采纳', (tester) async {
      final ai = _FakeAi(result: '续写内容');
      final s = AiSuggestionController(ai: ai, debounce: Duration.zero);
      addTearDown(s.dispose);

      var accepted = 0;
      await tester.pumpWidget(
        _host(
          AiSuggestionShortcuts(
            controller: s,
            onAccept: () => accepted++,
            child: const TextField(),
          ),
        ),
      );
      s.onTextChanged('前面的话', 4);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(accepted, 1);
    });
  });

  group('设置面板', () {
    testWidgets('能打开并显示关键信息', (tester) async {
      final ai = _FakeAi(on: false);
      addTearDown(ai.dispose);

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AiSettingsPanel.show(context, ai),
            child: const Text('打开'),
          ),
        ),
      ),);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('端侧智能补全'), findsOneWidget);
      expect(find.text('启用补全建议'), findsOneWidget);
      // 隐私说明必须在：用户要知道笔记不会被上传
      expect(find.textContaining('笔记内容不会上传'), findsOneWidget);
      // 未下载时应给出下载入口
      expect(find.text('下载模型'), findsOneWidget);
    });

    testWidgets('缺原生库时给出说明而不是让用户白下载', (tester) async {
      final ai = _FakeAi(on: false, native: false);
      addTearDown(ai.dispose);

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AiSettingsPanel.show(context, ai),
            child: const Text('打开'),
          ),
        ),
      ),);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      // 测试环境里没有 libyan_ai，nativeAvailable 应为 false，
      // 于是必须提示"当前平台没有可用的推理库"
      expect(find.textContaining('没有可用的推理库'), findsOneWidget);
    });
  });

  group('降级', () {
    testWidgets('没有 AiScope 时选项可空而不抛异常', (tester) async {
      // 端侧补全是可选能力：容器没注入控制器时，界面应当安静地少一块，
      // 而不是让整个应用起不来。
      AiController? seen;
      var probed = false;
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) {
            seen = AiScope.maybeOf(context);
            probed = true;
            return const Text('无 AI 容器');
          },
        ),
      ),);
      expect(probed, isTrue);
      expect(seen, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('下载状态文案', () {
    test('各阶段都有可读文案', () {
      expect(
        describeDownload(const AiDownloadState(phase: AiDownloadPhase.idle)),
        '尚未下载',
      );
      expect(
        describeDownload(const AiDownloadState(phase: AiDownloadPhase.verifying)),
        '正在校验完整性…',
      );
      expect(describeDownload(const AiDownloadState(phase: AiDownloadPhase.ready)), '已就绪');
    });
  });
}
