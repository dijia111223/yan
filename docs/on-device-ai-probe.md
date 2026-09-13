# 鸿蒙端侧推理探针 · 进展与踩坑记录

> 目标：验证**能不能在鸿蒙（OpenHarmony）上跑端侧 LLM 推理**。
>
> **当前状态（暂停点）：llama.cpp 的 107 个源文件在 OHOS 工具链下全部编译通过，
> 只差最后一步链接。** 未上设备验证。
>
> 所有工作在 `C:\ohos-ai-probe`（探针，不进产品代码）；
> 可复用的脚本已归档到 `app/tool/ohos-ai/`。

---

## 暂停点：下一步做什么（明确、可执行）

1. 跑 `app/tool/ohos-ai/link_probe.ps1` 链接出 `yan_probe`
   （约十几分钟，务必用 `Start-Process` 脱离方式跑，内联长命令会被超时打断）
2. 若链接成功 → 用 `hdc file send` 推到模拟器，**在设备上执行**（OHOS ELF 不能在 Windows 跑）
3. 需要一个能加载的 GGUF 模型。探针只验证"能加载 + 能前向出 token"，最小模型即可
4. 拿到**设备上的真实输出**才算探针通过

---

## 一、已确认可行的事实

| 事项 | 结果 | 证据 |
|---|---|---|
| 鸿蒙有原生 NDK | ✅ | `DevEco Studio\sdk\default\openharmony\native\`：clang 15.0.4 / cmake 3.28.2 / ninja |
| 能交叉编译 OHOS 可执行文件 | ✅ | `clang --target=x86_64-linux-ohos --sysroot=...` 产出 ELF64，`readelf` 确认 |
| OHOS ELF 无法在 Windows 宿主运行 | ✅（约束） | `%1 is not a valid Win32 application` —— 产物只能上设备验 |
| **llama.cpp 能全部编过** | ✅ **107/107** | `build_llama_ohos.ps1`，见下节 |
| `ai_engine` 是可靠路径吗 | ❌ | 它是 OpenHarmony **系统服务**（`/foundation/ai/ai_engine`），偏开发板场景，商用手机第三方应用大概率用不到 |

**最关键的一条**：llama.cpp 的源码**能全部用 OHOS clang 编过** ——
这说明"鸿蒙上跑 llama.cpp"在编译层面可行，不是死路。

---

## 二、探针做法（不用 CMake）

`build_llama_ohos.ps1`：直接用 OHOS clang 逐文件编译，再由 `link_probe.ps1` 链接。

**为什么不用 CMake**：llama.cpp 仓库没有 `ohos.toolchain.cmake`。自造 toolchain 后
CMake 会崩在编译器 ABI 探测阶段（`0xC0000409`）—— 它要**运行**探测产物，
而 OHOS ELF 在 Windows 上跑不起来。设 `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`
也没绕过。逐文件编译虽土，但可控、可复现、报错清楚。

---

## 三、踩过的坑（都是真的，值得记）

### 1. OHOS 定义了 `__linux__`，glibc 专有 API 被误启用

```
common/common.cpp:165: error: use of undeclared identifier 'pthread_setaffinity_np'
```

OHOS 的 clang 定义了 `__linux__`，于是 llama.cpp 里
`#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)`
这些块被启用，而它们用的是 **glibc 专有**的 `pthread_setaffinity_np` /
`pthread_getaffinity_np`。OHOS sysroot 只有 `sched_setaffinity`。

**处理**：`patch_llama_for_ohos.ps1` 给这些守卫加 `!defined(__OHOS__)`，与 Android 同样对待。
**代价**：OHOS 上不做 CPU 亲和性绑定与大小核识别 —— 只影响调度优化，不影响推理正确性。

### 2. 三个文件由 CMake 生成，不走 CMake 就得自己生成

- `src/llama-version.h`、`ggml/src/ggml-version.h`
- `common/build-info.cpp` → 少了它链接报 `undefined symbol: llama_print_build_info`

### 3. 源文件清单要递归、要按架构裁剪、键要唯一

- `common/` **有子目录**（`common/parsers/`、`common/jinja/`）。只扫顶层会漏，
  链接报一堆 `undefined symbol`
- `ggml-cpu/arch/` 按架构分目录；`ggml-cpu/spacemit/`、`kleidiai/`、`hexagon/`
  是**独立顶层目录**。这些只针对特定硬件，混编会有约 10 个**必然失败**
- 目标文件名要用**相对路径**做键：`arm/quants.c` 与 `x86/quants.c` 同名，只用 basename 会互相覆盖

### 4. 头文件遮蔽（最坑的一个，两个都是同名头）

项目里有**两对同名头**，`-I` 顺序会让错的胜出：

| 冲突 | 症状 |
|---|---|
| `src/unicode.h` vs `common/unicode.h` | `common_parse_utf8_codepoint` 找不到（声明只在 common 那份） |
| `common/jinja/string.h` vs libc++ 的 `<string>` | `no member named 'memcpy' in namespace 'std'` 这类莫名其妙的错 |

**结论**：不要为了"方便"把 `common/jinja` 之类的子目录加进 `-I`；
需要时用显式相对路径（如 `#include "../unicode.h"`）。

### 5. PowerShell 的坑

- **`if (...) { $a \| Where {...} + @(...) }` 不合法** —— 表达式位置不能用数组 `+`，
  报 `A positional parameter cannot be found that accepts argument '+'`。必须写成语句块
- **clang 的 `@参数文件` 里含空格的项必须加引号**，否则
  `--sysroot=C:/Program Files/...` 被按空格拆成多个参数
- **长命令会被超时打断**：链接要十几分钟，内联长命令会被 kill。
  用参数文件 + `Start-Process` 脱离方式更稳

### 6. 必须硬失败

脚本一开始"107/116 成功"看着还行，实际链接报一堆 undefined symbol ——
排查成本远高于一开始就报错。现在任何源文件编不过都 `exit 1`。

---

## 四、给决策用的事实（关于 0.5B 模型的现实）

即便探针跑通，**"逐键自动补全"在 0.5B 模型上仍然不现实**：

| 场景 | 单次推理延迟（估计） | 能否逐键补全 |
|---|---|---|
| 桌面 CPU | 100–400ms | 勉强 |
| 手机 CPU | 0.5–2s | ❌ |
| 手机 NPU | 50–200ms（需厂商推理框架） | 理论可行 |

**所以现实的产品形态是**：
- 「Markdown 格式自动补全」用**确定性规则**（已实现，零延迟，见 `markdown_edit_assist.dart`）
- 「文字预测」用**异步补全** —— 不阻塞输入，出结果了就显示

这也解释了为什么第一阶段先做确定性规则：它不依赖任何模型，且比模型更准。
