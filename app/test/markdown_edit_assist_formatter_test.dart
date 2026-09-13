// 验证编辑增强真的接在 TextField 上。
//
// 纯逻辑测试（markdown_edit_assist_test.dart）覆盖了规则本身，但覆盖不到
// "格式化器有没有挂上去" —— 这一层最容易出现"逻辑对了但没生效"。
//
// 注意：只走 TextInputFormatter 这条路径。输入法组合中（中文拼音未上屏）
// 格式化器会主动不介入，那条路径不在此测。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/markdown_edit_assist_formatter.dart';

void main() {
  late TextEditingController controller;
  final field = find.byType(TextField);

  Future<void> mount(WidgetTester tester, {String initial = ''}) async {
    controller = TextEditingController(text: initial);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            maxLines: null,
            inputFormatters: const <TextInputFormatter>[
              MarkdownEditAssistFormatter(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(() => controller.dispose());

  testWidgets('列表里回车会续上标记', (tester) async {
    await mount(tester, initial: '- 甲');
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await tester.enterText(field, '- 甲\n');
    await tester.pump();

    expect(controller.text, '- 甲\n- ');
  });

  testWidgets('普通段落回车不介入', (tester) async {
    await mount(tester, initial: '普通');
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.enterText(field, '普通\n');
    await tester.pump();

    expect(controller.text, '普通\n');
  });

  testWidgets('行首反引号直接给出成对围栏', (tester) async {
    await mount(tester);
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.enterText(field, '`');
    await tester.pump();

    expect(controller.text, '```\n\n```');
    expect(controller.selection.baseOffset, 4);
  });

  testWidgets('输入星号补成一对并把光标放中间', (tester) async {
    await mount(tester, initial: 'ab');
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.enterText(field, 'ab*');
    await tester.pump();

    expect(controller.text, 'ab**');
    expect(controller.selection.baseOffset, 3);
  });
}
