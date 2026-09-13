# 砚（Yan）· 决策记录

记录做过的技术取舍与踩过的坑。发版后深化的事另说，这里只留**影响过代码的那几条**。

---

## D1 · 语法高亮自研，不用第三方

**背景**：v1 需要"源码编辑 + 语法高亮"。

**踩到的坑**：候选包 `flutter_highlight` / `highlight` 的约束是 `sdk: >=2.12.0 <3.0.0`，
**上界锁死在 Dart 3.0 之前**，而本机 Flutter 3.47.4 自带 Dart 3.13.3 —— 根本装不上。
`re_highlight` 能装但只是 `highlight.js` 的移植，为高亮引入一个语法定义库偏重。

**决策**：自研两级扫描高亮器（`core/markdown_highlighter.dart`）。

**结果**：约 300 行，零依赖，可单测。行级负责 frontmatter / 围栏代码块 / 标题 / 引用 /
列表 / 表格 / 分隔线，行内负责代码 / 图片 / 链接 / 粗斜体 / 删除线 / 公式。
额外好处是 frontmatter 能当一等公民着色（第三方高亮器通常不认识它）。

**守住的底线**：有一条测试逐字符比对"高亮后文本 == 原文"，防止高亮改写内容。

---

## D2 · 预览的架构：AST → Flutter 组件

**决策**：用 `markdown` 包（纯 Dart，无 Flutter 依赖）解析出 GFM AST，
再由 `flutter_markdown` 渲染，**自研 element builder** 接管段落 / 标题 / 列表项 /
表格单元格 / 代码块 / 公式。

**为什么不用现成的**：`flutter_markdown` 官方已标记 discontinued（建议迁 `flutter_markdown_plus`），
但它在 0.7.7+1 上工作正常，且提供了 `MarkdownElementBuilder` 这个刚好够用的扩展点。

**关键设计**：把 Markdown 子节点树**摊平成"文本 + 样式区间"**再渲染，而不是事后改
`TextSpan` 树。原因是 Markdown 的 AST 里 `<strong>` 的文本是**兄弟节点而不是子节点**，
用区间标注比递归改树不容易错。

---

## D3 · LaTeX 公式：占位符替换法

**问题**：`flutter_markdown` 的解析器不认识 `$...$`，`$$...$$` 又会被当成普通段落。

**决策**：解析前先用 `MathExtractor` 把公式抽出来，替换成不透明占位符
（`\u0000YANMATH<n>\u0000`），交给 Markdown 正常渲染；渲染时在文本片段里把占位符
换回 `Math.tex(...)` 组件。

**必须写对的边界**（都有测试）：

- 围栏代码块（``` 与 ~~~）与行内代码（`` ` ``）里的 `$` **一个都不能动**；
- `\$` 是字面量美元号，不是公式起始；
- 未配对的 `$` 不能吞掉整段文字；
- 行间公式可以跨行，但不能跨空行；
- 渲染失败时退化为等宽文本，**绝不红屏**。

---

## D4 · frontmatter 必须无损

**背景**：宪章第 7 节——编辑器的 frontmatter 字段 = 统一语料层规范，是"体用组合"的焊接点。
这意味着用户的 frontmatter 里会有**别人写的、我们不认识的字段和注释**。

**决策**：用 `yaml_edit` 做**字段级编辑**（保留注释、字段顺序、未识别字段），
而不是 `parse → 改 Map → 重新 dump`。

**容错**：YAML 语法坏了也不能让编辑器崩 —— 字段退化为空，但原文照旧保留，用户还能修。
未闭合的 `---` 视为普通正文，避免"吃掉"用户内容。

---

## D5 · Windows 构建：CJK 路径 + 符号链接两道坎

这两条不在计划里，但不解决就无法交付可运行的 Windows 产物。

### 坎一：插件符号链接需要开发者模式

Flutter 构建带插件的应用时，会把 pub 缓存里的插件目录**符号链接**到
`windows/flutter/ephemeral/.plugin_symlinks/`。Windows 创建符号链接需要管理员权限或
开发者模式 —— 本机两者都没有。

**决策**：用**目录联接（junction）**替代。联接不需要任何特权，而 Flutter 只检查该目录
是否存在、并不校验链接类型。脚本：`app/tool/prepare_windows_plugins.ps1`。

**代价**：`flutter clean` 或增删依赖后要重跑一次脚本。已在 README 写明。

### 坎二：MSBuild 读不了 CJK 路径

项目原本在 `C:\Users\耶\workspace\yan`。Dart 编译阶段全部通过，但进入 CMake/MSBuild
阶段后报：

```
error : Unable to read file: C:\Users\鑰禱workspace\yan\app\.dart_tool\flutter_build\<hash>\app.dill
```

用户名里的 `耶` 被按 GBK 解码成了 `鑰` —— MSBuild 读取 Flutter 工具链产出的
UTF-8 路径清单时用了系统 ANSI 代码页，路径因此对不上，`app.dill` 永远读不到。

**决策**：把工程移到纯 ASCII 路径 `C:\yan`，原工作区路径保留为目录联接以便继续访问。

**结论（值得记住的一条）**：**Flutter 的 Windows 构建链路不要放在非 ASCII 路径下。**
中文用户名在新版 Windows 上很常见，遇到 `Unable to read file: ...app.dill` 就该想到这条。

---

## D6 · 测试：真实磁盘 I/O 必须放在 `runAsync` 里

**踩到的坑**：端到端组件测试里 `await state.openFolder(path)` 直接挂死。

**原因**：`flutter_test` 默认在 **fake-async 区域**里执行测试体。真实的文件 I/O 完成回调
永远不会被派发，所以 `await` 一个真实读盘会永久挂起（表现为测试既不通过也不失败）。

**决策**：所有触碰真实磁盘的异步调用统一包在 `tester.runAsync(...)` 里
（`app_smoke_test.dart` 的 `io()` 辅助函数）。

**附带决策**：**不要用 `pumpAndSettle`**。文件树/搜索面板在等异步读盘时会显示
`CircularProgressIndicator`，持续动画让 `pumpAndSettle` 永远无法收敛。改用有界推进
（`settle()` 固定 pump 若干帧）。

**另一条踩坑**：不要用 PowerShell 的 `Set-Content -Encoding utf8` 改这几个 Dart 文件 ——
它会把 UTF-8 中文注释写成乱码。用编辑工具直接改。

---

## D7 · 预览：只替换 pre / code / blockquote

**踩到的坑**：最初用 `MarkdownElementBuilder` 替换 `<p>` 和标题来自定义渲染，
结果**一打开有正文的笔记就崩**：

```
'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
```

**原因**：`MarkdownBuilder` 用一个 `_inlines` 栈拼行内片段，并在 `build()` 结尾断言它已清空。
当自定义 builder 替换掉 `<p>` 这类**内含行内子节点**的块时，库自己 pop 出来的 inline
不会被正常出栈，断言随即失败。

**决策**：只替换 `pre` / `code` / `blockquote` 三类元素，它们（在这个用法下）没有行内子节点，
替换是安全的。为此调整了公式方案：

- **行内公式** `$...$`：在预处理阶段转成 **Unicode 文本**（`latex_to_unicode.dart`），
  随正文正常排版 —— 不需要数学字体、不依赖组件、渲染完全确定；
- **行间公式** `$$...$$`：预处理成 `> <占位符>` 形式，再整体替换成 `flutter_math_fork` 组件。

**关键约束**：转换器是**保守**的 —— 遇到不认识的结构（矩阵、多字母上下标等）返回 `null`，
上层**原样保留 LaTeX 源码**。宁可让用户看到源码，也不要显示一个错的公式。
这条有专门的测试守着。

---

## D8 · 自动保存必须区分"正文变了"和"只是通知了"

**踩到的坑**：切换深色模式后，widget 测试报
`A Timer is still pending even after the widget tree was disposed.`，
栈指向 `_scheduleAutosave`。

**原因**：`MarkdownEditingController.theme=` 会 `notifyListeners()`，而
`WorkspaceState` 把 controller 的**任意**通知都当成"内容变了"，于是排出一个
毫无意义的自动保存定时器（还会在退出后触发一次重建）。

**决策**：`OpenDocument` 记一个 `lastObservedText`，只有 `controller.text` 真的
变化时才排自动保存。保存后同步更新 `savedContent` 与 `lastObservedText`，
并取消排队中的定时器。

**顺带修掉的两个真实缺陷**：

1. **保存用"临时文件 + 重命名"在 Windows 上会失败**：目标文件被占用时
   `rename` 直接报 `Cannot rename file to ...`，而用户打开的笔记恰恰常被占用。
   现在重命名失败会**退回直接覆写** —— 先保住用户的字，再谈原子性。
2. **提示（toast）的定时器没有取消**：`showToast` 用一个 3 秒的延迟回调清空提示，
   组件销毁后仍会触发。现在持有该 `Timer` 并在 `dispose()` 里取消。

---

## D9 · Windows 构建还有两道编码坎

### 坎三：`main.cpp` 不能有非 ASCII 字符

MSVC 用系统代码页（本机 936）编译，`main.cpp` 里的中文注释触发
`warning C4819`，而 Flutter 的 runner 工程把警告当错误（`/WX`），构建直接失败。

**决策**：`windows/runner/main.cpp` 保持**纯 ASCII**，窗口标题用 `\u` 转义写：
`L"\u781a Yan"`。同类问题也适用于 `tool/prepare_windows_plugins.ps1`
（Windows PowerShell 5.1 按 ANSI 读 `.ps1`，中文注释会让脚本解析失败）。

### 坎四：`flutter pub get` 会清掉插件联接

`pub get` 会重建 `windows/flutter/ephemeral/`，把 `.plugin_symlinks` 里的目录联接一起删掉，
下一次构建又回到"需要开发者模式"。

**决策**：把"建联接 + 跑测试/构建"串成一个脚本（`tool/run_e2e.cmd`），
每次都先补齐联接，避免这个隐式依赖被忘记。

---

## D10 · 端到端验证在真实 Windows 应用里做

**背景**：headless 的 `flutter test` 有几个**环境限制**，会把"环境不支持"误判成"功能坏了"：

- 真实文件 I/O 的回调在 fake-async 区不会派发（`await` 真实读盘会挂死）；
- 加载不到 KaTeX 字体，`Math.tex` 会走 `onErrorFallback`；
- `WidgetTester.tap` 发的是合成指针事件，验证的是 widget 逻辑而非真实窗口。

**决策**：分两层测试。

- `test/` —— 纯逻辑 + widget 行为，跑得快，日常用；
- `integration_test/` —— 在**真实 Windows 应用进程**里跑完整链路
  （打开库 → 打开笔记 → 编辑落盘 → 预览渲染表格/公式 → 搜索跳转），
  命令：`flutter test integration_test -d windows`。

**同时记下一条失败经验**：尝试用 `SendKeys` / `mouse_event` / UI Automation 去点真实窗口
**不可靠** —— Flutter 默认不构建语义树，UIA 只能看到一个顶层窗口，合成鼠标事件也进不去
Flutter 的命中测试。验证真实应用请用 `integration_test`，不要靠 GUI 自动化脚本。

---

## D11 · 字体：正文黑体，代码等宽

**需求**：正文与界面统一用黑体。

**决策**：正文/界面 → 黑体（Windows 族名 `SimHei`），跨平台回落链到系统无衬线字体；
**代码块 / frontmatter 源码 / 公式源码保留等宽字体**。理由：等宽是代码可读性的硬需求
（对齐、缩进、字符宽度一致），换成比例字体排版就散了。定义集中在 `core/typography.dart`。

### 踩坑一：字体名写错不会报错，只会静默回落

这是本次最花时间的一处。**Flutter 找不到指定字体族时不抛异常**，只是悄悄换一份字体渲染，
肉眼几乎无法分辨。为了确认"黑体真的生效"，连续否决了三种测量方案：

| 方案 | 为什么不行 |
|---|---|
| 渲染宽度（汉字） | 汉字全角，黑体与宋体推进宽度**相同**，无法区分 |
| 字形位图逐像素比对 | `Picture.toImage` 在测试环境拿不到真实像素，恒为空白，所有差异都是 0 |
| 字形 ID（glyph id） | `ui.GlyphInfo` 不暴露 glyphId；`TextPainter` 也没有 `getGlyphInfoAt` |

**最终可用的判据是"宽度指纹法"**：先量出本机三个参照族名对同一段中英混排文本的固有宽度
（雅黑 640.0 / 不存在的族名 633.50 / 宋体 620.0），再看应用字体落在哪个指纹上。
`SimHei` 实测 620.0 —— 既不等于雅黑也不等于默认回落，**证明它确实被解析到了**。

两个附带教训：

1. `TextPainter.width` 是**文本固有宽度**，可用；而 `tester.getSize(find.byType(Text))`
   量到的是**父级约束宽度**（放进 `Center` 就是整屏宽），会给出恒定假值——我在这上面绕了弯路。
2. 断言要挑**有区分度**的量。曾用 Consolas 与黑体渲染同一段汉字比宽度，结果两者完全相等 ——
   因为 Consolas 本就没有汉字字形、渲染汉字时正常回落到中文字体。那是正确行为，不是 bug。
   换成拉丁字母后立刻能区分（219.92 vs 200.0）。

### 踩坑二：`fontFamily: 'monospace'` 在 Windows 上解析不到

这个泛型名在 Windows 上**不生效**，引擎回落到 CJK 字体，导致拉丁字母被排成**全角**、
代码缩进全乱。改用具体族名 `Consolas` + 跨平台回落链后正常。

**验证方式**（等宽是可测量的事实）：改良后的判据是"每字符 em 比值" ——
真等宽字体约 0.5–0.65 em，CJK 全角回落会到 1.0 em。实测 Consolas 为 **0.550 em**，
且 `4xi == 4xW`（等宽字体所有字形推进宽度相同，这正是等宽的定义）。

---

## D12 · 端侧 AI 补全：分两层，格式补全走规则、文字预测走裸续写

**背景**：要在应用里内置 0.5B 级模型，做 Markdown 格式自动补全 + 文字预测。

**先验假设是错的**。动手前写的估计是"手机 CPU 0.5–2 秒/token，逐键补全不可行"。
探针在鸿蒙模拟器上实测（Qwen3-0.6B Q4_K_M，x86_64，4 线程）：

| 指标 | 实测 |
|---|---|
| 模型加载 | 300–500 ms |
| Prefill | 32–41 tok/s |
| Decode | **18–21 tok/s**（约 50 ms/token）|
| 峰值内存 | 485 MB |

比先验估计好一个数量级。**但结论没变，理由变了**——真正的瓶颈不是速度，是 Qwen3 的思考块。

**踩到的坑：思考块吃掉全部预算。** 套 chat 模板后模型先输出 `<think>...</think>`：

| 场景 | 总 token | 思考 token | 思考耗时 | 正文 |
|---|---|---|---|---|
| 段落续写 | 120 | 120 | 6.1 s | 一个字都没出 |
| 中文长文 | 195 | 119 | 6.5 s | 76 token |
| 句内补全 | 60 | 60 | 3.0 s | 一个字都没出 |

提示词里写 `/no_think` **无效**：Qwen3 模板靠 jinja 变量 `enable_thinking` 控制，
而 llama.cpp 的 C API `llama_chat_apply_template` **不是 jinja 解析器**，
只匹配内置模板列表并硬编码输出，传不进这个变量。

**决策**：

1. **Markdown 格式补全 → 确定性规则，不用模型**（`core/markdown_edit_assist.dart`）。
   列表续行、围栏闭合、括号配对、表格 Tab 跳转、智能退格。零延迟、可单测、100% 可预测。
   模型做这件事既慢又不保证正确——**用模型做格式补全是拿确定性换不确定性**。
2. **文字预测 → 裸续写（不套 chat 模板）**。实测 `--raw` 下思考块完全消失，首 token 约 50 ms。
   而且这在语义上更对：补全的输入本来就是"文档里已有的半句话"，不是"给助手的指令"，
   套 chat 模板属于错的产品形态。
3. **异步 + 可取消**。20 tok/s 下每个建议仍需 50 ms × N，且会与输入法抢主线程。
   用户继续打字时，在途推理必须能作废。

**另外两个必须实现的东西**（实测出来的，不是预防性设计）：

- **停止串**：没有它生成会一路跑到上限，延迟不可控。按光标所在行形态选 ——
  结构化行（表格 / 列表 / 引用 / 标题）取下一个换行；普通段落取句子边界
  （`。！？；…`）与换行。判定必须**先回调后截断**，顺序反了会把已吐出的字符又抹掉
  （实测表格续写丢行尾 `|`）。
- **有界预算**：默认只生成 24 token。

**一个被实测否掉的方案**：原本打算"检测到复读就截断"。0.6B 的复读是**递增式**的
（每次都拼一个新组合：`Markdown+CSS`、`Markdown+XML`、`Markdown+HTML`、…），
**并非重复同一段**，所以按片段复用率度量只有 0.30–0.46，够不到阈值，
而且输出越长该值越低。**递增式复读没有便宜的判据**，只能靠有界预算 + 停止串 +
回调可取消来兜。复读检测保留为兜底，不是主防线。

**待办约束**：

- 485 MB 峰值内存是硬门槛，低端机需评估，该功能必须可关闭。
- **速度数据的适用性要打折**：18–20 tok/s 来自 **x86_64 模拟器**，
  它跑在桌面级 CPU 上；真机 ARM 核可能慢 2–5 倍。若真是 150–250 ms/token，
  "首 token 约 50 ms、可做流式"这个结论会动摇，但"异步 + 有界预算"的架构
  不受影响 —— 这正是先做架构、再谈体验的原因。真机数据必须补测。
- ARM64 只验证到"264 个源文件全部编过 + 链接出 libyan_ai.so（AArch64）"，
  **没有在 ARM64 上实际运行过**（本机只有 x86_64 模拟器）。


