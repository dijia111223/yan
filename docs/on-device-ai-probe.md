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

## 二、探针做法（不用 CMake）

`build_llama_ohos.ps1`：直接用 OHOS clang 逐文件编译，再由 `link_probe.ps1` 链接。
改探针本身时用 `rebuild_probe.ps1` —— 只重编探针那一个文件再重链，不必全量重跑。

**为什么不用 CMake**：llama.cpp 仓库没有 `ohos.toolchain.cmake`。自造 toolchain 后
CMake 会崩在编译器 ABI 探测阶段（`0xC0000409`）—— 它要**运行**探测产物，
而 OHOS ELF 在 Windows 上跑不起来。设 `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`
也没绕过。逐文件编译虽土，但可控、可复现、报错清楚。

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

**这比原先估计的"手机 CPU 0.5–2 s/token"好一个数量级。** 注意这是 x86_64 模拟器，
真机 ARM 大小核会不同（可能更快、也可能因降频更慢），必须以真机复测为准。

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

- `common/` **有子目录**（`common/parsers/`、`common/jinja/`）。只扫顶层会漏，
  链接报一堆 `undefined symbol`
- `ggml-cpu/arch/` 按架构分目录；`ggml-cpu/spacemit/`、`kleidiai/`、`hexagon/`
  是**独立顶层目录**。这些只针对特定硬件，混编会有约 10 个**必然失败**
- 目标文件名要用**相对路径**做键：`arm/quants.c` 与 `x86/quants.c` 同名，只用 basename 会互相覆盖

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

### 5.6 必须硬失败

脚本一开始"107/116 成功"看着还行，实际链接报一堆 undefined symbol ——
排查成本远高于一开始就报错。现在任何源文件编不过都 `exit 1`。

### 5.7 双 BOS：套了 chat 模板就不能再 `add_special`

最隐蔽的一个。分词时 `add_special=true` 会加 BOS，而 chat 模板输出里**已经带了
`<|im_start|>`**。两者叠加后模型一上来就吐结束符，表现是"只生成几个 token 就停、
输出莫名其妙"。排查时先怀疑提示词构造，实际错在分词参数。

**规则：套模板 → `add_special=false`；裸续写 → `add_special=true`。**

### 5.8 空 sampler chain 会直接断言崩溃

`llama_sampler_sample()` 要求链里**至少有一个 sampler**。空链的 `cur_p.selected`
是 -1，采样时：

```
llama-sampler.cpp:956: GGML_ASSERT(cur_p.selected >= 0 && cur_p.selected < (int32_t) cur_p.size) failed
Signal 6
```

必须 `llama_sampler_chain_add(chain, llama_sampler_init_greedy())`。

### 5.9 停止串必须先跳过思考块

思考块内部也含双换行。若一开始就判停止串，会在 `<think>` 后第一个换行处就截断，
**正文一个字都留不下**（真踩过）。要先用 `</think>` 划出边界，边界之后才开始判停止串。

### 5.10 `printf("%s")` 会在 NUL 处截断，掩盖真实输出

排查时看到 `raw: <think>` 却统计出 24 个 token —— 不是模型只生成了这些，
而是 `%s` 遇到 NUL 就停了。探针改用转义打印（`\n` / `\0` / `\xNN`）。

---

## 六、对产品形态的结论

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
2. **必须有停止串 + 重复检测** —— 小模型会复读，没有截断会一路生成到上限
3. **必须异步 + 可取消** —— 用户继续打字时，在途的推理要能作废

