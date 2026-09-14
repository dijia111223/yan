import 'package:flutter/material.dart';

import '../core/ai_model_download.dart';
import '../core/ai_model_spec.dart';
import '../state/ai_controller.dart';

/// 端侧补全的设置入口。
///
/// 设计上的三个取舍：
/// * **默认关闭**。这是可选能力，而且首次启用要下载 378 MB、常驻约 485 MB 内存。
/// * **下载必须用户明确点**，不在启动时偷偷跑 —— 移动网络下几百 MB 是大事。
/// * 关掉开关**不删模型**。删了下次开还得重下；要释放空间另有"删除模型"。
class AiSettingsPanel extends StatefulWidget {
  const AiSettingsPanel({super.key, required this.controller});

  final AiController controller;

  static Future<void> show(BuildContext context, AiController controller) {
    return showDialog<void>(
      context: context,
      builder: (context) => AiSettingsPanel(controller: controller),
    );
  }

  @override
  State<AiSettingsPanel> createState() => _AiSettingsPanelState();
}

class _AiSettingsPanelState extends State<AiSettingsPanel> {
  bool? _nativeOk;

  @override
  void initState() {
    super.initState();
    widget.controller.nativeAvailable.then((ok) {
      if (mounted) setState(() => _nativeOk = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ai = widget.controller;
        final spec = kQwen3Model;

        return AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 19),
              SizedBox(width: 8),
              Text('端侧智能补全'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_nativeOk == false) ...<Widget>[
                    _Note(
                      icon: Icons.info_outline,
                      color: scheme.error,
                      text: '当前平台没有可用的推理库，此功能不可用。'
                          '（桌面端需要先构建 yan_ai 原生库；鸿蒙端需要随应用打包 libyan_ai.so）',
                    ),
                    const SizedBox(height: 12),
                  ],

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: ai.enabled,
                    onChanged: _nativeOk == false
                        ? null
                        : (v) => ai.setEnabled(v),
                    title: const Text('启用补全建议'),
                    subtitle: const Text('停止输入后，在编辑器下方给出续写建议'),
                  ),

                  const Divider(height: 22),

                  Text('模型', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${spec.displayName}　${spec.sizeLabel}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (ai.modelReady)
                        Icon(Icons.check_circle, size: 15, color: scheme.primary),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // 进度条：下载中才出现
                  if (ai.download.phase == AiDownloadPhase.downloading) ...<Widget>[
                    LinearProgressIndicator(value: ai.download.progress),
                    const SizedBox(height: 6),
                  ],

                  Text(
                    describeDownload(ai.download),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ai.download.phase == AiDownloadPhase.failed
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),

                  if (ai.error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    _Note(
                      icon: Icons.error_outline,
                      color: scheme.error,
                      text: ai.error!,
                    ),
                  ],

                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (!ai.modelReady)
                        FilledButton.icon(
                          onPressed: ai.busy || _nativeOk == false
                              ? null
                              : ai.downloadModel,
                          icon: const Icon(Icons.download, size: 16),
                          label: Text(
                            ai.download.phase == AiDownloadPhase.downloading
                                ? '下载中…'
                                : '下载模型',
                          ),
                        ),
                      if (ai.modelReady)
                        OutlinedButton.icon(
                          onPressed: ai.busy ? null : ai.downloadModel,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重新校验'),
                        ),
                      if (ai.modelReady || ai.download.phase != AiDownloadPhase.idle)
                        TextButton.icon(
                          onPressed: ai.busy ? null : ai.deleteModel,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('删除模型'),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  _Note(
                    icon: Icons.shield_outlined,
                    color: scheme.onSurfaceVariant,
                    text: '模型只在首次下载时联网，之后推理完全在设备本地进行。'
                        '笔记内容不会上传，本应用也没有任何遥测。'
                        '推理时内存占用约 485 MB，低端设备上可能较慢。',
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 6),
          child: Icon(icon, size: 13, color: color),
        ),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color, height: 1.45),
          ),
        ),
      ],
    );
  }
}
