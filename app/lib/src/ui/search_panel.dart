import 'dart:async';

import 'package:flutter/material.dart';

import '../core/search.dart';
import '../state/workspace.dart';

/// 全文搜索面板：文件名 + 内容。
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.state,
    required this.onClose,
  });

  final WorkspaceState state;
  final VoidCallback onClose;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      widget.state.runSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _query,
                    focusNode: _focus,
                    onChanged: _onChanged,
                    onSubmitted: state.runSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: '搜索文件名与内容…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空',
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _query.clear();
                                state.runSearch('');
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<SearchScope>(
                  value: state.searchScope,
                  underline: const SizedBox.shrink(),
                  style: theme.textTheme.bodySmall,
                  onChanged: (value) {
                    if (value == null) return;
                    state.setSearchScope(value);
                    if (_query.text.trim().isNotEmpty) state.runSearch(_query.text);
                  },
                  items: <DropdownMenuItem<SearchScope>>[
                    for (final scope in SearchScope.values)
                      DropdownMenuItem<SearchScope>(value: scope, child: Text(scope.label)),
                  ],
                ),
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          _ScopeOptions(state: state, onChanged: () {
            if (_query.text.trim().isNotEmpty) state.runSearch(_query.text);
          }),
          const SizedBox(height: 4),
          Divider(height: 1, color: scheme.outlineVariant),
          SizedBox(
            height: 240,
            child: _Results(
              state: state,
              onOpen: (hit) async {
                await state.openHit(hit);
                widget.onClose();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeOptions extends StatelessWidget {
  const _ScopeOptions({required this.state, required this.onChanged});

  final WorkspaceState state;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: state.searchFrontmatter,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (value) {
              state.setSearchFrontmatter(value ?? false);
              onChanged();
            },
          ),
          Text('包含 frontmatter', style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(
            state.searching
                ? '搜索中…'
                : (state.searchQuery.trim().isEmpty ? '' : '${state.searchHits.length} 条命中'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state, required this.onOpen});

  final WorkspaceState state;
  final Future<void> Function(SearchHit) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hits = state.searchHits;

    if (state.searching && hits.isEmpty) {
      return const Center(
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (state.searchQuery.trim().isEmpty) {
      return Center(
        child: Text('输入关键词开始搜索', style: theme.textTheme.bodySmall),
      );
    }
    if (hits.isEmpty) {
      return Center(
        child: Text('没有匹配「${state.searchQuery}」的结果', style: theme.textTheme.bodySmall),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return InkWell(
          onTap: () => onOpen(hit),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      hit.isFileNameMatch ? Icons.description_outlined : Icons.notes_rounded,
                      size: 14,
                      color: hit.isFileNameMatch ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _highlighted(
                        hit.snippet ?? hit.name,
                        hit.matchStart,
                        hit.matchEnd,
                        theme.textTheme.bodyMedium!.copyWith(
                          fontWeight: hit.isFileNameMatch ? FontWeight.w600 : FontWeight.w400,
                        ),
                        scheme.primary.withValues(alpha: 0.28),
                      ),
                    ),
                    if (hit.location.isNotEmpty)
                      Text(hit.location, style: theme.textTheme.labelSmall),
                  ],
                ),
                if (hit.isFileNameMatch)
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 1),
                    child: Text(
                      hit.relativePath,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 1),
                    child: Text(
                      hit.relativePath,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _highlighted(
    String text,
    int? start,
    int? end,
    TextStyle style,
    Color background,
  ) {
    if (start == null || end == null || start >= end || end > text.length) {
      return Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: <TextSpan>[
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: style.copyWith(
              backgroundColor: background,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
