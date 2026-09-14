// 模型下载的边界测试。
//
// 真去下 378 MB 不现实，所以这里钉住的是**纯逻辑**部分：
// 续传偏移的三个边界、体积校验、状态展示文案。
// 这些都对应真实会出问题的地方 —— 尤其是"坏 .part 文件不能拿来续传"，
// 踩过的后果是写出一个永远校验不过的文件。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yan_note/src/core/ai_model_download.dart';
import 'package:yan_note/src/core/ai_model_spec.dart';

void main() {
  group('续传偏移', () {
    const expected = 1000;

    test('没有 .part 时从头下', () {
      expect(resumeOffset(partLength: 0, expected: expected), 0);
    });

    test('有部分内容时从断点继续', () {
      expect(resumeOffset(partLength: 400, expected: expected), 400);
    });

    test('.part 恰好等于目标时不再续传（交给摘要校验判断）', () {
      expect(resumeOffset(partLength: expected, expected: expected), expected);
    });

    test('.part 比目标还大说明是坏文件，必须从头下', () {
      // 若在此基础续传，服务端会回 416，或写出长度永远对不上的文件
      expect(resumeOffset(partLength: expected + 1, expected: expected), 0);
    });

    test('负数长度（异常情况）按从头下处理', () {
      expect(resumeOffset(partLength: -5, expected: expected), 0);
    });
  });

  group('体积与就绪判定', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('yan_model_test'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    // 用一个小规格做测试，避免真的创建 378 MB 文件
    const spec = AiModelSpec(
      id: 'test',
      displayName: '测试模型',
      fileName: 'test.gguf',
      downloadUrl: 'https://example.invalid/test.gguf',
      mirrorUrls: <String>[],
      sizeBytes: 8,
      sha256: '',
    );

    test('文件不存在时不算就绪', () {
      final d = AiModelDownloader(
        modelPath: '${dir.path}${Platform.pathSeparator}test.gguf',
        spec: spec,
      );
      expect(d.isInstalled, isFalse);
    });

    test('体积不对不算就绪（挡住截断的下载）', () {
      final d = AiModelDownloader(
        modelPath: '${dir.path}${Platform.pathSeparator}test.gguf',
        spec: spec,
      );
      File(d.modelFile.path).writeAsBytesSync(List<int>.filled(5, 0));
      expect(d.isInstalled, isFalse);
    });

    test('体积正确就算就绪', () {
      final d = AiModelDownloader(
        modelPath: '${dir.path}${Platform.pathSeparator}test.gguf',
        spec: spec,
      );
      File(d.modelFile.path).writeAsBytesSync(List<int>.filled(8, 0));
      expect(d.isInstalled, isTrue);
    });

    test('正式文件与 .part 是两个不同路径', () {
      final d = AiModelDownloader(
        modelPath: '${dir.path}${Platform.pathSeparator}test.gguf',
        spec: spec,
      );
      expect(d.partFile.path, isNot(d.modelFile.path));
      expect(d.partFile.path, endsWith('.part'));
    });
  });

  group('状态展示文案', () {
    test('未知总长度时不显示百分比', () {
      const s = AiDownloadState(
        phase: AiDownloadPhase.downloading,
        received: 1024,
        total: 0,
      );
      expect(s.progress, isNull);
      final text = describeDownload(s);
      expect(text, contains('下载中'));
      expect(text, isNot(contains('%')));
    });

    test('已知总长度时显示百分比与两端体积', () {
      const s = AiDownloadState(
        phase: AiDownloadPhase.downloading,
        received: 50,
        total: 100,
      );
      expect(s.progress, 0.5);
      final text = describeDownload(s);
      expect(text, contains('50%'));
    });

    test('续传状态会被标注出来', () {
      const s = AiDownloadState(
        phase: AiDownloadPhase.downloading,
        received: 50,
        total: 100,
        resumed: true,
      );
      expect(describeDownload(s), contains('续传'));
    });

    test('进度不会越界（服务端给的长度可能不准）', () {
      const over = AiDownloadState(
        phase: AiDownloadPhase.downloading,
        received: 200,
        total: 100,
      );
      expect(over.progress, 1.0);
    });

    test('失败时优先显示具体原因', () {
      const s = AiDownloadState(
        phase: AiDownloadPhase.failed,
        message: 'HTTP 404',
      );
      expect(describeDownload(s), 'HTTP 404');
    });
  });

  group('体积格式化', () {
    test('各量级都有合适单位', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });
  });

  group('默认模型规格', () {
    test('体积与实测的 gguf 一致', () {
      // 探针与桥接层的设备实测都用这个文件，写错会导致每次都判定"需要重下"
      expect(kQwen3Model.sizeBytes, 396705472);
    });

    test('配了摘要与备用源', () {
      expect(kQwen3Model.sha256.length, 64);
      // 国内直连 HuggingFace 经常不通，备用源是必需的而不是可选
      expect(kQwen3Model.mirrorUrls, isNotEmpty);
      expect(kQwen3Model.allUrls.length, greaterThanOrEqualTo(2));
    });
  });
}
