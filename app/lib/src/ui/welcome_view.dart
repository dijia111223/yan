import 'package:flutter/material.dart';

import '../state/workspace.dart';
import '../state/workspace_scope.dart';
import 'platform_file_picker.dart';
import 'window_title.dart';
/// 没有库时显示的欢迎页。
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = WorkspaceScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '砚',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('砚 Yan', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                '纯文件、本地优先的 Markdown 编辑器',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 26),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('一个文件夹就是一个库', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 10),
                      for (final line in const <String>[
                        '· 笔记就是磁盘上的 .md 文件，没有私有数据库、不锁定格式',
                        '· 文件树、语法高亮、GFM 预览（表格 / 代码块 / 公式）',
                        '· frontmatter 读写，与统一语料层规范一致',
                        '· 全文搜索：文件名 + 内容',
                        '· v1 同步方案：把库放进 Git 仓库即可',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(line, style: theme.textTheme.bodySmall),
                        ),
                      const SizedBox(height: 16),
                      // 触屏平台没有 Ctrl，且按钮本身已经够宽，提示只会挤掉它；只在桌面显示
                      if (WindowTitle.supported) ...<Widget>[
                        Row(
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: () => _pickAndOpen(context, state),
                              icon: const Icon(Icons.folder_open_rounded, size: 17),
                              label: const Text('打开文件夹作为库'),
                            ),
                            const SizedBox(width: 10),
                            Text('或按 Ctrl+O', style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ] else
                        FilledButton.icon(
                          onPressed: () => _pickAndOpen(context, state),
                          icon: const Icon(Icons.folder_open_rounded, size: 17),
                          label: const Text('打开文件夹作为库'),
                        ),
                    ],
                  ),
                ),
              ),
              if (state.recentLibraries.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('最近的库', style: theme.textTheme.labelMedium),
                ),
                const SizedBox(height: 8),
                for (final path in state.recentLibraries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history_rounded, size: 18, color: scheme.primary),
                    title: Text(path, style: theme.textTheme.bodySmall),
                    onTap: () => state.openFolder(path),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _pickAndOpen(BuildContext context, WorkspaceState state) async {
    try {
      final path = await pickDirectoryPath();
      if (path == null) return;
      await state.openFolder(path);
    } on DirectoryPickException catch (e) {
      state.showToast(e.message);
    }
  }
}
