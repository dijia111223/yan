import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'ai_model_spec.dart';

/// 下载过程中对外的状态。界面上要显示进度，所以每一步都要能报出来。
enum AiDownloadPhase {
  /// 还没开始
  idle,

  /// 正在检查已下载的部分 / 已有文件是否可用
  checking,

  /// 正在下载
  downloading,

  /// 正在校验完整性（大文件要几秒）
  verifying,

  /// 已就绪
  ready,

  /// 失败，[AiDownloadState.message] 说明原因
  failed,
}

class AiDownloadState {
  const AiDownloadState({
    required this.phase,
    this.received = 0,
    this.total = 0,
    this.message = '',
    this.resumed = false,
  });

  final AiDownloadPhase phase;
  final int received;
  final int total;
  final String message;

  /// 本次是否是断点续传（而不是从头下）。
  final bool resumed;

  bool get isDone => phase == AiDownloadPhase.ready;

  /// 0.0–1.0；总长度未知时返回 null（界面应显示不确定进度条）。
  double? get progress {
    if (total <= 0) return null;
    final v = received / total;
    return v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  AiDownloadState copyWith({
    AiDownloadPhase? phase,
    int? received,
    int? total,
    String? message,
    bool? resumed,
  }) {
    return AiDownloadState(
      phase: phase ?? this.phase,
      received: received ?? this.received,
      total: total ?? this.total,
      message: message ?? this.message,
      resumed: resumed ?? this.resumed,
    );
  }
}

/// 下载模型文件，支持断点续传与完整性校验。
///
/// 三个非显然的设计点：
///
/// 1. **下载与校验都在后台 isolate 里跑**。378 MB 的 SHA-256 在主 isolate 上
///    要几秒，会让界面直接卡住。Dart 的 `HttpClient` 在 isolate 里能正常用。
/// 2. **先写 `.part`，校验通过才改名**。否则一次中断会留下一个"看起来存在但内容不全"
///    的正式文件，下次启动会拿它去加载，表现为莫名其妙的加载失败。
/// 3. **体积对不上就不算完成**。服务端返回的文件长度是最便宜的一致性检查，
///    先比长度再算摘要，能省掉大部分无用功。
class AiModelDownloader {
  AiModelDownloader({
    required String modelPath,
    this.spec = kQwen3Model,
    this.onState,
  }) : modelFile = File(modelPath);

  /// 模型最终的完整路径。目录由上层决定（鸿蒙走沙箱、桌面走用户目录），
  /// 所以这里只收路径，不去猜平台差异。
  final File modelFile;
  final AiModelSpec spec;

  /// 状态回调。注意可能在后台 isolate 之外被调用，界面侧要确保切回主 isolate。
  final void Function(AiDownloadState)? onState;

  Directory get dir => modelFile.parent;

  File get partFile => File('${modelFile.path}.part');

  AiModelSpec get modelSpec => spec;

  /// 已装好的模型是否可用（存在且体积正确）。
  bool get isInstalled {
    final f = modelFile;
    return f.existsSync() && f.lengthSync() == spec.sizeBytes;
  }

  /// 下载（或续传）到就绪。返回最终状态。
  Future<AiDownloadState> download() async {
    _emit(const AiDownloadState(phase: AiDownloadPhase.checking));

    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } on FileSystemException catch (e) {
        return _fail('无法创建模型目录：${e.message}');
      }
    }

    // 已经装好了就直接用，不重复下载
    if (isInstalled) {
      final ok = await _verifyDigest(modelFile.path, spec.sha256);
      if (ok) {
        return _emit(AiDownloadState(
          phase: AiDownloadPhase.ready,
          received: spec.sizeBytes,
          total: spec.sizeBytes,
        ),);
      }
      // 体积对但摘要不对：文件是坏的，删掉重下
      _safeDelete(modelFile);
    }

    // 体积已经对但还没校验过的情况由上面处理；这里处理 .part 续传
    int startAt = resumeOffset(partLength: _lengthOf(partFile), expected: spec.sizeBytes);

    Object? lastError;
    for (final url in spec.allUrls) {
      try {
        final result = await _runInIsolate(
          url: url,
          partPath: partFile.path,
          startAt: startAt,
        );
        if (result.error != null) {
          lastError = result.error;
          continue;   // 换下一个源
        }

        _emit(AiDownloadState(
          phase: AiDownloadPhase.verifying,
          received: result.received,
          total: spec.sizeBytes,
        ),);
        final ok = await _verifyDigest(partFile.path, spec.sha256);
        if (!ok) {
          lastError = '下载内容校验失败（SHA-256 不匹配）';
          _safeDelete(partFile);
          startAt = 0;
          continue;
        }

        // 原子落位：校验通过才改名，中途失败不会留下半成品正式文件
        if (modelFile.existsSync()) _safeDelete(modelFile);
        partFile.renameSync(modelFile.path);

        return _emit(AiDownloadState(
          phase: AiDownloadPhase.ready,
          received: spec.sizeBytes,
          total: spec.sizeBytes,
        ),);
      } on Object catch (e) {
        lastError = e;
      }
    }

    return _fail('下载失败：$lastError');
  }

  /// 把下载放进独立 isolate。
  ///
  /// 传进去的必须是可跨 isolate 传递的值：路径用字符串、进度用 SendPort。
  Future<_DownloadOutcome> _runInIsolate({
    required String url,
    required String partPath,
    required int startAt,
  }) async {
    final port = ReceivePort();
    final completer = Completer<_DownloadOutcome>();

    port.listen((Object? msg) {
      if (msg is Map) {
        // 进度消息
        _emit(AiDownloadState(
          phase: AiDownloadPhase.downloading,
          received: (msg['received'] as int?) ?? 0,
          total: (msg['total'] as int?) ?? spec.sizeBytes,
          resumed: startAt > 0,
        ),);
        return;
      }
      if (msg is _DownloadOutcome) {
        if (!completer.isCompleted) completer.complete(msg);
        port.close();
      }
    });

    try {
      await Isolate.spawn(
        _downloadWorker,
        _DownloadJob(
          url: url,
          partPath: partPath,
          startAt: startAt,
          sendPort: port.sendPort,
        ),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
    } on Object catch (e) {
      port.close();
      return _DownloadOutcome(error: '无法启动下载任务：$e');
    }

    return completer.future;
  }

  Future<bool> _verifyDigest(String path, String expected) async {
    if (expected.isEmpty) {
      // 没配摘要时退化为体积检查 —— 至少能挡住截断的文件
      final f = File(path);
      return f.existsSync() && f.lengthSync() == spec.sizeBytes;
    }
    try {
      return await Isolate.run(() async {
        final f = File(path);
        if (!f.existsSync()) return false;
        final digest = await sha256.bind(f.openRead()).first;
        return digest.toString() == expected;
      });
    } on Object {
      return false;
    }
  }

  AiDownloadState _emit(AiDownloadState s) {
    onState?.call(s);
    return s;
  }

  AiDownloadState _fail(String message) =>
      _emit(AiDownloadState(phase: AiDownloadPhase.failed, message: message));

  int _lengthOf(File f) {
    try {
      return f.existsSync() ? f.lengthSync() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  void _safeDelete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // 删不掉不影响主流程：后续体积校验会挡住它
    }
  }
}

class _DownloadJob {
  const _DownloadJob({
    required this.url,
    required this.partPath,
    required this.startAt,
    required this.sendPort,
  });

  final String url;
  final String partPath;
  final int startAt;
  final SendPort sendPort;
}

class _DownloadOutcome {
  const _DownloadOutcome({this.received = 0, this.error});

  final int received;
  final String? error;
}

/// 运行在独立 isolate 里的下载主体。
///
/// 用 `HttpClient` 而不是 `package:http`：Range 头、流式读取和超时控制都要手写，
/// 而 HttpClient 本来就提供这些，少一层包装少一处意外。
Future<void> _downloadWorker(_DownloadJob job) async {
  final client = HttpClient();
  IOSink? sink;
  try {
    final req = await client.getUrl(Uri.parse(job.url));
    if (job.startAt > 0) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=${job.startAt}-');
    }
    final resp = await req.close();

    // 206 才是续传成功；服务端不支持 Range 会回 200，那就得从头写
    final isPartial = resp.statusCode == HttpStatus.partialContent;
    final startAt = isPartial ? job.startAt : 0;
    if (resp.statusCode != HttpStatus.ok && !isPartial) {
      job.sendPort.send(_DownloadOutcome(
        error: 'HTTP ${resp.statusCode}',
      ),);
      return;
    }

    final contentLength = resp.contentLength;
    final total = contentLength > 0 ? startAt + contentLength : 0;

    final file = File(job.partPath);
    sink = file.openWrite(
      mode: startAt > 0 ? FileMode.append : FileMode.write,
    );

    var received = startAt;
    var lastReport = DateTime.now();
    await for (final chunk in resp) {
      sink.add(chunk);
      received += chunk.length;
      // 节流上报：每个 chunk 都发消息会把 isolate 通信变成瓶颈
      final now = DateTime.now();
      if (now.difference(lastReport).inMilliseconds >= 200) {
        lastReport = now;
        job.sendPort.send(<String, int>{'received': received, 'total': total});
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;

    job.sendPort.send(_DownloadOutcome(received: received));
  } on Object catch (e) {
    try {
      await sink?.close();
    } on Object {
      // 关闭失败无所谓，调用方会用体积校验兜住
    }
    job.sendPort.send(_DownloadOutcome(error: '$e'));
  } finally {
    client.close(force: true);
  }
}

/// 从多少字节处续传。
///
/// 单独抽成纯函数是因为这里有三个边界情况，都值得单测而不用真去下载 378 MB：
/// * 没有 `.part`（或长度为 0）→ 从头下
/// * `.part` 比目标还大 → 文件是坏的，必须从头下，否则会写出一个永远对不上的文件
/// * `.part` 恰好等于目标 → 不必再下，交给摘要校验判断
int resumeOffset({required int partLength, required int expected}) {
  if (partLength <= 0) return 0;
  if (partLength > expected) return 0;
  return partLength;
}

/// 把字节数格式化成易读文本。界面直接用。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// 把下载状态压成一行给人看的文字。
String describeDownload(AiDownloadState s) {
  switch (s.phase) {
    case AiDownloadPhase.idle:
      return '尚未下载';
    case AiDownloadPhase.checking:
      return '正在检查已下载的内容…';
    case AiDownloadPhase.downloading:
      final p = s.progress;
      final head = s.resumed ? '续传中' : '下载中';
      if (p == null) return '$head ${formatBytes(s.received)}';
      return '$head ${(p * 100).toStringAsFixed(0)}%'
          '（${formatBytes(s.received)} / ${formatBytes(s.total)}）';
    case AiDownloadPhase.verifying:
      return '正在校验完整性…';
    case AiDownloadPhase.ready:
      return '已就绪';
    case AiDownloadPhase.failed:
      return s.message.isEmpty ? '下载失败' : s.message;
  }
}

/// 供测试与诊断：把一段文本的 SHA-256 算出来（与下载校验同一套实现）。
Future<String> sha256OfText(String text) async {
  return sha256.convert(utf8.encode(text)).toString();
}
