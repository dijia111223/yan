import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:yan_note/src/state/workspace.dart';
import 'package:yan_note/src/state/workspace_scope.dart';
import 'package:yan_note/src/ui/shell.dart';

/// 端到端测试：跑在**真实的 Windows 应用进程**里。
///
/// 与 `flutter test`（headless、无字体、无法派发真实 I/O 回调）不同，这里验证的是
/// 交付给用户的那个东西：真的窗口、真的渲染管线、真的文件系统。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late WorkspaceState state;

  setUp(() {
    root = Directory.systemTemp.createTempSync('yan_e2e_');
    File(p.join(root.path, 'alpha.md')).writeAsStringSync(
      '# 阿尔法笔记\n\n这是正文，包含 **粗体** 与 `行内代码`。\n',
    );
    File(p.join(root.path, 'beta.md')).writeAsStringSync(
      '---\ntitle: 贝塔\n---\n\n'
      '# 贝塔笔记\n\n'
      '| 列 1 | 列 2 |\n| --- | --- |\n| a | b |\n\n'
      '行内公式 \$E = mc^2\$ 与 \$\\alpha \\le \\beta\$。\n\n'
      '\$\$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n\$\$\n',
    );
    state = WorkspaceState();
  });

  tearDown(() {
    state.dispose();
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // 临时目录清不掉不影响结论
    }
  });

  Widget buildApp() => WorkspaceScope(
        state: state,
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const Shell(),
          ),
        ),
      );

  testWidgets('端到端：打开库 → 打开笔记 → 编辑落盘 → 预览渲染 → 搜索跳转',
      (tester) async {
    // 真实读盘在集成测试里可以正常 await
    await state.openFolder(root.path);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 文件树列出了磁盘上的文件
    expect(find.text('alpha.md'), findsOneWidget);
    expect(find.text('beta.md'), findsOneWidget);

    // 点击打开编辑器
    await tester.tap(find.text('alpha.md'));
    await tester.pumpAndSettle();
    expect(state.activeDocument, isNotNull);
    expect(
      state.activeDocument!.controller.text,
      File(p.join(root.path, 'alpha.md')).readAsStringSync(),
    );

    // 编辑并保存 → 真实落盘
    state.activeDocument!.controller.text = '# 改过的标题\n新内容\n';
    await tester.pump();
    expect(state.activeDocument!.isDirty, isTrue);
    await state.saveActive();
    await tester.pumpAndSettle();
    expect(
      File(p.join(root.path, 'alpha.md')).readAsStringSync(),
      '# 改过的标题\n新内容\n',
    );
    expect(state.activeDocument!.isDirty, isFalse);

    // 切到含公式与表格的笔记，验证真实渲染管线
    await tester.tap(find.text('beta.md'));
    await tester.pumpAndSettle();

    expect(find.textContaining('贝塔笔记'), findsWidgets);
    expect(find.textContaining('列 1'), findsWidgets);
    // 行内公式 → Unicode 文本
    expect(find.textContaining('mc²'), findsWidgets);
    expect(find.textContaining('α'), findsWidgets);
    // 行间公式 → 真实数学组件（真实进程里有 KaTeX 字体，应能正常排版）
    expect(find.byType(Math), findsWidgets);
    // 占位符绝不能泄漏
    expect(find.textContaining('YANMATH'), findsNothing);

    // 搜索 → 命中 → 跳转
    await state.runSearch('贝塔');
    expect(state.searchHits, isNotEmpty);
    await state.openHit(state.searchHits.first);
    await tester.pumpAndSettle();
    expect(state.activeDocument!.path, p.join(root.path, 'beta.md'));
  });
}
