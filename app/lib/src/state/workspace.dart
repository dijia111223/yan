import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/frontmatter.dart';
import '../core/launch_options.dart';
import '../core/library.dart';
import '../core/markdown_theme.dart';
import '../core/math_text.dart';
import '../core/models.dart';
import '../core/search.dart';
import 'editor_controller.dart';

class OpenDocument {
  OpenDocument({
    required this.path,
    required this.controller,
    required this.savedContent,
  })  : name = p.basename(path),
        lastObservedText = savedContent;

  final String path;
  String name;
  final MarkdownEditingController controller;

  /// 与磁盘一致的内容，用来判断未保存。
  String savedContent;

  /// 只有它变了才算正文改动：主题切换、选区变化也会触发 controller 通知。
  String lastObservedText;

  /// 光标行列，1 基。
  int cursorLine = 1;
  int cursorColumn = 1;

  bool get isDirty => controller.text != savedContent;

  String get content => controller.text;

  TextStats get stats => TextStats.of(controller.text);

  void dispose() => controller.dispose();
}

/// 应用状态：库、标签页、偏好。
class WorkspaceState extends ChangeNotifier {
  WorkspaceState();

  static const String _kLibrary = 'yan.libraryPath';
  static const String _kRecentLibraries = 'yan.recentLibraries';
  static const String _kOpenTabs = 'yan.openTabs';
  static const String _kActiveTab = 'yan.activeTab';
  static const String _kShowSidebar = 'yan.showSidebar';
  static const String _kShowPreview = 'yan.showPreview';
  static const String _kShowFrontmatter = 'yan.showFrontmatter';
  static const String _kDarkMode = 'yan.darkMode';
  static const String _kAutosave = 'yan.autosave';
  static const String _kSort = 'yan.sort';
  static const int _maxRecentLibraries = 8;

  static const Duration autosaveDelay = Duration(milliseconds: 900);

  SharedPreferences? _prefs;

  Library? _library;
  Library? get library => _library;
  String? get libraryPath => _library?.rootPath;
  bool get hasLibrary => _library != null;

  MarkdownTheme markdownTheme = MarkdownTheme.light;

  List<String> _recentLibraries = <String>[];
  List<String> get recentLibraries => List<String>.unmodifiable(_recentLibraries);

  LibrarySort _sort = LibrarySort.nameAsc;
  LibrarySort get sort => _sort;

  int _treeRevision = 0;
  int get treeRevision => _treeRevision;

  String? _revealPath;
  String? get revealPath => _revealPath;

  final List<OpenDocument> _documents = <OpenDocument>[];
  List<OpenDocument> get documents => List<OpenDocument>.unmodifiable(_documents);

  int _activeIndex = -1;
  int get activeIndex => _activeIndex;

  OpenDocument? get activeDocument =>
      _activeIndex >= 0 && _activeIndex < _documents.length ? _documents[_activeIndex] : null;

  bool _showSidebar = true;
  bool _showPreview = true;
  bool _showFrontmatter = false;
  bool _darkMode = false;
  bool _autosave = true;
  bool _previewLive = true;

  bool get showSidebar => _showSidebar;
  bool get showPreview => _showPreview;
  bool get showFrontmatter => _showFrontmatter;
  bool get darkMode => _darkMode;
  bool get autosave => _autosave;
  bool get previewLive => _previewLive;

  SearchScope _searchScope = SearchScope.both;
  bool _searchFrontmatter = true;
  List<SearchHit> _searchHits = const <SearchHit>[];
  bool _searching = false;
  String _searchQuery = '';

  SearchScope get searchScope => _searchScope;
  bool get searchFrontmatter => _searchFrontmatter;
  List<SearchHit> get searchHits => _searchHits;
  bool get searching => _searching;
  String get searchQuery => _searchQuery;

  String? _toast;
  String? get toast => _toast;

  Timer? _autosaveTimer;
  Timer? _toastTimer;
  int _openToken = 0;

  final Map<String, ({int hash, MathExtraction extraction})> _mathCache =
      <String, ({int hash, MathExtraction extraction})>{};

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _autosaveTimer?.cancel();
    _toastTimer?.cancel();
    for (final doc in _documents) {
      doc.dispose();
    }
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ================================================================ 生命周期

  Future<void> bootstrap({LaunchOptions launch = const LaunchOptions()}) async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } on Exception {
      _prefs = null;
    }
    final prefs = _prefs;
    if (prefs != null) {
      _recentLibraries = prefs.getStringList(_kRecentLibraries) ?? <String>[];
      _showSidebar = prefs.getBool(_kShowSidebar) ?? true;
      _showPreview = prefs.getBool(_kShowPreview) ?? true;
      _showFrontmatter = prefs.getBool(_kShowFrontmatter) ?? false;
      _darkMode = prefs.getBool(_kDarkMode) ?? false;
      _autosave = prefs.getBool(_kAutosave) ?? true;
      final sortName = prefs.getString(_kSort);
      _sort = LibrarySort.values.firstWhere(
        (s) => s.name == sortName,
        orElse: () => LibrarySort.nameAsc,
      );

      // 命令行 > 上次会话
      final lastLibrary = launch.libraryPath ?? prefs.getString(_kLibrary);
      if (lastLibrary != null && Directory(lastLibrary).existsSync()) {
        await openFolder(lastLibrary, remember: launch.libraryPath == null);

        final toOpen = launch.openFiles.isNotEmpty
            ? launch.openFiles
            : (prefs.getStringList(_kOpenTabs) ?? <String>[]);
        // 只给了笔记没给库时，拿笔记所在目录当库
        if (!hasLibrary && toOpen.isNotEmpty) {
          final dir = p.dirname(toOpen.first);
          if (Directory(dir).existsSync()) {
            await openFolder(dir);
          }
        }
        for (final tab in toOpen) {
          if (File(tab).existsSync()) {
            await openFile(tab, activate: false);
          }
        }

        final activeTab = launch.openFiles.isNotEmpty
            ? launch.openFiles.last
            : prefs.getString(_kActiveTab);
        if (activeTab != null) {
          final index = _documents.indexWhere((d) => d.path == activeTab);
          if (index >= 0) _activeIndex = index;
        }
        if (_documents.isNotEmpty && _activeIndex < 0) _activeIndex = 0;
      }
    } else if (launch.openFiles.isNotEmpty) {
      // 偏好存储不可用时也要满足命令行请求
      final dir = p.dirname(launch.openFiles.first);
      if (Directory(dir).existsSync()) {
        await openFolder(dir);
        for (final tab in launch.openFiles) {
          if (File(tab).existsSync()) await openFile(tab);
        }
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setStringList(_kRecentLibraries, _recentLibraries);
    await prefs.setStringList(_kOpenTabs, _documents.map((d) => d.path).toList());
    await prefs.setString(_kActiveTab, activeDocument?.path ?? '');
    await prefs.setBool(_kShowSidebar, _showSidebar);
    await prefs.setBool(_kShowPreview, _showPreview);
    await prefs.setBool(_kShowFrontmatter, _showFrontmatter);
    await prefs.setBool(_kDarkMode, _darkMode);
    await prefs.setBool(_kAutosave, _autosave);
    await prefs.setString(_kSort, _sort.name);
  }

  // ================================================================ 库操作

  Future<bool> openFolder(String path, {bool remember = true}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      showToast('文件夹不存在：$path');
      return false;
    }

    // 切换库之前先落盘，避免丢内容
    await saveAll();

    _library = Library(path);
    _treeRevision++;
    _revealPath = null;
    _searchHits = const <SearchHit>[];
    _searchQuery = '';
    _mathCache.clear();

    for (final doc in _documents) {
      doc.dispose();
    }
    _documents.clear();
    _activeIndex = -1;

    if (remember) {
      _recentLibraries = <String>[
        path,
        ..._recentLibraries.where((item) => item != path),
      ].take(_maxRecentLibraries).toList(growable: false);
      final prefs = _prefs;
      await prefs?.setString(_kLibrary, path);
    }

    notifyListeners();
    await _persist();
    return true;
  }

  Future<void> closeLibrary() async {
    await saveAll();
    _library = null;
    for (final doc in _documents) {
      doc.dispose();
    }
    _documents.clear();
    _activeIndex = -1;
    _treeRevision++;
    notifyListeners();
    await _persist();
  }

  void setSort(LibrarySort value) {
    if (_sort == value) return;
    _sort = value;
    _treeRevision++;
    notifyListeners();
    unawaited(_persist());
  }

  void requestReveal(String? path) {
    _revealPath = path;
    notifyListeners();
  }

  void clearReveal() {
    _revealPath = null;
  }

  void refreshTree() {
    _treeRevision++;
    notifyListeners();
  }

  // ================================================================ 文档操作

  Future<OpenDocument?> openFile(String path, {bool activate = true}) async {
    final existing = _documents.where((d) => d.path == path).toList();
    if (existing.isNotEmpty) {
      if (activate) {
        _activeIndex = _documents.indexOf(existing.first);
        notifyListeners();
      }
      return existing.first;
    }

    final file = File(path);
    if (!await file.exists()) {
      showToast('文件不存在：${p.basename(path)}');
      return null;
    }

    String content;
    try {
      content = await _readFile(file);
    } on FileSystemException catch (e) {
      showToast('读取失败：${e.message}');
      return null;
    }

    final doc = OpenDocument(
      path: path,
      controller: MarkdownEditingController(text: content, theme: markdownTheme),
      savedContent: content,
    );
    doc.controller.addListener(_onDocumentChanged);
    doc.controller.selectionNotifier.addListener(_onSelectionChanged);

    _documents.add(doc);
    if (activate) _activeIndex = _documents.length - 1;
    notifyListeners();
    await _persist();
    return doc;
  }

  static Future<String> _readFile(File file) async {
    final bytes = await file.readAsBytes();
    // 去掉 UTF-8 BOM，否则首行显示乱码
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<OpenDocument?> createNote({String? parentPath}) async {
    final library = _library;
    if (library == null) return null;
    try {
      final path = await library.createNote(parentPath: parentPath);
      final doc = await openFile(path);
      requestReveal(path);
      await _applyFrontmatterTemplate(doc);
      return doc;
    } on FileSystemException catch (e) {
      showToast('新建失败：${e.message}');
      return null;
    }
  }

  /// 补空笔记的 frontmatter，title 取自文件名。
  Future<void> _applyFrontmatterTemplate(OpenDocument? doc) async {
    if (doc == null) return;
    final title = p.basenameWithoutExtension(doc.path);
    final withTemplate = FrontmatterCodec.ensureFrontmatter(doc.content, title: title);
    if (withTemplate == doc.content) return;
    doc.controller.text = withTemplate;
    notifyListeners();
    await saveDocument(doc);
  }

  Future<void> createFolder({String? parentPath}) async {
    final library = _library;
    if (library == null) return;
    try {
      final path = await library.createFolder(parentPath: parentPath);
      requestReveal(path);
      refreshTree();
    } on FileSystemException catch (e) {
      showToast('新建文件夹失败：${e.message}');
    }
  }

  void activate(int index) {
    if (index < 0 || index >= _documents.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> closeDocument(int index) async {
    if (index < 0 || index >= _documents.length) return;
    final doc = _documents[index];
    if (doc.isDirty) {
      await saveDocument(doc);
    }
    doc.controller.removeListener(_onDocumentChanged);
    doc.controller.selectionNotifier.removeListener(_onSelectionChanged);
    doc.dispose();
    _documents.removeAt(index);
    if (_documents.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= _documents.length) {
      _activeIndex = _documents.length - 1;
    } else if (index < _activeIndex) {
      _activeIndex--;
    }
    _mathCache.remove(doc.path);
    notifyListeners();
    await _persist();
  }

  Future<void> closeAllDocuments() async {
    await saveAll();
    for (final doc in _documents) {
      doc.controller.removeListener(_onDocumentChanged);
      doc.controller.selectionNotifier.removeListener(_onSelectionChanged);
      doc.dispose();
    }
    _documents.clear();
    _activeIndex = -1;
    notifyListeners();
    await _persist();
  }

  // ================================================================ 保存

  void _onDocumentChanged() {
    // 只有正文真的变了才排自动保存：主题切换、选区变化也会走到这里。
    final doc = activeDocument;
    if (doc != null && doc.controller.text != doc.lastObservedText) {
      doc.lastObservedText = doc.controller.text;
      _scheduleAutosave();
    }
    notifyListeners();
  }

  void _onSelectionChanged() {
    final doc = activeDocument;
    if (doc == null) return;
    final offset = doc.controller.selectionNotifier.value.baseOffset;
    final (line, column) = offsetToLineColumn(doc.content, offset);
    if (line != doc.cursorLine || column != doc.cursorColumn) {
      doc.cursorLine = line;
      doc.cursorColumn = column;
      notifyListeners();
    }
  }

  static (int, int) offsetToLineColumn(String text, int offset) {
    if (text.isEmpty) return (1, 1);
    final clamped = offset.clamp(0, text.length);
    var line = 1;
    var lastLineStart = 0;
    for (var i = 0; i < clamped; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lastLineStart = i + 1;
      }
    }
    return (line, clamped - lastLineStart + 1);
  }

  void _scheduleAutosave() {
    if (!_autosave) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(autosaveDelay, () {
      final doc = activeDocument;
      if (doc != null && doc.isDirty) {
        unawaited(saveDocument(doc));
      }
    });
  }

  /// 首选临时文件 + 重命名，但 Windows 上目标被占用时 rename 会失败（笔记常被
  /// 预览、同步盘、杀毒占用），这时退回直接覆写。
  Future<bool> saveDocument(OpenDocument doc) async {
    if (!doc.isDirty) return true;
    _autosaveTimer?.cancel();
    final content = doc.content;

    try {
      final target = File(doc.path);
      final directory = target.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      var wrote = false;
      final temp = File('${doc.path}.yan-tmp');
      try {
        await temp.writeAsString(content, encoding: utf8, flush: true);
        await temp.rename(doc.path);
        wrote = true;
      } on FileSystemException {
        try {
          await temp.delete();
        } on FileSystemException {
          // 清理失败不影响保存
        }
      }

      if (!wrote) {
        await target.writeAsString(content, encoding: utf8, flush: true);
      }

      doc.savedContent = content;
      doc.lastObservedText = content;
      notifyListeners();
      return true;
    } on FileSystemException catch (e) {
      showToast('保存失败：${e.message}');
      return false;
    }
  }

  Future<bool> saveActive() async {
    final doc = activeDocument;
    if (doc == null) return true;
    return saveDocument(doc);
  }

  Future<void> saveAll() async {
    _autosaveTimer?.cancel();
    for (final doc in _documents) {
      if (doc.isDirty) {
        await saveDocument(doc);
      }
    }
  }

  // ================================================================ 标签页内容

  void jumpTo(int line, {int? column}) {
    final doc = activeDocument;
    if (doc == null) return;
    doc.controller.jumpToLine(line, column: column);
  }

  void insertAtCursor(String snippet) {
    final doc = activeDocument;
    if (doc == null) return;
    final controller = doc.controller;
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    // 成对标记（粗体/斜体/代码）由调用方传入
    final next = '$before$snippet$after';
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
  }

  void appendText(String snippet) {
    final doc = activeDocument;
    if (doc == null) return;
    final text = doc.controller.text;
    final separator = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    doc.controller.text = '$text$separator$snippet';
    notifyListeners();
  }

  // ================================================================ frontmatter

  Frontmatter get activeFrontmatter {
    final doc = activeDocument;
    if (doc == null) return Frontmatter.none;
    return FrontmatterCodec.parse(doc.content);
  }

  /// 保留其它字段与注释。
  Future<void> updateFrontmatter(Map<String, Object?> updates, {Set<String> removeKeys = const <String>{}}) async {
    final doc = activeDocument;
    if (doc == null) return;
    final next = FrontmatterCodec.update(doc.content, updates: updates, removeKeys: removeKeys);
    if (next == doc.content) return;
    doc.controller.text = next;
    notifyListeners();
    await saveDocument(doc);
  }

  Future<void> ensureFrontmatter() async {
    final doc = activeDocument;
    if (doc == null) return;
    final title = p.basenameWithoutExtension(doc.path);
    final next = FrontmatterCodec.ensureFrontmatter(doc.content, title: title);
    if (next == doc.content) {
      showToast('已有 frontmatter');
      return;
    }
    doc.controller.text = next;
    notifyListeners();
    await saveDocument(doc);
  }

  Future<void> touchUpdatedField() async {
    final doc = activeDocument;
    if (doc == null) return;
    final parsed = FrontmatterCodec.parse(doc.content);
    if (!parsed.hasFrontmatter) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}';
    if (parsed.string('updated') == stamp) return;
    await updateFrontmatter(<String, Object?>{'updated': stamp});
  }

  // ================================================================ 文件管理

  Future<void> renameEntry(String path, String newName) async {
    final library = _library;
    if (library == null) return;
    try {
      final newPath = await library.rename(path, newName);
      final index = _documents.indexWhere((d) => d.path == path);
      if (index >= 0) {
        final old = _documents[index];
        final content = old.content;
        old.controller.removeListener(_onDocumentChanged);
        old.controller.selectionNotifier.removeListener(_onSelectionChanged);
        old.dispose();
        final doc = OpenDocument(
          path: newPath,
          controller: MarkdownEditingController(text: content, theme: markdownTheme),
          savedContent: old.savedContent,
        );
        doc.controller.addListener(_onDocumentChanged);
        doc.controller.selectionNotifier.addListener(_onSelectionChanged);
        _documents[index] = doc;
      }
      requestReveal(newPath);
      refreshTree();
    } on FileSystemException catch (e) {
      showToast('重命名失败：${e.message}');
    }
  }

  Future<void> deleteEntry(String path) async {
    final library = _library;
    if (library == null) return;
    try {
      await library.delete(path);
      final index = _documents.indexWhere((d) => d.path == path);
      if (index >= 0) {
        final doc = _documents[index];
        doc.controller.removeListener(_onDocumentChanged);
        doc.controller.selectionNotifier.removeListener(_onSelectionChanged);
        doc.dispose();
        _documents.removeAt(index);
        if (_documents.isEmpty) {
          _activeIndex = -1;
        } else if (_activeIndex >= _documents.length) {
          _activeIndex = _documents.length - 1;
        }
      }
      _mathCache.remove(path);
      refreshTree();
      await _persist();
    } on FileSystemException catch (e) {
      showToast('删除失败：${e.message}');
    }
  }

  // ================================================================ 搜索

  void setSearchScope(SearchScope scope) {
    if (_searchScope == scope) return;
    _searchScope = scope;
    notifyListeners();
  }

  void setSearchFrontmatter(bool value) {
    if (_searchFrontmatter == value) return;
    _searchFrontmatter = value;
    notifyListeners();
  }

  Future<void> runSearch(String query) async {
    final library = _library;
    _searchQuery = query;
    if (library == null || query.trim().isEmpty) {
      _searchHits = const <SearchHit>[];
      _searching = false;
      notifyListeners();
      return;
    }

    final token = ++_openToken;
    _searching = true;
    notifyListeners();

    final engine = SearchEngine(library);
    final hits = await engine.search(
      query,
      scope: _searchScope,
      searchFrontmatter: _searchFrontmatter,
    );

    if (token != _openToken) return; // 已有更新的搜索，丢掉这次结果
    _searchHits = hits;
    _searching = false;
    notifyListeners();
  }

  Future<void> openHit(SearchHit hit) async {
    await openFile(hit.path);
    if (hit.line != null) {
      // 等一帧布局再跳，否则滚动位置会被重置
      await Future<void>.delayed(const Duration(milliseconds: 60));
      jumpTo(hit.line!, column: hit.column);
    }
  }

  // ================================================================ 预览 / 公式

  String previewSourceFor(OpenDocument doc) => _extractionFor(doc).markdown;

  Map<String, MathFragment> mathFragmentsFor(OpenDocument doc) => _extractionFor(doc).fragments;

  /// 公式提取缓存，同一份内容只扫一次。frontmatter 必须先剥掉：`---` 在
  /// Markdown 里是分隔线，直接渲染会把元数据当正文显示。
  MathExtraction _extractionFor(OpenDocument doc) {
    final content = doc.content;
    final hash = content.hashCode;
    final cached = _mathCache[doc.path];
    if (cached != null && cached.hash == hash) return cached.extraction;
    final body = FrontmatterCodec.parse(content).body;
    final extraction = MathExtractor.extract(body);
    _mathCache[doc.path] = (hash: hash, extraction: extraction);
    return extraction;
  }

  // ================================================================ UI 开关

  void toggleSidebar() {
    _showSidebar = !_showSidebar;
    notifyListeners();
    unawaited(_persist());
  }

  void togglePreview() {
    _showPreview = !_showPreview;
    notifyListeners();
    unawaited(_persist());
  }

  void toggleFrontmatterPanel() {
    _showFrontmatter = !_showFrontmatter;
    notifyListeners();
    unawaited(_persist());
  }

  void toggleDarkMode() {
    _darkMode = !_darkMode;
    markdownTheme = _darkMode ? MarkdownTheme.dark : MarkdownTheme.light;
    for (final doc in _documents) {
      doc.controller.theme = markdownTheme;
    }
    notifyListeners();
    unawaited(_persist());
  }

  void setAutosave(bool value) {
    _autosave = value;
    notifyListeners();
    unawaited(_persist());
  }

  void setPreviewLive(bool value) {
    _previewLive = value;
    notifyListeners();
  }

  void showToast(String message) {
    _toast = message;
    // 计时器要在 dispose 里取消，否则 widget 测试会报 pending Timer。
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (_toast == message) {
        _toast = null;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void clearToast() {
    _toast = null;
    notifyListeners();
  }
}
