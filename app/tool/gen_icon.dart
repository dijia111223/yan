// 生成应用图标 PNG。
//
// 为什么要自己生成：鸿蒙工程的图标是 flutter create 从模板拷来的 Flutter 默认图标
// （44×44 蓝色 F 标志），上架时会被驳回。
//
// 用 dart:ui 直接画而不是引图片库：Flutter 自带 Canvas 与字体渲染，
// 中文「砚」字能正确出字形，也不需要额外依赖。
//
// 运行（不是单元测试，只是借 flutter test 的运行时）：
//     flutter test tool/gen_icon.dart
// 输出：assets/icon/icon.png（1024×1024，供各平台缩放取用）

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _brand = Color(0xFF2F6F62);
const String _glyph = '砚';

/// 测试环境只有测试字体，系统字体得自己塞进去；否则中文会渲染成豆腐块。
Future<bool> _loadCjkFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final loader = FontLoader('YanIconFont')
      ..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    stdout.writeln('loaded font: $path');
    return true;
  }
  return false;
}

Future<void> _render(String path, int size, {required bool round}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();

  final paint = Paint()..color = _brand;
  if (round) {
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, paint);
  } else {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)),
      paint,
    );
  }

  final painter = TextPainter(
    text: TextSpan(
      text: _glyph,
      style: TextStyle(
        color: Colors.white,
        fontSize: s * 0.62,
        fontFamily: 'YanIconFont',
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset((s - painter.width) / 2, (s - painter.height) / 2),
  );

  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  stdout.writeln('wrote $path  (${size}x${size}, text ${painter.width.toStringAsFixed(0)}x${painter.height.toStringAsFixed(0)})');
}

void main() {
  test('生成应用图标', () async {
    final ok = await _loadCjkFont();
    if (!ok) {
      fail('找不到可用的中文字体，图标上的「砚」会渲染成豆腐块');
    }
    // 单张 1024 方图：鸿蒙 AppScope 用方形，各平台自行缩放
    await _render('assets/icon/icon.png', 1024, round: false);
    // 圆形版本，部分商店/桌面场景需要
    await _render('assets/icon/icon_round.png', 1024, round: true);
    expect(File('assets/icon/icon.png').existsSync(), isTrue);
  });
}
