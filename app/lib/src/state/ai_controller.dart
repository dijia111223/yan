import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ai_model_download.dart';
import '../core/ai_model_spec.dart';
import '../core/ai_native.dart';
import '../core/platform_file_picker.dart';

/// 端侧补全的开关与状态。
///
/// 分成三件独立的事，不要混在一起：
/// * **开关**（用户是否想要这个功能）
/// * **模型**（文件在不在、要不要下载）
/// * **会话**（原生模型有没有加载进内存）
///
/// 混在一起会出问题：用户关掉开关不该删模型（下次开还得重下 378 MB）；
/// 模型在但会话加载失败也该能重试，而不是显示成"未下载"。
class AiController extends ChangeNotifier {
  AiController({Future<bool>? nativeAvailable})
      : _nativeAvailable = nativeAvailable;

  static const String _kEnabled = 'ai.enabled';

  /// 送给模型的前缀上限。
  ///
  /// 为什么限制：原生的上下文窗口是 512 token，而 prefill 是线性成本
  /// （实测约 38 tok/s）。截断的收益是延迟可预测 —— 长文档里若把整篇塞进去，
  /// 光是读提示就要好几秒。**且前缀必须取尾部**：补全只关心光标附近。
  static const int maxPrefixChars = 600;

  /// 生成上限，与原生默认值一致。
  static const int maxTokens = 24;

  bool _enabled = false;
  bool _busy = false;
  bool _disposed = false;
  String _modelPath = '';
  String? _error;
  AiDownloadState _download = const AiDownloadState(phase: AiDownloadPhase.idle);
  AiNativeSession? _session;
  Completer<void>? _loading;
  Future<bool>? _nativeAvailable;

  bool get enabled => _enabled;

  /// 是否正在下载或加载（界面据此禁用按钮）。
  bool get busy => _busy;

  String get modelPath => _modelPath;
  AiDownloadState get download => _download;
  String? get error => _error;

  /// 模型文件是否已就位。
  bool get modelReady => _downloader?.isInstalled ?? false;

  /// 原生库是否存在。不存在时界面要说明"此平台不支持"，而不是让用户白下载。
  ///
  /// 可通过构造参数注入：真实实现要 spawn 一个 isolate 去试探动态库，
  /// 而界面不该依赖这个时序才能渲染出正确提示（测试里也就能确定性地验证）。
  Future<bool> get nativeAvailable =>
      _nativeAvailable ??= AiNativeSession.nativeAvailable();

  /// 功能是否已可用（开关开着 + 模型在 + 会话已加载）。
  bool get ready => _enabled && _session != null && modelReady;

  AiModelDownloader? get _downloader => _modelPath.isEmpty
      ? null
      : AiModelDownloader(modelPath: _modelPath, spec: kQwen3Model);

  /// 读出持久化的开关，并把模型路径定下来。
  ///
  /// 不自动开始下载：378 MB 的流量必须由用户明确同意，不能在启动时就悄悄跑。
  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
    } on Exception {
      // 读不到偏好就用默认值，不该因此让功能不可用
    }

    await _resolveModelPath();
    _refreshDownloadState();

    // 开关本来就是开的（上次留下的），这时才值得把模型读进内存
    if (_enabled && modelReady) unawaited(_ensureSession());
    _notify();
  }

  /// 模型放哪儿：鸿蒙在沙箱的独立子目录，桌面放在用户目录下的隐藏文件夹。
  Future<void> _resolveModelPath() async {
    if (kIsWeb) return;
    try {
      if (Platform.operatingSystem == 'ohos') {
        final dir = await ensureOhosModelDir();
        if (dir != null && dir.isNotEmpty) {
          _modelPath = '$dir/${kQwen3Model.fileName}';
          return;
        }
      }
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      final dir = Directory('$home${Platform.pathSeparator}.yan${Platform.pathSeparator}models');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _modelPath = '${dir.path}${Platform.pathSeparator}${kQwen3Model.fileName}';
    } on Object catch (e) {
      _error = '无法确定模型存放位置：$e';
    }
  }

  void _refreshDownloadState() {
    final d = _downloader;
    if (d == null) return;
    if (d.isInstalled) {
      _download = AiDownloadState(
        phase: AiDownloadPhase.ready,
        received: kQwen3Model.sizeBytes,
        total: kQwen3Model.sizeBytes,
      );
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    _error = null;
    _notify();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } on Exception {
      // 存不上只是下次启动记不住，不影响本次使用
    }

    if (value) {
      if (modelReady) {
        unawaited(_ensureSession());
      }
      // 模型没下也什么都不做：等用户点"下载模型"
    } else {
      // 关掉就把内存还回去 —— 485 MB 常驻对中低端机太重
      _session?.dispose();
      _session = null;
      _notify();
    }
  }

  /// 下载模型（可重复调用，已在下载中则忽略）。
  Future<void> downloadModel() async {
    final d = _downloader;
    if (d == null || _busy) return;

    _busy = true;
    _error = null;
    _notify();

    try {
      final result = await AiModelDownloader(
        modelPath: d.modelFile.path,
        spec: kQwen3Model,
        onState: (s) {
          _download = s;
          _notify();
        },
      ).download();

      _download = result;
      if (result.phase == AiDownloadPhase.failed) {
        _error = result.message;
      } else if (_enabled) {
        unawaited(_ensureSession());
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 删掉模型文件，把空间还回去。
  Future<void> deleteModel() async {
    _session?.dispose();
    _session = null;
    _busy = true;
    _notify();
    try {
      final d = _downloader;
      if (d != null) {
        if (d.modelFile.existsSync()) d.modelFile.deleteSync();
        if (d.partFile.existsSync()) d.partFile.deleteSync();
      }
      _download = const AiDownloadState(phase: AiDownloadPhase.idle);
      _error = null;
    } on Object catch (e) {
      _error = '删除失败：$e';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 确保原生会话已加载模型。并发调用会共用同一次加载。
  Future<void> _ensureSession() async {
    if (_session != null) return;
    final inflight = _loading;
    if (inflight != null) return inflight.future;

    final completer = Completer<void>();
    _loading = completer;
    _busy = true;
    _notify();

    try {
      final session = await AiNativeSession.spawn();
      if (session == null) {
        _error = '端侧推理库未加载，此平台暂不支持';
        return;
      }
      final err = await session.load(_modelPath);
      if (err.isNotEmpty) {
        _error = '模型加载失败：$err';
        session.dispose();
        return;
      }
      _session = session;
      _error = null;
    } on Object catch (e) {
      _error = '模型加载异常：$e';
    } finally {
      _loading = null;
      _busy = false;
      _notify();
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// 请求一次补全。[text] 是编辑器全文，[cursor] 是光标位置。
  ///
  /// 返回空字符串表示没有建议（模型未就绪、输入为空、或建议没通过校验）。
  Future<String> requestCompletion(String text, int cursor) async {
    final session = _session;
    if (session == null || !_enabled) return '';

    final prefix = completionPrefix(text, cursor);
    if (prefix.isEmpty) return '';

    try {
      final r = await session.complete(prefix, maxTokens: maxTokens);
      if (!r.ok || r.text.isEmpty) return '';
      // 校验放在这里而不是原生侧：它是"这份建议能不能直接用"的产品判断，
      // 与推理无关，而且放这儿能单测。
      if (!suggestionLooksValid(r.text, prefix)) return '';
      return r.text;
    } on Object {
      return '';
    }
  }

  /// 打断在途补全（用户继续打字时调用）。
  void cancelCompletion() => _session?.cancel();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session?.dispose();
    _session = null;
    super.dispose();
  }
}

/// 取出送模型的前缀：**光标之前**、末尾 [AiController.maxPrefixChars] 个字符。
///
/// 抽成纯函数是为了能单测边界（光标在文首、光标在文末、超长文本），
/// 而不用真的加载模型。
String completionPrefix(String text, int cursor, {int limit = AiController.maxPrefixChars}) {
  if (text.isEmpty) return '';
  var end = cursor;
  if (end < 0) end = 0;
  if (end > text.length) end = text.length;
  if (end == 0) return '';
  final start = end - limit > 0 ? end - limit : 0;
  return text.substring(start, end);
}

/// 这份建议能不能直接写进文档。
///
/// 存在的理由：0.6B 写 Markdown 表格行时**经常不输出行尾的 `|`**，
/// 补出来就是 ` Linux | 已发布` 这种残缺行。提示工程没能稳定修好它
/// （试过以 `|` 作停止串，反而在第一个竖线就截断、真实内容全丢），
/// 所以宁可不给建议，也不要给一个会把表格改坏的建议。
///
/// "不给"比"给错的"好：补全只是辅助，用户自己敲那半行没有任何损失；
/// 而接受一个坏建议会把文档结构弄乱，还得手动修。
bool suggestionLooksValid(String suggestion, String prefix) {
  final s = suggestion.trimRight();
  if (s.isEmpty) return false;

  // 光标所在行是表格行 → 建议必须补成完整的表格行
  final lastNl = prefix.lastIndexOf('\n');
  final curLine = lastNl < 0 ? prefix : prefix.substring(lastNl + 1);
  if (curLine.startsWith('|')) {
    // 完整表格行以 `|` 收尾；建议里若含换行，则每个非空行都要收尾
    final lines = s.split('\n');
    for (final line in lines) {
      final t = line.trimRight();
      if (t.isEmpty) continue;
      if (!t.endsWith('|')) return false;
    }
  }
  return true;
}
