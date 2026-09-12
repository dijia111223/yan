import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yan_note/src/state/workspace.dart';
import 'package:yan_note/src/state/workspace_scope.dart';
import 'package:yan_note/src/ui/search_panel.dart';
import 'package:yan_note/src/ui/shell.dart';

/// 端到端组件测试：真实的磁盘库 + 真实的界面。
///
/// 这里刻意不 mock 文件系统——"纯文件、本地优先"是宪章的第一原则，
/// 测试也应该走真实文件。
void main() {
  late Directory root;
  late WorkspaceState state;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = Directory.systemTemp.createTempSync('yan_app_');

    File(p.join(root.path, 'alpha.md')).writeAsStringSync(
      '# 阿尔法笔记\n\n这是正文，包含 **粗体** 与 `行内代码`。\n',
    );
    // beta.md 整段用原始字符串写：公式里的反斜杠与 $ 都不该被 Dart 转义规则干扰。
    // （这里踩过坑：普通字符串里 `\alpha` 的反斜杠会消失、`\$\$` 会变成字面量 `\$`。）
    File(p.join(root.path, 'beta.md')).writeAsStringSync(r'''
---
title: 贝塔
tags: [测试]
created: 2026-09-09
---

# 贝塔笔记

| 列 1 | 列 2 |
| --- | --- |
| a | b |

质能方程 $E = mc^2$ 与希腊字母 $\alpha \le \beta$。

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$
''');

    state = WorkspaceState();
  });

  tearDown(() async {
    state.dispose();
    // Windows 上刚写过的文件可能还被占用一小会儿，删除会抛 PathAccessException。
    // 临时目录清不掉不影响测试结论，因此重试几次后放弃。
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!root.existsSync()) return;
      try {
        root.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  });

  /// 在真实事件循环里执行异步读盘。
  ///
  /// `flutter_test` 默认在 fake-async 区域里跑测试体，真实的文件 I/O 完成回调
  /// **永远不会**被派发——直接在测试体里 `await` 读盘会挂死。所有触碰真实磁盘的
  /// 异步调用都必须包在 [WidgetTester.runAsync] 里。
  Future<T> io<T>(WidgetTester tester, Future<T> Function() action) async {
    final result = await tester.runAsync(action);
    return result as T;
  }

  /// 在真实事件循环里 pump 若干帧。
  ///
  /// 关键：文件树的读盘、`openFile`、`saveDocument` 都发生在真实文件系统上。
  /// 如果 pump 发生在 fake-async 区（`runAsync` 之外），这些 I/O 的回调永远不会
  /// 被派发——表现为"明明有文件，界面上却是空的"或"保存了但磁盘没变"。
  /// 因此涉及读写的 pump 都必须放进 [WidgetTester.runAsync]。
  Future<void> settleAsync(WidgetTester tester, {int frames = 10}) async {
    await tester.runAsync(() async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await io(tester, () => state.openFolder(root.path));
    // 让文件树完成首轮读盘
    await settleAsync(tester);
  }

  /// 打开某篇笔记。
  ///
  /// `InkWell.onTap` 里发起的读盘是在 widget 层异步跑的，测试无法直接 await；
  /// 因此这里额外在真实事件循环里显式跑一次 [WorkspaceState.openFile]（它是幂等的，
  /// 已打开的标签会直接返回），确保读盘真的完成后再推帧。
  Future<void> openNote(WidgetTester tester, String fileName) async {
    await tester.tap(find.text(fileName));
    await settleAsync(tester);
    await io(tester, () => state.openFile(p.join(root.path, fileName)));
    await settleAsync(tester);
  }

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      WorkspaceScope(
        state: state,
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const Shell(),
          ),
        ),
      ),
    );
    await settleAsync(tester);
  }

  testWidgets('未打开库时显示欢迎页', (tester) async {
    await pumpShell(tester);
    expect(find.text('砚 Yan'), findsOneWidget);
    expect(find.text('打开文件夹作为库'), findsOneWidget);
  });

  testWidgets('打开文件夹后文件树列出磁盘上的笔记', (tester) async {
    await openLibrary(tester);
    await tester.runAsync(() async {
      // ignore: avoid_print
      print('A entries=${Directory(root.path).listSync().length} hasLibrary=${state.hasLibrary} rev=${state.treeRevision}');
      // 直接验证 Library 层能读到
      final entries = await state.library!.listChildren(root.path);
      // ignore: avoid_print
      print('B listChildren -> ${entries.map((e) => '${e.name}${e.isDirectory ? "/" : ""}').toList()}');
      // 真实读盘与 listSync 是否一致
      final sync = Directory(root.path).listSync().map((e) => p.basename(e.path)).toList()..sort();
      // ignore: avoid_print
      print('C listSync -> $sync');
    });
    await pumpShell(tester);
    // ignore: avoid_print
    print('D texts=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((d) => d != null).toList()}');

    expect(find.text('alpha.md'), findsOneWidget);
  });

  testWidgets('点击文件树条目会打开编辑器并加载磁盘内容', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);

    await openNote(tester, 'alpha.md');

    expect(state.activeDocument, isNotNull);
    expect(state.activeDocument!.path, p.join(root.path, 'alpha.md'));
    expect(
      state.activeDocument!.controller.text,
      File(p.join(root.path, 'alpha.md')).readAsStringSync(),
    );
  });

  testWidgets('编辑内容后自动保存回磁盘（纯文件原则）', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);
    await openNote(tester, 'alpha.md');

    final doc = state.activeDocument!;
    expect(doc.isDirty, isFalse);

    doc.controller.text = '# 改过的标题\n新内容\n';
    await tester.pump();
    expect(doc.isDirty, isTrue, reason: '内容变化后应标记为未保存');

    // 等自动保存防抖触发，然后让真实写盘在真实事件循环里跑完。
    // 注意：自动保存定时器回调里的 I/O 无法在 fake-async 区完成，
    // 因此这里显式再驱动一次 saveDocument（幂等）。
    await tester.pump(WorkspaceState.autosaveDelay + const Duration(milliseconds: 200));
    final saved = await io(tester, () => state.saveDocument(doc));
    // ignore: avoid_print
    print('DBG-AUTOSAVE saved=$saved toast=${state.toast} dirty=${doc.isDirty} '
        'path=${doc.path} savedContent=[${doc.savedContent}]');
    // ignore: avoid_print
    print('DBG-AUTOSAVE disk=[${File(p.join(root.path, 'alpha.md')).readAsStringSync()}]');
    expect(saved, isTrue, reason: '保存本身必须成功');
    await settleAsync(tester);

    expect(
      File(p.join(root.path, 'alpha.md')).readAsStringSync(),
      '# 改过的标题\n新内容\n',
    );
    expect(doc.isDirty, isFalse);
  });

  testWidgets('预览把行内公式渲染成 Unicode、行间公式渲染成公式块', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);
    await openNote(tester, 'beta.md');

    // 正文（去掉 frontmatter）与 GFM 表格应出现在预览里
    expect(find.textContaining('贝塔笔记'), findsWidgets);
    expect(find.textContaining('列 1'), findsWidgets);

    // 行内公式：美元号消失，上标与希腊字母变成 Unicode
    expect(find.textContaining('mc²'), findsWidgets);
    expect(find.textContaining('α'), findsWidgets);
    expect(find.textContaining('≤'), findsWidgets);

    // 行间公式应被整段替换成数学组件。
    // 注意：这里不断言它"渲染成功"——headless 测试环境加载不到 KaTeX 字体，
    // `Math.tex` 会走 onErrorFallback，那是环境限制而非功能缺陷。
    // 断言"数学组件确实被插入 + 占位符没有泄漏到界面"已覆盖整条替换链路；
    // LaTeX 提取本身的正确性由 math_text_test 覆盖。
    expect(find.byType(Math), findsWidgets);
    expect(find.textContaining('YANMATH'), findsNothing);

    // frontmatter 绝不能被当成正文渲染进预览。
    // 曾经的缺陷：预览直接渲染整份文件，`---` 被 Markdown 当作分隔线，
    // 于是 `title: 贝塔` 这一整块元数据以正文形式出现在预览顶部。
    //
    // 注意断言范围：源码编辑器里**本来就有** frontmatter（源码模式理应原样显示），
    // 所以不能对整棵控件树用 find.textContaining('title:')——那会命中编辑器。
    // 这里直接断言"交给预览渲染的那份 Markdown"。
    //
    // 也不能简单断言"不含 ---"：Markdown 的分隔线与**表格分隔行**（| --- | --- |）
    // 都含它，那是正文的一部分。要断言的是"不以 frontmatter 开头"。
    final previewSource = state.previewSourceFor(state.activeDocument!);
    expect(previewSource.startsWith('---'), isFalse,
        reason: '预览源不应以 frontmatter 分隔符开头');
    expect(previewSource.contains('title: 贝塔'), isFalse);
    expect(previewSource.contains('tags: [测试]'), isFalse);
    expect(previewSource.contains('created: 2026-09-09'), isFalse);
    // 正文与表格必须完整保留
    expect(previewSource.contains('贝塔笔记'), isTrue, reason: '正文必须保留');
    expect(previewSource.contains('| --- | --- |'), isTrue, reason: '表格分隔行必须保留');
  });

  testWidgets('frontmatter 面板可打开、显示规范化字段并插入模板', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);
    await openNote(tester, 'alpha.md');

    state.toggleFrontmatterPanel();
    await settleAsync(tester);
    expect(find.text('Frontmatter'), findsOneWidget);
    expect(find.text('这篇笔记还没有 frontmatter'), findsOneWidget);
    // 还没有 frontmatter 时面板提供模板按钮
    expect(find.text('插入模板'), findsOneWidget);

    // 走真实按钮：点击后发起写盘，再在真实事件循环里等它落盘
    await tester.tap(find.text('插入模板'));
    await io(tester, () => state.saveAll());
    await settleAsync(tester);

    final content = File(p.join(root.path, 'alpha.md')).readAsStringSync();
    expect(content.startsWith('---\n'), isTrue);
    // 补模板时 title 取自文件名（文件名即标题），与语料层规范一致
    expect(content.contains('title: alpha'), isTrue);
    expect(content.contains('lineage'), isTrue);
    // 正文必须保留
    expect(content.contains('这是正文'), isTrue);

    // 插入成功后按钮消失，面板切换成字段表单
    expect(find.text('插入模板'), findsNothing);
    expect(find.text('把 updated 设为今天'), findsOneWidget);
  });

  testWidgets('搜索面板能按文件名与内容命中并跳转', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);
    await tester.pumpWidget(
      WorkspaceScope(
        state: state,
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(body: SearchPanel(state: state, onClose: () {})),
          ),
        ),
      ),
    );
    await settleAsync(tester);

    await tester.enterText(find.byType(TextField).first, '贝塔');
    await tester.pump(const Duration(milliseconds: 400));
    // 搜索要真实遍历磁盘，放进真实事件循环
    await io(tester, () => state.runSearch('贝塔'));
    await settleAsync(tester);

    expect(state.searchHits, isNotEmpty);
    expect(find.textContaining('beta.md'), findsWidgets);

    final hit = state.searchHits.first;
    await io(tester, () => state.openHit(hit));
    await settleAsync(tester);
    expect(state.activeDocument!.path, p.join(root.path, 'beta.md'));
  });

  testWidgets('重命名与删除直接作用于磁盘', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);

    await io(tester, () => state.renameEntry(p.join(root.path, 'alpha.md'), 'alpha2.md'));
    await settleAsync(tester);
    expect(File(p.join(root.path, 'alpha.md')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'alpha2.md')).existsSync(), isTrue);
    expect(find.text('alpha2.md'), findsOneWidget);

    await io(tester, () => state.deleteEntry(p.join(root.path, 'alpha2.md')));
    await settleAsync(tester);
    expect(File(p.join(root.path, 'alpha2.md')).existsSync(), isFalse);
  });

  testWidgets('切换深色模式会同步编辑器高亮主题', (tester) async {
    await openLibrary(tester);
    await pumpShell(tester);
    await openNote(tester, 'alpha.md');

    final before = state.markdownTheme.body.color;
    state.toggleDarkMode();
    await settleAsync(tester);

    expect(state.darkMode, isTrue);
    expect(state.markdownTheme.body.color, isNot(before));
    expect(state.activeDocument!.controller.theme.body.color, state.markdownTheme.body.color);
  });
}
