# 鸿蒙端侧推理探针 · 进展与踩坑记录

> 目标：验证**能不能在鸿蒙（OpenHarmony）上跑端侧 LLM 推理**。
>
> **当前状态：探针通过 ✅** —— llama.cpp 在 OHOS 上编过、链过、**在模拟器上真实跑出推理结果**。
> 模型：Qwen3-0.6B Q4_K_M（378 MB）。实测 18–20 token/s、峰值内存 485 MB、首 token 约 50 ms。
>
> 所有工作在 `C:\ohos-ai-probe`（探针，不进产品代码）；
> 可复用的脚本已归档到 `app/tool/ohos-ai/`。

---

## 一、已确认可行的事实

| 事项 | 结果 | 证据 |
|---|---|---|
| 鸿蒙有原生 NDK | ✅ | `DevEco Studio\sdk\default\openharmony\native\`：clang 15.0.4 / cmake 3.28.2 / ninja |
| 能交叉编译 OHOS 可执行文件 | ✅ | `clang --target=x86_64-linux-ohos --sysroot=...` 产出 ELF64，`readelf` 确认 |
| OHOS ELF 无法在 Windows 宿主运行 | ✅（约束） | `%1 is not a valid Win32 application` —— 产物只能上设备验 |
| llama.cpp 能全部编过 | ✅ **266/266** | `build_llama_ohos.ps1`，见下节 |
| llama.cpp 能在鸿蒙上链接 | ✅ | 266 个目标文件 → 10 MB 静态链接可执行文件 |
| **能在鸿蒙上真实推理** | ✅ | 模拟器上加载模型 + prefill + 逐 token 生成，见第五节 |
| `ai_engine` 是可靠路径吗 | ❌ | 它是 OpenHarmony **系统服务**（`/foundation/ai/ai_engine`），偏开发板场景，商用手机第三方应用大概率用不到 |

---

## 二、探针做法（逐文件编译）

`build_llama_ohos.ps1`：直接用 OHOS clang 逐文件编译，再由 `link_probe.ps1` 链接。
改探针本身时用 `rebuild_probe.ps1` —— 只重编探针那一个文件再重链，不必全量重跑。

**为什么探针不用 CMake**：llama.cpp 仓库没有 `ohos.toolchain.cmake`。自造 toolchain 后
CMake 会崩在编译器 ABI 探测阶段（`0xC0000409`）—— 它要**运行**探测产物，
而 OHOS ELF 在 Windows 上跑不起来。设 `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`
也没绕过。逐文件编译虽土，但可控、可复现、报错清楚。

### 但集成进应用时必须用 CMake —— 而且可行

上面那个崩溃**是自造 toolchain 造成的，不是 CMake 的锅**。DevEco SDK 自带官方
toolchain，用它可以正常交叉编译：

```
<DevEco SDK>\default\openharmony\native\build\cmake\ohos.toolchain.cmake
```

实测：官方 toolchain 下 CMake 配置 1–2 秒完成、ABI 探测正常、产出 AArch64 共享库。

这一点是集成的前提，因为 **hvigor 编译 HAR 时走的就是 CMake** —— `plugin_ffi`
模板的 `build-profile.json5` 里：

```json5
"buildOption": {
  "externalNativeOptions": { "path": "../src/CMakeLists.txt" }
}
```

所以集成路径是：**FFI 插件（HAR）→ `externalNativeOptions` → 我们的 CMakeLists
→ `libyan_ai.so` → Dart 侧 `DynamicLibrary.open('libyan_ai.so')`**。
ohos Flutter fork 的 `plugin_ffi` Dart 模板里 `Platform.isOhos` 分支是现成的。

用 CMake 还必须显式指定 C++ 标准，否则报 `no template named 'is_same_v'`：

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
```

---

## 三、上设备验证的方法

OHOS ELF 在 Windows 宿主上跑不起来，所以每次改动都必须：

```powershell
# 1. 只重编探针 + 重链（266 个目标文件都还在，不必全量重跑）
powershell -File app/tool/ohos-ai/rebuild_probe.ps1

# 2. 推到模拟器
& "$hdc" -t 127.0.0.1:5555 file send out\yan_probe_ohos_x86_64 /data/local/tmp/yanprobe/yan_probe
& "$hdc" -t 127.0.0.1:5555 shell "chmod 755 /data/local/tmp/yanprobe/yan_probe"

# 3. 在设备上跑（hdc 不在 PATH，要用全路径）
& "$hdc" -t 127.0.0.1:5555 shell "cd /data/local/tmp/yanprobe && ./yan_probe model.gguf '<提示词>' 64"
```

`$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'`

两个 hdc 使用上的坑：

- **`\n` 会被当字面字符**，提示词里的换行要写成 `$'...\n...'` 让设备侧 shell 解析
- **`$?` 回显成 `True`**，别指望从退出码判断成败，以探针自己打印的 `RESULT: OK` 为准

---

## 四、设备实测数据（模拟器 x86_64，4 线程）

| 指标 | 数值 |
|---|---|
| 模型加载 | 300–500 ms |
| Prefill | 32–41 tok/s |
| **Decode（生成）** | **18–21 tok/s**（约 50 ms/token）|
| 峰值内存（VmHWM） | 483–486 MB |

**这比原先估计的"手机 CPU 0.5–2 s/token"好一个数量级。**

> ⚠️ **但这组数据必须打折看**：它来自 **x86_64 模拟器**，跑在桌面级 CPU 上。
> 真机 ARM 核（尤其被降频时）可能慢 2–5 倍。若真是 150–250 ms/token，
> "首 token 约 50 ms、可以做流式"会动摇，但**不影响"异步 + 有界预算"的架构**。
> 真机数据必须补测。

### 4.1 决定成败的发现：Qwen3 的思考块必须绕开

Qwen3 是 reasoning 模型，套 chat 模板后会先输出 `<think>...</think>`。实测代价：

| 场景 | 总 token | 思考 token | 思考耗时 | 正文 |
|---|---|---|---|---|
| 段落续写 | 120 | **120（全部）** | 6.1 s | 一个字都没出 |
| 中文长文 | 195 | 119（61%） | 6.5 s | 76 token |
| 句内补全 | 60 | **60（全部）** | 3.0 s | 一个字都没出 |

**思考块吃掉 3–6 秒，两个场景把预算全烧光、正文一个字都没留下。**

提示词里写 `/no_think` **无效** —— Qwen3 的模板靠 jinja 变量 `enable_thinking` 控制，
而 llama.cpp 的 C API `llama_chat_apply_template` **不是 jinja 解析器**，
只匹配一份内置模板列表并硬编码输出，传不进这个变量。

**解法：补全走裸续写（`--raw`，不套 chat 模板）。** 因为补全的输入本来就是
"文档里已有的半句话"，而不是"给助手的指令"，套 chat 模板反而是错的产品形态。
实测 `--raw` 下思考块完全消失，首 token 约 50 ms。

### 4.2 补全质量实测（`--raw`）

表格补全 —— 从 `| Windows | 已发布 |` 往下接，语法完全正确：

```
 Linux | 已发布 |
| macOS | 已发布 |
| Android | 已发布 |
| iOS | 已发布 |
```

中文长文（套模板、剥掉思考块后的正文）—— 质量出乎意料地好：

> Markdown是一种用于创建结构化文本的标记语言，通过特定的语法格式化内容，如代码块、
> 链接、列表等，使技术文档更易读。它不仅支持跨平台兼容性，还具备可编辑性，便于团队
> 协作与版本管理。因此，Markdown 非常适合用于编写技术文档，提升文档的可维护性。

**但小模型会复读**：同一场景几行之后开始循环（`Markdown+CSS`、`Markdown+XML` 无限重复）。
这是 0.6B 模型在贪心采样下的典型行为，**生产实现必须自己加重复检测与截断**，
不能只靠贪心。也说明停止串不能省 —— 没有它生成会一路跑到上限，延迟不可控。

---

## 五、踩过的坑（都是真的，值得记）

### 5.1 OHOS 定义了 `__linux__`，glibc 专有 API 被误启用

```
common/common.cpp:165: error: use of undeclared identifier 'pthread_setaffinity_np'
```

OHOS 的 clang 定义了 `__linux__`，于是 llama.cpp 里
`#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)`
这些块被启用，而它们用的是 **glibc 专有**的 `pthread_setaffinity_np` /
`pthread_getaffinity_np`。OHOS sysroot 只有 `sched_setaffinity`。

**处理**：`patch_llama_for_ohos.ps1` 给这些守卫加 `!defined(__OHOS__)`，与 Android 同样对待。
**代价**：OHOS 上不做 CPU 亲和性绑定与大小核识别 —— 只影响调度优化，不影响推理正确性。

### 5.2 三个文件由 CMake 生成，不走 CMake 就得自己生成

- `src/llama-version.h`、`ggml/src/ggml-version.h`
- `common/build-info.cpp` → 少了它链接报 `undefined symbol: llama_print_build_info`

### 5.3 源文件清单要递归、要按架构裁剪、键要唯一

这一类错误**全是静默的** —— 编译不报错，只在链接期缺符号、或者换一个模型才炸。

- `src/` **有子目录**，且 `src/models/` 下有 **150+ 个模型架构实现**。只扫顶层会漏掉它们。
  危险之处在于**漏了不一定立刻发现**：模型注册表靠静态初始化，Qwen3 的实现恰好是顶层的
  `qwen3.cpp`，所以"只测 Qwen3"时看不出问题 —— 换成 Llama、Gemma 任何别的架构才会崩。
  实测：修递归前 aarch64 只编 **107** 个文件，修后 **260** 个

  ```powershell
  # 错：只扫顶层
  Get-ChildItem "$LlamaSrc\src" -Filter '*.cpp' | ...
  # 对：递归
  Get-ChildItem "$LlamaSrc\src" -Filter '*.cpp' -Recurse | ...
  ```

- `common/` **也有子目录**（`common/parsers/`、`common/jinja/`）。只扫顶层会漏，
  链接报一堆 `undefined symbol`
- `ggml-cpu/arch/` 按架构分目录；`ggml-cpu/spacemit/`、`kleidiai/`、`hexagon/`
  是**独立顶层目录**。这些只针对特定硬件，混编会有约 10 个**必然失败**
- 目标文件名要用**相对路径**做键：`arm/quants.c` 与 `x86/quants.c` 同名，只用 basename 会互相覆盖
- **扩展名必须保留在键里**：`ggml-cpu.c` 与 `ggml-cpu.cpp` 去掉扩展名后同名，
  只留一个会让另一个**永远不参与编译**。aarch64 就是这样丢了 `gguf.cpp`、
  `ggml-backend-dl.cpp`、`ggml-backend-meta.cpp`、`ggml-cpu.c`，
  链接期报 `undefined symbol: gguf_init_from_file`。把扩展名的点也换成连字符即可：

  ```powershell
  $key = ($rel -replace '[\\/]', '-') -replace '\.(c|cpp)$', '-$1'
  ```

**改完命名规则必须清空产物目录重编**，否则新旧目标文件名混在一起，链接会取到旧的那批。

### 5.4 头文件遮蔽（最坑的一个，两个都是同名头）

项目里有**两对同名头**，`-I` 顺序会让错的胜出：

| 冲突 | 症状 |
|---|---|
| `src/unicode.h` vs `common/unicode.h` | `common_parse_utf8_codepoint` 找不到（声明只在 common 那份） |
| `common/jinja/string.h` vs libc++ 的 `<string>` | `no member named 'memcpy' in namespace 'std'` 这类莫名其妙的错 |

**结论**：不要为了"方便"把 `common/jinja` 之类的子目录加进 `-I`；
需要时用显式相对路径（如 `#include "../unicode.h"`）。

### 5.5 PowerShell 的坑

- **`if (...) { $a \| Where {...} + @(...) }` 不合法** —— 表达式位置不能用数组 `+`，
  报 `A positional parameter cannot be found that accepts argument '+'`。必须写成语句块
- **clang 的 `@参数文件` 里含空格的项必须加引号**，否则
  `--sysroot=C:/Program Files/...` 被按空格拆成多个参数
- **长命令会被超时打断**：链接要十几分钟，内联长命令会被 kill。
  用参数文件 + `Start-Process` 脱离方式更稳
- **PowerShell 5.1 不支持三元运算符 `? :`**，会报 `Unexpected token '?'`
- **`ForEach-Object` 块里的 `return` 只结束当前迭代**，但它与 `$script:` 计数器、
  新建文件的枚举顺序掺在一起时行为很难推理 —— 这种"逐个改文件并回读确认"的活
  直接用 `foreach` 循环写，可读且确定
- **`$PSScriptRoot` 在 `powershell -File` 下可能为空**，脚本会静默地只处理当前目录。
  用 `Split-Path -Parent $MyInvocation.MyCommand.Path` 兜底

### 5.6 含中文的 `.ps1` 丢了 BOM，报错完全指向别处

Windows PowerShell 5.1 在没有 BOM 时按**系统 ANSI 代码页**（简体中文为 GBK）读脚本。
中文变乱码，而**乱码里恰好含引号就会破坏语法**：

```
Write-Host "鏈?$($failed.Count) 涓簮鏂囦欢鏈紪杩囷紝鍚庣画閾炬帴蹇呯劧澶辫触锛? -ForegroundColor ...
The string is missing the terminator: ".
```

报的是"字符串没结束"，看着像引号配对写错了，实际原因在文件编码。

**更麻烦的是编辑工具写入时会丢掉 BOM** —— 每次改完脚本都要补，否则下次运行必炸。
`fix_ps1_bom.ps1` 负责这件事（逐个回读确认，不凭"写过了"就认为成功）：

```powershell
$text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding($true)))
```

### 5.7 必须硬失败

脚本一开始"107/116 成功"看着还行，实际链接报一堆 undefined symbol ——
排查成本远高于一开始就报错。现在任何源文件编不过都 `exit 1`。

### 5.8 双 BOS：套了 chat 模板就不能再 `add_special`

最隐蔽的一个。分词时 `add_special=true` 会加 BOS，而 chat 模板输出里**已经带了
`<|im_start|>`**。两者叠加后模型一上来就吐结束符，表现是"只生成几个 token 就停、
输出莫名其妙"。排查时先怀疑提示词构造，实际错在分词参数。

**规则：套模板 → `add_special=false`；裸续写 → `add_special=true`。**

### 5.9 空 sampler chain 会直接断言崩溃

`llama_sampler_sample()` 要求链里**至少有一个 sampler**。空链的 `cur_p.selected`
是 -1，采样时：

```
llama-sampler.cpp:956: GGML_ASSERT(cur_p.selected >= 0 && cur_p.selected < (int32_t) cur_p.size) failed
Signal 6
```

必须 `llama_sampler_chain_add(chain, llama_sampler_init_greedy())`。

### 5.10 停止串必须先跳过思考块

思考块内部也含双换行。若一开始就判停止串，会在 `<think>` 后第一个换行处就截断，
**正文一个字都留不下**（真踩过）。要先用 `</think>` 划出边界，边界之后才开始判停止串。

### 5.11 停止串不能放在回调之后判定

先截断、再回调，会出现"**已经吐给调用方的字符又被从结果里去掉**"的不一致 ——
实测表现为表格续写丢掉了行尾的 `|`。**必须先回调、后判定**，让消费者看到的
与最终结果一致。

### 5.12 `printf("%s")` 会在 NUL 处截断，掩盖真实输出

排查时看到 `raw: <think>` 却统计出 24 个 token —— 不是模型只生成了这些，
而是 `%s` 遇到 NUL 就停了。探针改用转义打印（`\n` / `\0` / `\xNN`）。

---

## 六、桥接层（应用真正要用的接口）

探针证明了"能跑"，但探针是一次性程序。应用需要的是**模型只加载一次、可反复补全**
的接口。这部分在 `app/tool/ohos-ai/yan_ai.cpp`（C API，`yan_ai.h` 是头文件）。

| 接口 | 作用 |
|---|---|
| `yan_ai_load` / `yan_ai_unload` / `yan_ai_is_loaded` | 会话生命周期 |
| `yan_ai_complete` | 阻塞式补全，逐 token 回调，返回停止原因 |
| `yan_ai_cancel` | 从其它线程打断生成 |

### 6.1 设备实测（模拟器 x86_64，Qwen3-0.6B Q4_K_M）

三次连续补全**共用一次模型加载**，全部通过：

| 用例 | 输出 | 停止原因 |
|---|---|---|
| 表格续写 | ` Linux \| 已发布 \|` | `stop` |
| 段落续写 | `支持多种格式，包括但不限于 HTML、CSS、XML、Markdown、Markdown+CSS、…` | `max` |
| 列表续写 | ` 支持 Android` | `stop` |

加载模型后，三次补全总计约 3–5 秒（含设备传输），**没有重新加载模型**。

### 6.2 放弃"复读度量"作为主要防线（重要）

原本的设计是"检测到复读就截断"。实测发现**这个思路不成立**：

0.6B 的复读是**递增式**的 —— 每次都拼一个新组合
（`Markdown+CSS`、`Markdown+XML`、`Markdown+HTML`、`Markdown+CSS+XML`、…），
**并非重复同一段**。所以按"片段复用率"度量出来只有 **0.30–0.46**，
远达不到判定阈值，而且**输出越长该值越低**（109 字节时 0.30）。

结论：递增式复读**没有低成本的可靠判据**。真正的防线是另外三个：

1. **有界预算** —— 默认只生成 24 token。这个量级是"一条建议"，不是"一段文章"。
   降到 24 后输出立刻变得可用（`…Markdown+CSS、Markdown+XML、Markdown+` 被干净截断）
2. **停止串** —— 按光标所在行形态选：
   - 结构化行（表格 / 列表 / 引用 / 标题 / 有序列表）→ 下一个换行
   - 普通段落 → 句子边界（`。！？；…`）与换行
3. **回调里可取消** —— 调用方（应用）觉得输出没价值就直接返回非 0，立刻停止

复读检测保留为兜底，但**不再当作主要机制**。

---

## 七、对产品形态的结论

实测数据推翻了"手机 CPU 太慢、只能异步"的悲观估计，但**没有**推翻"要异步"这个结论，
理由变了：

| 项 | 结论 |
|---|---|
| Markdown 格式补全 | 用**确定性规则**（已实现，零延迟、比模型更准，见 `markdown_edit_assist.dart`）|
| 文字预测 | **异步**，但不必延迟到"出结果才显示"—— 首 token 约 50 ms，可以做流式 |
| 逐键同步补全 | 仍不可行：20 tok/s 下每个建议要 50 ms×N，且会与输入法抢占主线程 |
| 内存 | **485 MB 峰值是硬约束**，低端机需评估；这也是必须可选、可关闭的功能 |

**关键设计约束**：

1. **必须走裸续写**，不能套 chat 模板 —— 否则每次建议都先付 3–6 秒思考税
2. **必须有停止串 + 有界预算** —— 小模型会递增式复读，且没有便宜的判据能识别它
3. **必须异步 + 可取消** —— 用户继续打字时，在途的推理要能作废
4. **模型只加载一次** —— 378 MB 的模型每次补全都重载是不可接受的（桥接层已实现会话复用）

### 7.1 集成路径（已验证可行）

```
FFI 插件（HAR）
  └─ build-profile.json5: buildOption.externalNativeOptions.path = "../src/CMakeLists.txt"
       └─ hvigor 用 DevEco SDK 官方 ohos.toolchain.cmake 调 CMake
            └─ libyan_ai.so（AArch64，11.5 MB，导出 5 个 yan_ai_* 符号）
                 └─ Dart: DynamicLibrary.open('libyan_ai.so')
```

CMake 路径实测通过：配置 1–2 秒、265 个源文件全部编过、产出 AArch64 共享库。
`plugin_ffi` 的 Dart 模板里 `Platform.isOhos` 分支是现成的，不需要自造。

### 7.2 还没做的

- **Dart FFI 绑定**与编辑器集成（补全建议的 UI 呈现、接受/忽略交互）
- **模型分发**：378 MB 不适合打进 HAP，需要"首次启动下载"或"用户导入"流程
- **真机验证**：本机只有 x86_64 模拟器，ARM64 真机的速度与内存未实测
- **内存评估**：485 MB 峰值在中低端机上是否可接受，需要真机确认


