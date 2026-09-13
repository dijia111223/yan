import 'package:flutter/material.dart';

import '../core/frontmatter.dart';
import '../core/typography.dart';
import '../state/workspace.dart';

/// frontmatter 读写面板：规范字段表单化编辑，另留原始 YAML 入口。
/// 原样重建保证未识别字段与 YAML 注释不会因可视化编辑而丢失。
class FrontmatterPanel extends StatefulWidget {
  const FrontmatterPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<FrontmatterPanel> createState() => _FrontmatterPanelState();
}

class _FrontmatterPanelState extends State<FrontmatterPanel> {
  bool _showRaw = false;
  final TextEditingController _raw = TextEditingController();

  WorkspaceState get state => widget.state;

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = state.activeDocument;
    if (doc == null) return const SizedBox.shrink();

    final fm = FrontmatterCodec.parse(doc.content);

    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
            child: Row(
              children: <Widget>[
                Icon(Icons.sell_outlined, size: 15, color: scheme.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Frontmatter',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (fm.hasFrontmatter)
                  IconButton(
                    tooltip: _showRaw ? '切换为表单视图' : '编辑原始 YAML',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_showRaw ? Icons.list_alt_rounded : Icons.code_rounded, size: 17),
                    onPressed: () {
                      if (!_showRaw) _raw.text = fm.raw;
                      setState(() => _showRaw = !_showRaw);
                    },
                  ),
                IconButton(
                  tooltip: '关闭面板',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: state.toggleFrontmatterPanel,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: !fm.hasFrontmatter
                ? _MissingView(onInsert: state.ensureFrontmatter)
                : (_showRaw
                    ? _RawEditorView(controller: _raw, onWrite: (value) => _writeRaw(value, fm))
                    : _FieldFormView(state: state, fm: fm)),
          ),
        ],
      ),
    );
  }

  Future<void> _writeRaw(String raw, Frontmatter fm) async {
    final doc = state.activeDocument;
    if (doc == null) return;
    final next = fm.reconstruct(raw, fm.body);
    if (next == doc.content) return;
    doc.controller.text = next;
    await state.saveActive();
  }
}

class _MissingView extends StatelessWidget {
  const _MissingView({required this.onInsert});

  final Future<void> Function() onInsert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('这篇笔记还没有 frontmatter', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              '按统一语料层规范补齐 title / created / updated / tags / source，'
              '并预留 lineage 血缘字段——这是"体用组合"的焊接点。',
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onInsert,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('插入模板'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RawEditorView extends StatelessWidget {
  const _RawEditorView({required this.controller, required this.onWrite});

  final TextEditingController controller;
  final Future<void> Function(String) onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: AppFonts.monoStyle(theme.textTheme.bodySmall).copyWith(height: 1.55),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('原样保存：注释与未识别字段都会保留', style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          FilledButton(onPressed: () => onWrite(controller.text), child: const Text('写入文件')),
        ],
      ),
    );
  }
}

class _FieldFormView extends StatelessWidget {
  const _FieldFormView({required this.state, required this.fm});

  final WorkspaceState state;
  final Frontmatter fm;

  static const List<String> structured = <String>[
    'title',
    'created',
    'updated',
    'source',
    'tags',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extras = fm.fields.keys.where((k) => !structured.contains(k)).toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        _ScalarField(
          key: ValueKey<String>('title:${fm.string('title') ?? ''}'),
          label: '标题',
          hint: '笔记标题',
          initialValue: fm.string('title') ?? '',
          onSubmit: (value) => state.updateFrontmatter(<String, Object?>{'title': value}),
        ),
        _ScalarField(
          key: ValueKey<String>('created:${fm.string('created') ?? ''}'),
          label: '创建日期',
          hint: 'YYYY-MM-DD',
          initialValue: fm.string('created') ?? '',
          onSubmit: (value) => state.updateFrontmatter(<String, Object?>{'created': value}),
        ),
        _ScalarField(
          key: ValueKey<String>('updated:${fm.string('updated') ?? ''}'),
          label: '更新日期',
          hint: 'YYYY-MM-DD',
          initialValue: fm.string('updated') ?? '',
          onSubmit: (value) => state.updateFrontmatter(<String, Object?>{'updated': value}),
        ),
        _ScalarField(
          key: ValueKey<String>('source:${fm.string('source') ?? ''}'),
          label: '来源',
          hint: '书籍 / 课程 / 网页…',
          initialValue: fm.string('source') ?? '',
          onSubmit: (value) => state.updateFrontmatter(<String, Object?>{'source': value}),
        ),
        const SizedBox(height: 2),
        _TagsField(
          key: ValueKey<String>('tags:${fm.stringList('tags').join('|')}'),
          tags: fm.stringList('tags'),
          onChange: (tags) => state.updateFrontmatter(<String, Object?>{'tags': tags}),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: state.touchUpdatedField,
          icon: const Icon(Icons.today_rounded, size: 15),
          label: const Text('把 updated 设为今天'),
        ),
        if (extras.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text('其它字段（原样保留）', style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          for (final key in extras)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 68,
                    child: Text(
                      key,
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      fm.fields[key]?.toString() ?? '',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ScalarField extends StatefulWidget {
  const _ScalarField({
    super.key,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onSubmit,
  });

  final String label;
  final String hint;
  final String initialValue;
  final Future<void> Function(String) onSubmit;

  @override
  State<_ScalarField> createState() => _ScalarFieldState();
}

class _ScalarFieldState extends State<_ScalarField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value == widget.initialValue.trim()) return;
    widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onSubmitted: (_) => _commit(),
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        ),
      ),
    );
  }
}

class _TagsField extends StatefulWidget {
  const _TagsField({super.key, required this.tags, required this.onChange});

  final List<String> tags;
  final Future<void> Function(List<String>) onChange;

  @override
  State<_TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<_TagsField> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final value = raw.trim();
    _input.clear();
    if (value.isEmpty || widget.tags.contains(value)) return;
    widget.onChange(<String>[...widget.tags, value]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('标签', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final tag in widget.tags)
                InputChip(
                  label: Text(tag, style: theme.textTheme.labelSmall),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onDeleted: () => widget.onChange(
                    widget.tags.where((t) => t != tag).toList(growable: false),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 6),
        TextField(
          controller: _input,
          style: theme.textTheme.bodySmall,
          onSubmitted: _add,
          decoration: InputDecoration(
            hintText: '输入标签后回车',
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => _add(_input.text),
            ),
          ),
        ),
      ],
    );
  }
}
