import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// 补全结束的原因。与原生侧 `StopReason` 一一对应。
enum AiStopReason {
  eog,
  stopString,
  repeat,
  maxTokens,
  cancelled,
  error,
  unknown;

  static AiStopReason fromCode(int code) {
    switch (code) {
      case 0:
        return AiStopReason.eog;
      case 1:
        return AiStopReason.stopString;
      case 2:
        return AiStopReason.repeat;
      case 3:
        return AiStopReason.maxTokens;
      case 4:
        return AiStopReason.cancelled;
      case 5:
        return AiStopReason.error;
      default:
        return AiStopReason.unknown;
    }
  }
}

class AiCompletion {
  const AiCompletion({
    required this.text,
    required this.reason,
    required this.ok,
    this.message = '',
  });

  final String text;
  final AiStopReason reason;

  /// 原生调用是否成功（模型没加载、prefill 失败等都会是 false）。
  final bool ok;
  final String message;

  static const AiCompletion unavailable = AiCompletion(
    text: '',
    reason: AiStopReason.unknown,
    ok: false,
    message: '端侧模型不可用',
  );
}

/// `libyan_ai.so`（鸿蒙）/ `yan_ai.dll`（桌面）的绑定。
///
/// 只做一件事：把 `yan_ai.h` 的 5 个接口映射出来。所有调用都是**阻塞**的，
/// 所以不要在 UI isolate 里直接调 —— 用 [AiNativeSession]。
class AiNativeBindings {
  AiNativeBindings(this._lib);

  final DynamicLibrary _lib;

  /// 尝试加载原生库。加载不到返回 null（桌面端没构建、或鸿蒙上打包遗漏），
  /// 由调用方决定如何降级 —— 端侧补全是可选功能，缺了不该让应用起不来。
  static AiNativeBindings? tryLoad() {
    final DynamicLibrary lib;
    try {
      if (Platform.isWindows) {
        lib = DynamicLibrary.open('yan_ai.dll');
      } else if (Platform.operatingSystem == 'ohos' || Platform.isLinux) {
        // 鸿蒙上由 HAR 的 CMake 构建产出并随 hap 打包，运行时按名字加载
        lib = DynamicLibrary.open('libyan_ai.so');
      } else {
        return null;
      }
    } on Object {
      return null;
    }
    return AiNativeBindings(lib);
  }

  late final int Function(Pointer<Utf8>, Pointer<_Config>, Pointer<_Error>)
      _load = _lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<_Config>, Pointer<_Error>),
          int Function(Pointer<Utf8>, Pointer<_Config>, Pointer<_Error>)>(
      'yan_ai_load',
    );

  late final void Function() _unload =
      _lib.lookupFunction<Void Function(), void Function()>('yan_ai_unload');

  late final int Function() _isLoaded = _lib
      .lookupFunction<Int32 Function(), int Function()>('yan_ai_is_loaded');

  late final void Function() _cancel = _lib
      .lookupFunction<Void Function(), void Function()>('yan_ai_cancel');

  late final int Function(
    Pointer<Utf8>,
    Pointer<_Params>,
    Pointer<Utf8>,
    int,
    Pointer<NativeFunction<_TokenFn>>,
    Pointer<Void>,
    Pointer<_Error>,
  ) _complete = _lib.lookupFunction<
      Int32 Function(
        Pointer<Utf8>,
        Pointer<_Params>,
        Pointer<Utf8>,
        Int32,
        Pointer<NativeFunction<_TokenFn>>,
        Pointer<Void>,
        Pointer<_Error>,
      ),
      int Function(
        Pointer<Utf8>,
        Pointer<_Params>,
        Pointer<Utf8>,
        int,
        Pointer<NativeFunction<_TokenFn>>,
        Pointer<Void>,
        Pointer<_Error>,
      )>('yan_ai_complete');

  bool get isLoaded => _isLoaded() == 1;

  /// 加载模型。返回空字符串表示成功，否则是错误信息。
  String load(String modelPath) {
    final p = modelPath.toNativeUtf8();
    final cfg = calloc<_Config>();
    final err = calloc<_Error>();
    try {
      cfg.ref.nCtx = 512;
      cfg.ref.nBatch = 128;
      cfg.ref.nThreads = 4;
      cfg.ref.reserved = 0;
      final rc = _load(p, cfg, err);
      return rc != 0 ? _readMessage(err, '加载失败（code=$rc）') : '';
    } finally {
      calloc.free(p);
      calloc.free(cfg);
      calloc.free(err);
    }
  }

  void unload() => _unload();

  /// 从**其它线程**打断正在进行的生成。这正是它存在的意义：
  /// 生成线程自己不可能响应取消（它正阻塞在原生调用里）。
  void cancel() => _cancel();

  /// 同步补全。返回整段生成的文本。
  ///
  /// 为什么不在这里逐 token 回调出去：`Pointer.fromFunction` **不接受闭包**
  /// （不能捕获状态），而这段代码本来就跑在独立 isolate 里、结果也传不回 UI，
  /// 所以逐 token 回调没有实际用途 —— 结果由原生写进我们提供的缓冲区。
  AiCompletion completeSync(String prefix, int maxTokens) {
    const outCap = 4096;   // 补全上限 24 token，4 KB 足够富裕
    final p = prefix.toNativeUtf8();
    final params = calloc<_Params>();
    final err = calloc<_Error>();
    final out = calloc<Uint8>(outCap);

    try {
      params.ref.maxTokens = maxTokens;
      params.ref.minTokens = 6;
      params.ref.reserved1 = 0;
      params.ref.reserved2 = 0;

      final rc = _complete(
        p,
        params,
        out.cast<Utf8>(),
        outCap,
        nullptr,   // 不要逐 token 回调
        nullptr,
        err,
      );
      final ok = rc >= 0 && rc <= 4;
      // 原生保证 NUL 结尾，所以按 C 字符串读到结尾即可
      final text = ok ? out.cast<Utf8>().toDartString() : '';
      return AiCompletion(
        text: text,
        reason: AiStopReason.fromCode(rc),
        ok: ok,
        message: ok ? '' : _readMessage(err, '补全失败（code=$rc）'),
      );
    } on Object catch (e) {
      return AiCompletion(
        text: '',
        reason: AiStopReason.error,
        ok: false,
        message: '$e',
      );
    } finally {
      calloc.free(p);
      calloc.free(params);
      calloc.free(out);
      calloc.free(err);
    }
  }

  String _readMessage(Pointer<_Error> err, String fallback) {
    try {
      final p = err.ref.message;
      if (p == nullptr) return fallback;
      final s = p.toDartString();
      return s.isEmpty ? fallback : s;
    } on Object {
      return fallback;
    }
  }
}

/// 与 `YanAiConfig` 对齐。
final class _Config extends Struct {
  @Int32()
  external int nCtx;

  @Int32()
  external int nBatch;

  @Int32()
  external int nThreads;

  @Int32()
  external int reserved;
}

/// 与 `YanAiParams` 对齐。
final class _Params extends Struct {
  @Int32()
  external int maxTokens;

  @Int32()
  external int minTokens;

  @Int32()
  external int reserved1;

  @Int32()
  external int reserved2;
}

/// 与 `YanAiError` 对齐：int code + const char * message。
///
/// message 是指针而不是内联数组 —— 内联数组在 dart:ffi 里要当 `Array<Uint8>`
/// 处理，取值得绕开 `.address` 只允许出现在 leaf native 调用里的限制，
/// 很容易写成硬编码结构体偏移。指针形式这边就是一行 toDartString()。
final class _Error extends Struct {
  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

typedef _TokenFn = Int32 Function(Pointer<Uint8>, Int32, Pointer<Void>);

/// 补全会话：把原生调用挡在独立 isolate 后面。
///
/// 为什么必须这么绕：
///
/// * 单次补全几百毫秒到几秒，直接在 UI isolate 上调 `yan_ai_complete` 会冻住界面。
/// * 模型又不能每个 isolate 各加载一份（378 MB × N），所以必须有一个**长驻** isolate
///   持有它，UI 侧只发请求。
///
/// 两个看起来该做、实际做不到的事（都是踩过的结论，别再去试）：
///
/// 1. **token 不能跨 isolate 流式回传**。工作 isolate 阻塞在 `yan_ai_complete`
///    里时，它自己的 ReceivePort 收不到消息 —— 事件循环被占住了。
///    所以补全是"发一次请求、拿一次最终结果"。
/// 2. **取消不能靠给工作 isolate 发消息**。同理它没空处理。
///    取消必须由**另一个** isolate 直接调 `yan_ai_cancel()`
///    （原生侧那个标志是进程级的），见 [_cancelMain]。
class AiNativeSession {
  AiNativeSession._(this._cmd, this._events, this._cancelCmd);

  final SendPort _cmd;
  final ReceivePort _events;
  final SendPort _cancelCmd;

  Isolate? _isolate;
  Isolate? _cancelIsolate;
  bool _disposed = false;
  Completer<AiCompletion>? _pending;
  int _requestId = 0;

  static Future<AiNativeSession?> spawn() async {
    final ready = ReceivePort();
    Isolate? worker;
    Isolate? canceller;
    try {
      worker = await Isolate.spawn(_sessionMain, ready.sendPort);
      final first = await ready.first;
      ready.close();
      if (first is! List || first.length < 2) {
        worker.kill();
        return null;
      }

      // 取消通道单独一个 isolate：生成线程正忙，只能从外部打断
      final cancelReady = ReceivePort();
      canceller = await Isolate.spawn(_cancelMain, cancelReady.sendPort);
      final cancelPort = await cancelReady.first;
      cancelReady.close();

      final session = AiNativeSession._(
        first[0] as SendPort,
        first[1] as ReceivePort,
        cancelPort as SendPort,
      );
      session._isolate = worker;
      session._cancelIsolate = canceller;
      session._events.listen(session._onEvent);
      return session;
    } on Object {
      ready.close();
      worker?.kill();
      canceller?.kill();
      return null;
    }
  }

  /// 原生库是否可用（模型未必已加载）。
  static Future<bool> nativeAvailable() async {
    final port = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_probeMain, port.sendPort);
      final ok = await port.first;
      isolate.kill();
      return ok == true;
    } on Object {
      return false;
    } finally {
      port.close();
    }
  }

  void _onEvent(Object? msg) {
    if (msg is! Map) return;
    final id = msg['id'] as int?;
    final completer = _pending;
    if (completer == null) return;
    // 过期回包直接丢掉：用户已经继续打字了，旧建议没有意义
    if (id != _requestId) return;
    _pending = null;
    if (!completer.isCompleted) {
      completer.complete(AiCompletion(
        text: (msg['text'] as String?) ?? '',
        reason: AiStopReason.fromCode((msg['reason'] as int?) ?? -1),
        ok: (msg['ok'] as bool?) ?? false,
        message: (msg['message'] as String?) ?? '',
      ),);
    }
  }

  /// 请求加载模型。返回空字符串表示成功。
  Future<String> load(String modelPath) {
    final port = ReceivePort();
    _cmd.send(<String, Object?>{
      'op': 'load',
      'path': modelPath,
      'reply': port.sendPort,
    });
    return port.first.then((Object? v) {
      port.close();
      return (v as String?) ?? '加载失败';
    });
  }

  Future<bool> get loaded async {
    final port = ReceivePort();
    _cmd.send(<String, Object?>{'op': 'loaded', 'reply': port.sendPort});
    final v = await port.first;
    port.close();
    return v == true;
  }

  /// 发起一次补全。同一时刻只保留最新一次请求。
  Future<AiCompletion> complete(String prefix, {int maxTokens = 24}) {
    if (_disposed) return Future<AiCompletion>.value(AiCompletion.unavailable);

    // 上一次还在跑：先打断它，再发新的。
    // 不这样会出现"旧建议后到、覆盖新建议"。
    if (_pending != null) cancel();

    final id = ++_requestId;
    final completer = Completer<AiCompletion>();
    _pending = completer;
    _cmd.send(<String, Object?>{
      'op': 'complete',
      'id': id,
      'prefix': prefix,
      'maxTokens': maxTokens,
    });
    return completer.future;
  }

  /// 打断正在进行的补全。走独立 isolate，因为生成线程没空处理消息。
  void cancel() {
    if (_disposed) return;
    _cancelCmd.send('cancel');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cmd.send(<String, Object?>{'op': 'quit'});
    _cancelCmd.send('quit');
    _events.close();
    _isolate?.kill(priority: Isolate.immediate);
    _cancelIsolate?.kill(priority: Isolate.immediate);
  }
}

void _probeMain(SendPort reply) {
  reply.send(AiNativeBindings.tryLoad() != null);
}

/// 生成 isolate：持有模型，串行处理补全请求。
///
/// 注意它**阻塞在原生调用里时收不到消息** —— 这正是取消要另开 isolate 的原因。
void _sessionMain(SendPort ready) {
  final events = ReceivePort();
  final cmd = ReceivePort();

  AiNativeBindings? bindings;
  try {
    bindings = AiNativeBindings.tryLoad();
  } on Object {
    bindings = null;
  }

  ready.send(<Object>[cmd.sendPort, events]);

  cmd.listen((Object? raw) {
    if (raw is! Map) return;
    switch (raw['op'] as String?) {
      case 'quit':
        cmd.close();
        events.close();
        Isolate.exit();

      case 'load':
        final reply = raw['reply'] as SendPort?;
        if (bindings == null) {
          reply?.send('端侧原生库未加载（libyan_ai 缺失）');
          return;
        }
        reply?.send(bindings.load((raw['path'] as String?) ?? ''));

      case 'loaded':
        (raw['reply'] as SendPort?)?.send(bindings?.isLoaded ?? false);

      case 'complete':
        final id = (raw['id'] as int?) ?? 0;
        if (bindings == null || !bindings.isLoaded) {
          events.sendPort.send(<String, Object?>{
            'kind': 'done',
            'id': id,
            'text': '',
            'reason': -1,
            'ok': false,
            'message': '模型未加载',
          });
          return;
        }
        final r = bindings.completeSync(
          (raw['prefix'] as String?) ?? '',
          (raw['maxTokens'] as int?) ?? 24,
        );
        events.sendPort.send(<String, Object?>{
          'kind': 'done',
          'id': id,
          'text': r.text,
          'reason': r.reason.index,
          'ok': r.ok,
          'message': r.message,
        });
    }
  });
}

/// 取消 isolate：只干一件事 —— 在别人忙着推理时把取消标志置上。
void _cancelMain(SendPort ready) {
  final cmd = ReceivePort();
  AiNativeBindings? bindings;
  try {
    bindings = AiNativeBindings.tryLoad();
  } on Object {
    bindings = null;
  }
  ready.send(cmd.sendPort);

  cmd.listen((Object? raw) {
    if (raw == 'quit') {
      cmd.close();
      Isolate.exit();
    }
    if (raw == 'cancel') bindings?.cancel();
  });
}
