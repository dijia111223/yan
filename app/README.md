# 砚（Yan）· 应用本体

纯文件、本地优先的 Markdown 编辑器。**一个文件夹就是一个库。**

Windows / Android 已可用，鸿蒙（HarmonyOS NEXT）适配在途。

---

## 功能（v1 三件套）

### 1. 源码编辑 + 语法高亮

左右分栏：左边写 Markdown 源码，右边实时预览。

- **自研高亮器**，零第三方高亮依赖。两级扫描：行级（frontmatter / 围栏代码块 / 标题 / 引用 / 列表 / 表格 / 分隔线）+ 行内（代码 / 图片 / 链接 / 粗斜体 / 删除线 / 公式）。
- **frontmatter 是一等公民**：`key:` 与 `value` 分色，注释用斜体灰。
- 顶部格式工具条：标题、粗体、斜体、删除线、行内代码、代码块、链接、图片、引用、任务列表、表格、行内公式、行间公式、分隔线。
- 有行号栏，跟随正文滚动。
- 输入法（IME）候选区被特殊处理，中文输入不受高亮干扰。

### 2. 文件树（本地文件夹即库）

- 点击「打开文件夹作为库」选择任意文件夹，**不导入、不复制、不建索引**。
- 懒加载：只读展开的目录，大库也不卡。
- 右键（移动端长按）菜单：新建笔记 / 新建子文件夹 / 重命名 / 删除。
- 排序：名称 A→Z、Z→A、最近修改、最早修改。
- 自动跳过 `.git`、`.obsidian`、`attachments`、`node_modules` 等目录——妙言的附件目录不会被当成笔记列出来。

### 3. 预览渲染（GFM + LaTeX）

用 `markdown` 包解析出 GFM AST，再渲染成 Flutter 组件：

- **表格**（含 GFM 对齐）、**任务列表**（`- [x]` 渲染成复选框）、**删除线**、**自动链接**；
- **代码块**：语言标签 + 自研轻量高亮（Dart / Python / JS / TS / Java / C / C++ / Rust / Go / Bash / SQL 的关键字、字符串、数字、注释）；
- **LaTeX 公式**：`$...$`、`$$...$$`、`\(...\)`、`\[...\]` 四种写法，经 `flutter_math_fork` 渲染。公式解析失败时优雅退化为等宽文本，**不会红屏**；
- 预览可选中复制，右上角可切「实时 / 手动」。

### 4. frontmatter 读写（与统一语料层规范一致）

这是与知识库蓝图的**焊接点**。

- 表单视图：`title` / `created` / `updated` / `source` 输入即写，`tags` 用标签芯片增删；
- 原始 YAML 视图：直接编辑整块 frontmatter；
- **无损**：未识别的字段、注释、字段顺序在回写时全部保留（靠 `yaml_edit` 做字段级编辑，而不是整体重写）；
- YAML 语法坏了也不崩：字段退化为空，但原文照旧保留；
- 新建笔记自动补一份规范模板，含预留的 `lineage` 血缘字段。

```yaml
---
title: 高数 · 极限
created: 2026-09-09
updated: 2026-09-09
tags: [考研, 数学]
source: "《数学分析》第一章"
# lineage: 血缘字段预留，与知识库蓝图统一语料层规范对齐
# lineage:
#   derived_from: []
---
```

### 5. 全文搜索（文件名 + 内容）

- `Ctrl+F` 唤出，输入即搜（250ms 防抖），**纯遍历磁盘，不建索引文件**；
- 文件名命中排在内容命中之前（完全匹配 > 前缀 > 中段）；
- 内容命中显示行号 + 命中片段，并在片段里高亮关键词；
- 标题行（`#`）命中额外加权；
- 可切换「包含 frontmatter」与搜索范围（文件名 / 内容 / 两者）；
- 点击结果自动打开文件并跳到命中行。

---

## 快捷键

| 快捷键 | 功能 |
|---|---|
| `Ctrl+O` | 打开文件夹作为库 |
| `Ctrl+N` | 新建笔记 |
| `Ctrl+S` | 保存 |
| `Ctrl+F` | 全文搜索 |
| `Ctrl+W` | 关闭当前标签 |
| `Ctrl+B` | 显示 / 隐藏文件树 |
| `Ctrl+P` | 显示 / 隐藏预览 |
| `Ctrl+E` | 显示 / 隐藏 frontmatter 面板 |

编辑器内 `Ctrl+Z` / `Ctrl+Y` / `Ctrl+A` / `Ctrl+C/V/X` 走系统默认行为。

---

## 运行

### 环境要求

- Flutter **3.47.4**（stable）或更高；Dart 3.13+
- **Windows**：Visual Studio 2022/2026 生成工具，勾选「使用 C++ 的桌面开发」（含 MSVC + Windows SDK）
- **Android**：Android SDK

### 步骤

```bash
flutter pub get
flutter run -d windows      # 或 -d <android-device-id>
```

### ⚠️ Windows 上的一步额外操作

Flutter 构建带插件的应用时，会为插件创建**符号链接**，而 Windows 创建符号链接需要
管理员权限或**开发者模式**。如果你不想开开发者模式，可以用等价的**目录联接（junction）**替代
（联接不需要任何特权）：

```powershell
pwsh -File tool/prepare_windows_plugins.ps1
```

何时需要重新运行：首次克隆后、`flutter clean` 后、增删依赖后。

> 已开启开发者模式的话，这一步完全不需要。

### 打包

```bash
flutter build windows --release     # 产物在 build/windows/x64/runner/Release/
flutter build apk --release         # 需要 Android SDK
```

---

## 第一次打开推荐这样做

1. `flutter run -d windows` 启动；
2. 点「打开文件夹作为库」，选中 **`assets/sample`** —— 这是内置示例库，能一次看到全部功能；
3. 或直接选你自己已有的 Markdown 笔记文件夹（Obsidian / Typora / 妙言的库都能直接用）。

---

## 目录结构

```
lib/
├── main.dart                       入口
├── app.dart                        主题、深色模式、标题
└── src/
    ├── core/                       不依赖 UI 的纯逻辑（可单测）
    │   ├── models.dart             目录项模型与排序
    │   ├── library.dart            库 = 文件夹；扫描 / 新建 / 重命名 / 删除
    │   ├── frontmatter.dart        frontmatter 无损解析与字段级写回
    │   ├── search.dart             全文搜索（文件名 + 内容）
    │   ├── math_text.dart          LaTeX 公式提取（正确跳过代码块）
    │   ├── markdown_highlighter.dart  Markdown 源码高亮器
    │   └── markdown_theme.dart     深浅两套高亮配色
    ├── state/
    │   ├── workspace.dart          应用状态：库、标签页、自动保存、偏好
    │   ├── editor_controller.dart  带高亮的 TextEditingController
    │   └── workspace_scope.dart    InheritedNotifier 注入
    └── ui/
        ├── shell.dart              三栏主界面 + 快捷键
        ├── file_tree.dart          文件树
        ├── editor_pane.dart        标签页 + 格式工具条
        ├── markdown_editor.dart    行号栏 + 文本域
        ├── markdown_preview.dart   GFM + 公式预览
        ├── search_panel.dart       搜索面板
        ├── frontmatter_panel.dart  frontmatter 面板
        ├── status_bar.dart         状态栏
        └── welcome_view.dart       欢迎页
```

---

## 测试

两层测试，日常用第一层，交付前跑第二层。

### 1. 单元 + widget 测试（快）

```bash
flutter test
```

| 文件 | 覆盖 |
|---|---|
| `frontmatter_test.dart` | 解析边界（CRLF / 未闭合 / YAML 损坏）、字段级更新保留注释、`ensureFrontmatter` |
| `math_text_test.dart` | 四种分隔符、代码块与行内代码里的美元号不动、转义、未配对、跨行规则、LaTeX→Unicode 的上下标与命令边界 |
| `markdown_highlighter_test.dart` | **高亮不丢字**（逐字符比对）、各语义着色、超长文本退化、跳行不改正文 |
| `library_and_search_test.dart` | 真实磁盘读写、排序、跳过规则、重名处理、搜索排序与命中位置 |
| `app_smoke_test.dart` | 真实磁盘库 + 真实界面：打开库 → 点文件 → 编辑 → 自动落盘 → 预览渲染 → frontmatter 面板 → 搜索跳转 → 浅深色切换 |
| `integration_test/font_check_test.dart` | 在**真实 Windows 应用**里核验字体：黑体是否真被解析（宽度指纹法，防止静默回落）、等宽字体是否真等宽、两者是否互相污染 |
| `integration_test/app_e2e_test.dart` | 在**真实 Windows 应用**里跑完整链路：打开库 → 打开笔记 → 编辑落盘 → 预览表格与公式 → 搜索跳转 |

### 2. 端到端测试（跑在真实 Windows 应用里）

```bash
flutter test integration_test -d windows
```

在**真实应用进程**中验证完整链路（真实窗口、真实渲染管线、真实 KaTeX 字体）：
打开库 → 打开笔记 → 编辑并落盘 → 预览渲染表格与公式 → 搜索命中并跳转。

> 自动会先补齐插件目录联接；Windows 上也可以直接跑 `tool\run_e2e.cmd`（带日志）。

---

## 设计取舍（为什么这么做）

- **为什么自研高亮而不是用现成的**：`flutter_highlight` / `highlight` 停更于 Dart 2 时代，
  `sdk: >=2.12.0 <3.0.0` 的上界与 Dart 3.13 不兼容。自研反而更简单——两级扫描约 300 行，
  可单测，还能把 frontmatter 当一等公民。
- **为什么"纯文件"是硬约束**：思源用 `.sy` 私有 JSON，格式被锁死。砚坚持 `.md` + 纯文件夹，
  好处是你的笔记永远能被别的工具读，也能直接丢进 Git。
- **为什么 v1 不做所见即所得**：渲染一致性是很难的问题，源码 + 预览已经覆盖"写"和"看"两个需求。
  按宪章的砍刀规则，砍掉它 v1 还能用，所以砍。
- **为什么行内公式转 Unicode 而不是内嵌组件**：`flutter_markdown` 不支持在段落内部塞组件，
  强行替换块级元素会破坏它内部的 inline 记账并触发断言（详见 `docs/decisions.md` D7）。
  转成 Unicode 文本反而渲染确定、零字体依赖。**看不懂的公式原样保留 LaTeX**，绝不硬猜。
- **为什么配置不用 SQLite**：要存的东西只有"库路径 / 打开的标签 / 分栏开关"这几个键值，
  用平台偏好存储足够；更重要的是，**笔记内容永远不经过任何数据库**。
- **字体为什么不是"全部统一成一种"**：正文与界面统一为**黑体**（Windows 上族名 `SimHei`，
  非 Windows 走回落链到系统无衬线字体，都是黑体风格）；但代码块、frontmatter 源码、公式源码
  **保留等宽字体**——等宽是代码可读性的硬需求（对齐、缩进、字符宽度一致），换成比例字体
  排版就散了。字体定义集中在 `lib/src/core/typography.dart`，只此一处。
- **为什么不用 `fontFamily: 'monospace'` 这个泛型名**：实测在 Windows 上它**解析不到**，
  引擎会静默回落到 CJK 字体，于是拉丁字母被排成全角、代码缩进全乱。因此改用具体族名
  `Consolas` 并给出跨平台回落链。
- **保存怎么保证不写坏文件**：优先"临时文件 + 重命名"（避免断电留下半截文件）；
  但在 Windows 上目标被占用时重命名会失败，此时**退回直接覆写**——先保住用户的字。

---

## 已知限制（诚实清单）

- **鸿蒙端尚未适配**：`pubspec` / 目录结构已预留，W7–8 按排期推进。
- **Android 的 SAF 目录授权（`content://`）尚未支持**：v1 不做"伪文件系统"抽象，
  选择目录时会明确提示而不是假装能用。
- **行尾统一为 LF**：CRLF 文件会被读成 LF 并在保存时写回 LF（v1 不做行尾保留）。
- **文档内锚点链接（`#标题`）暂不跳转**。
- **非 UTF-8 文件**（GBK 等）会被跳过并在搜索中忽略。
- **无外部修改监听**：在别的编辑器里改了同一个文件，需要重新打开该标签才会刷新。

Roadmap 见仓库根目录 `README.md`。
