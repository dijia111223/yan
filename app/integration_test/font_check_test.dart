import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yan_note/app.dart';
import 'package:yan_note/src/core/typography.dart';

/// 黑体生效性判定：跑在真实 Windows 应用进程里。
///
/// 判定思路（宽度指纹法）
/// --------------------
/// 在本机实测三个族名对同一段中英混排文本的**固有渲染宽度**：
///   Microsoft YaHei = 640.0
///   SimHei / SimSun = 620.0（汉字全角，两者推进宽度相同）
///   「不存在的族名」   = 633.50（引擎回落后的默认字体）
///
/// 因此宽度本身就是**指纹**：
///   * 应用正文字体宽度 == 620.0  → 黑体（或宋体）生效
///   * 应用正文字体宽度 == 640.0  → 回落到了雅黑
///   * 应用正文字体宽度 == 633.50 → 回落到了引擎默认字体
/// 只要不是后两者，就证明 `SimHei` 这个族名确实被解析到了。
///
/// 测量必须用 [TextPainter] 取**文本固有宽度**。用 `tester.getSize(find.byType(Text))`
/// 量到的是父级约束宽度（放进 Center 就是整屏宽），会得到恒定的假结果。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 文本固有宽度（不经过 widget 树，避免被父级约束污染）。
  double intrinsicWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  testWidgets('黑体族名已被引擎解析（宽度指纹判定）', (tester) async {
    const sample = '黑体渲染度量探针汉字宽度测试ABC';
    const size = 40.0;

    final yahei = intrinsicWidth(sample, const TextStyle(fontFamily: 'Microsoft YaHei', fontSize: size));
    final bogus = intrinsicWidth(sample, const TextStyle(fontFamily: 'NonexistentFontXYZ', fontSize: size));
    final simhei = intrinsicWidth(
      sample,
      const TextStyle(fontFamily: AppFonts.body, fontFamilyFallback: AppFonts.fallback, fontSize: size),
    );

    // ignore: avoid_print
    print('FONT-FP fingerprint: YaHei=$yahei  bogus=$bogus  AppFonts.body(${AppFonts.body})=$simhei');

    // 前置有效性：雅黑与默认回落必须不同，否则这套指纹法不成立
    expect(
      (yahei - bogus).abs() > 0.5,
      isTrue,
      reason: '雅黑与默认回落字体宽度应不同，否则宽度指纹法不可用',
    );

    // 核心判定：应用的正文族名不能落到"雅黑"或"引擎默认"这两个指纹上
    final looksLikeYaHei = (simhei - yahei).abs() < 0.01;
    final looksLikeDefault = (simhei - bogus).abs() < 0.01;
    // ignore: avoid_print
    print('FONT-FP verdict: matchesYaHei=$looksLikeYaHei  matchesDefaultFallback=$looksLikeDefault');

    expect(
      looksLikeYaHei || looksLikeDefault,
      isFalse,
      reason: 'AppFonts.body("${AppFonts.body}") 的固有宽度与雅黑/引擎默认字体一致，'
          '说明该族名没有被解析、发生了静默回落。'
          '（body=$simhei, YaHei=$yahei, default=$bogus）',
    );

    // 主题层：确认全应用声明的就是黑体，并带跨平台回落链
    await tester.pumpWidget(const YanApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    // ignore: avoid_print
    print('FONT-FP theme bodyMedium.fontFamily = ${theme.textTheme.bodyMedium?.fontFamily}');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'SimHei');
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, contains('Microsoft YaHei'));
    expect(theme.textTheme.titleLarge?.fontFamily, 'SimHei');
    expect(theme.textTheme.labelSmall?.fontFamily, 'SimHei');
  });

  testWidgets('等宽字体是真正的等宽，且未污染正文', (tester) async {
    const size = 40.0;
    final codeStyle = AppFonts.monoStyle(const TextStyle(fontSize: size));
    final bodyStyle = AppFonts.bodyStyle(const TextStyle(fontSize: size));

    // 等宽判据：等宽字体里**所有字形推进宽度相同**，包括窄的 i 与宽的 W
    final codeI = intrinsicWidth('iiii', codeStyle);
    final codeW = intrinsicWidth('WWWW', codeStyle);
    // ignore: avoid_print
    print('FONT-FP mono(${AppFonts.mono}) 4xi=$codeI  4xW=$codeW');

    expect(
      (codeI - codeW).abs() < 0.5,
      isTrue,
      reason: '等宽字体里 4xi 应等于 4xW（实际 $codeI vs $codeW）',
    );

    // 等宽字体必须有**区别度**：'i' 与 'W' 若是全角（CJK 回落），宽度会明显更胖。
    // 用"每个字符的推进宽度相对字号的比值"判断：真正等宽字体约 0.5–0.65 em，
    // 而 CJK 全角回落会到 1.0 em。
    final emRatio = codeI / 4 / size;
    // ignore: avoid_print
    print('FONT-FP mono 每字符 em 比值 = ${emRatio.toStringAsFixed(3)}');
    expect(
      emRatio < 0.8,
      isTrue,
      reason: '等宽字体每字符宽度为 ${emRatio.toStringAsFixed(3)} em，接近 1.0 说明回落成了全角 CJK 字体',
    );

    // 正文（黑体）与代码字体必须是两份不同字体。
    //
    // 判据用**拉丁字母**而不是汉字：Consolas 本就没有汉字字形，渲染汉字时会
    // 正常回落到中文字体——那是正确行为，拿汉字比宽度得不到有效区分。
    // 拉丁字母则各自有字形，宽度差异能直接反映字体身份。
    const latin = 'MMMMMMMMMM';
    final bodyLatin = intrinsicWidth(latin, bodyStyle);
    final codeLatin = intrinsicWidth(latin, codeStyle);
    // ignore: avoid_print
    print('FONT-FP 同一段拉丁文: body=${AppFonts.body}->$bodyLatin  mono=${AppFonts.mono}->$codeLatin');

    expect(
      (bodyLatin - codeLatin).abs() > 0.01,
      isTrue,
      reason: '正文与代码字体渲染同一段拉丁字母的宽度完全相同，说明两者其实回落到了同一份字体',
    );

    // 正文汉字应为全角推进（约 1.0 em）
    const cjk = '汉字宽度对比测试';
    final bodyCjk = intrinsicWidth(cjk, bodyStyle);
    final bodyEmRatio = bodyCjk / cjk.length / size;
    // ignore: avoid_print
    print('FONT-FP body 汉字 em 比值 = ${bodyEmRatio.toStringAsFixed(3)}');
    expect(
      bodyEmRatio > 0.9,
      isTrue,
      reason: '汉字应为全角推进（约 1.0 em），实际 ${bodyEmRatio.toStringAsFixed(3)} em',
    );
  });
}
