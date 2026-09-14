/// 端侧补全用模型的元信息。
///
/// 模型不打进安装包：Qwen3-0.6B Q4_K_M 约 378 MB，塞进 HAP 会让安装包体积失控。
/// 改为首次启用时下载，所以这里要带上足够校验的信息。
class AiModelSpec {
  const AiModelSpec({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.mirrorUrls,
    required this.sizeBytes,
    required this.sha256,
  });

  final String id;
  final String displayName;

  /// 落盘后的文件名，同时用在 `.part` 临时文件命名上。
  final String fileName;

  final String downloadUrl;

  /// 备用源。主源不可达时按顺序尝试 —— 国内网络访问 HuggingFace 经常不通。
  final List<String> mirrorUrls;

  final int sizeBytes;

  /// 小写十六进制 SHA-256。下载完整性靠它确认，不能省：
  /// 模型文件损坏的表现是加载失败或输出乱码，很难与其它问题区分。
  final String sha256;

  /// 按顺序尝试的所有下载地址。
  List<String> get allUrls => <String>[downloadUrl, ...mirrorUrls];

  /// 体积的易读表示，用于界面显示。
  String get sizeLabel => '${(sizeBytes / 1024 / 1024).round()} MB';
}

/// 默认模型：Qwen3-0.6B Q4_K_M（Unsloth 量化版）。
///
/// 选它的理由见 docs/decisions.md D12：0.6B 是能在这类设备上跑到
/// 十几 token/s 的量级，再大延迟就不可接受了。
const AiModelSpec kQwen3Model = AiModelSpec(
  id: 'qwen3-0.6b-q4km',
  displayName: 'Qwen3-0.6B（Q4_K_M）',
  fileName: 'qwen3-0.6b-q4km.gguf',
  downloadUrl:
      'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
  mirrorUrls: <String>[
    'https://hf-mirror.com/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
  ],
  sizeBytes: 396705472,
  // 由本地那份已验证可用的 gguf 算出（探针与桥接层的实测都用它）。
  sha256: 'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a',
);
