# yan_ai —— 砚的端侧推理原生库

把 **llama.cpp** 与补全桥接层（`src/yan_ai.cpp`）编成 `libyan_ai.so`（鸿蒙）
或 `yan_ai.dll`（Windows），供应用通过 `dart:ffi` 调用。

## 职责边界

这个插件**只负责把原生库编出来并打包**，不含业务逻辑：

| 在哪 | 做什么 |
|---|---|
| 本插件 | 编译 llama.cpp + 桥接层、随应用打包动态库 |
| 应用 `lib/src/core/ai_native.dart` | FFI 绑定、独立 isolate、取消、参数 |

分开的原因：把推理调用放进独立 isolate、支持跨线程取消，这些涉及 UI 时序，
属于应用逻辑，不该塞进插件。

## 构建怎么发生的

鸿蒙端由 hvigor 驱动：

```
ohos/build-profile.json5
  └─ buildOption.externalNativeOptions.path = "../src/CMakeLists.txt"
       └─ DevEco SDK 自带的 ohos.toolchain.cmake
            └─ libyan_ai.so
```

**不要自造 toolchain**：CMake 在编译器 ABI 探测阶段会尝试**运行**探测产物，
而 OHOS ELF 在 Windows 宿主上跑不起来，直接崩 `0xC0000409`。用 SDK 自带的那份没这个问题。

`pubspec.yaml` 里的 `ffiPlugin: true` 是开关 —— 没有它，`src/CMakeLists.txt`
根本不会被调用，运行时也就找不到 `libyan_ai.so`。

## 单独构建（不经过 hvigor）

调试时直接用 CMake 比整包构建快得多：

```powershell
$sdk = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony'
$cmake = "$sdk\native\build-tools\cmake\bin\cmake.exe"
& $cmake -S src -B build-ohos -G Ninja `
  -DCMAKE_TOOLCHAIN_FILE="$sdk\native\build\cmake\ohos.toolchain.cmake" `
  -DOHOS_ARCH=arm64-v8a `
  -DCMAKE_MAKE_PROGRAM="$sdk\native\build-tools\cmake\bin\ninja.exe" `
  -DCMAKE_BUILD_TYPE=Release
& $cmake --build build-ohos
```

约 265 个源文件，几分钟。产物 `build-ohos/libyan_ai.so`。

## llama.cpp 源码与 OHOS 补丁

`src/vendor/llama.cpp` 是上游快照（commit 见 `UPSTREAM_COMMIT.txt`），**不含 `.git`**。
OHOS 需要的三处改动由 `src/CMakeLists.txt` 在**配置阶段自动完成**
（读文件 → 按标记判断是否已应用 → 字符串替换）。

**不要手工改 vendored 源码** —— 改了之后 CMake 会当成"已应用"而跳过，
两边的修改会悄悄分叉。

### 为什么不用 git apply

它在 Windows 上很脆：补丁是 LF、工作区是 CRLF 时会错位，实测把两行合成一行、
把 `#include` 揉进注释，而报错却指向别处。判断"是否已应用"也不能用
`git --reverse --check` —— 那是拿**当前工作目录**去比，若源码另有拷贝就会误判
（真踩过：CMake 说"已应用"，实际 vendored 源码一行没改）。

### 补丁为什么必要

OHOS 的 clang **会**定义 `__linux__` 与 `__gnu_linux__`，于是 llama.cpp 里
用 glibc 专有 `pthread_*affinity_np` 的代码块被启用，而 OHOS 的 sysroot 只提供
`sched_setaffinity`，编译直接失败。三处改动：

| 文件 | 改什么 |
|---|---|
| `common/common.cpp` | 两处 `__x86_64__ && __linux__` 守卫加 `!defined(__OHOS__)` |
| `ggml/src/ggml-cpu/ggml-cpu.c` | `ggml_get_numa_affinity` / `set_numa_thread_affinity` 两处 `__gnu_linux__` 守卫加 `!defined(__OHOS__)` |
| `common/jinja/value.cpp` | 补 `#include "../unicode.h"` —— 见下 |

第三处是**头文件同名**问题：该文件用了 `common_parse_utf8_codepoint`（声明在
`common/unicode.h`），但它写的是 `#include "unicode.h"`，而 `src/unicode.h`
同名且 `-I` 顺序在前，命中的是错的那份。

**已知取舍**：OHOS 上不做 CPU 亲和性绑定与大小核识别，只影响线程调度优化，
不影响推理正确性。
