# yan_ai 原生库：把 llama.cpp 与桥接层编成 libyan_ai.so。
#
# 由 hvigor 通过 HAR 的 externalNativeOptions 调用，工具链是 DevEco SDK 自带的
# ohos.toolchain.cmake（不要自造 toolchain：CMake 会在编译器 ABI 探测阶段
# 尝试运行产物，而 OHOS ELF 在 Windows 宿主上跑不起来，直接崩 0xC0000409）。

cmake_minimum_required(VERSION 3.10)
project(yan_ai_library LANGUAGES C CXX)

# 必须显式指定：CMake 不会替你加 -std=c++17，而 llama.cpp 用了
# if constexpr / std::is_same_v，漏了会报一堆 "no template named 'is_same_v'"。
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/vendor/llama.cpp")

if(NOT EXISTS "${LLAMA_SRC}/include/llama.h")
  message(FATAL_ERROR "缺少 llama.cpp 源码：${LLAMA_SRC}")
endif()

# ---- OHOS 移植补丁 --------------------------------------------------------
#
# 缺一不可：
#
# 1. common/common.cpp：`#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)`
#    这几块用了 **glibc 专有**的 pthread_getaffinity_np；OHOS 的 sysroot 只提供
#    sched_setaffinity，编译直接失败。与 Android 同样排除。
#
# 2. ggml/src/ggml-cpu/ggml-cpu.c：affinity 调用被 `#if defined(__gnu_linux__)`
#    包着 —— 而 OHOS 的 clang **会**定义 __gnu_linux__，所以这些块同样会被启用。
#    另有几处在 `#ifdef __ANDROID__` 里（OHOS 不定义该宏，本来就不编译）。
#
# 3. common/jinja/value.cpp 用了 common_parse_utf8_codepoint（声明在
#    common/unicode.h），但它写的是 #include "unicode.h"，而 **src/unicode.h
#    同名且 -I 顺序在前**，命中的是错的那份。补一条显式相对路径 include。
#
# 代价：OHOS 上不做 CPU 亲和性绑定 —— 只影响线程调度优化，不影响推理正确性。
#
# 用文本替换而不是 git apply，因为 git apply 对行尾极敏感（补丁 LF、工作区
# CRLF 就会错位，实测把两行合成一行、把 #include 揉进注释，而报错指向别处）。
# 判断"是否已应用"也不能用 git --reverse --check —— 那是拿**当前工作目录**去比，
# 若源码另有拷贝就会误判。读文件、按标记判断、按字符串替换，行为确定。
function(apply_yan_llama_patch rel marker old_text new_text)
  set(_path "${LLAMA_SRC}/${rel}")
  if(NOT EXISTS "${_path}")
    message(FATAL_ERROR "补丁目标不存在：${_path}")
  endif()

  file(READ "${_path}" _content)
  if(_content MATCHES "${marker}")
    message(STATUS "  补丁已应用: ${rel}")
    return()
  endif()

  string(REPLACE "${old_text}" "${new_text}" _patched "${_content}")
  if(_patched STREQUAL _content)
    message(FATAL_ERROR "补丁未命中（上游可能改过这段）：${rel}")
  endif()

  file(WRITE "${_path}" "${_patched}")
  message(STATUS "  已打补丁: ${rel}")
endfunction()

apply_yan_llama_patch("common/common.cpp"
  "defined\\(__OHOS__\\)"
  "#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)"
  "#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__) && !defined(__OHOS__)")

# 只改包含 affinity 调用的那两处 __gnu_linux__ 守卫。
# 文件里共有 5 处 `#if defined(__gnu_linux__)`，其余三处（syscall.h、NUMA 类型
# 定义、stat 调用）与 affinity 无关，动了只会引入无关差异。
# 所以判据带上紧随其后的函数签名，精确命中目标：
#   L622  -> static cpu_set_t ggml_get_numa_affinity(void)
#   L2172 -> static void set_numa_thread_affinity(int thread_n)
apply_yan_llama_patch("ggml/src/ggml-cpu/ggml-cpu.c"
  "ggml_get_numa_affinity.*__OHOS__"
  "#if defined(__gnu_linux__)\nstatic cpu_set_t ggml_get_numa_affinity(void) {"
  "#if defined(__gnu_linux__) && !defined(__OHOS__)\nstatic cpu_set_t ggml_get_numa_affinity(void) {")

apply_yan_llama_patch("ggml/src/ggml-cpu/ggml-cpu.c"
  "set_numa_thread_affinity.*__OHOS__"
  "#if defined(__gnu_linux__)\nstatic void set_numa_thread_affinity(int thread_n) {"
  "#if defined(__gnu_linux__) && !defined(__OHOS__)\nstatic void set_numa_thread_affinity(int thread_n) {")

# 标记必须是**补丁插入的内容**：先前这里写的是 `unicode\.h"`，而文件里本来就有
# `#include "unicode.h"`，于是每次都误判"已应用"、直接跳过，补丁从未生效 ——
# 表现是编译到 value.cpp 才报 common_parse_utf8_codepoint 未声明。
# 第三处：ggml_thread_apply_affinity 里的 `#else` 分支直接调 pthread_setaffinity_np，
# 而 OHOS 只提供 sched_setaffinity（Android 那支用的就是它），
# 所以把 OHOS 并入 Android 分支。编译期不报错（声明在别处），只在**链接期**
# 报 undefined symbol: pthread_setaffinity_np。
apply_yan_llama_patch("ggml/src/ggml-cpu/ggml-cpu.c"
  "sched_setaffinity.*__OHOS__"
  "#ifdef __ANDROID__\n    err = sched_setaffinity(0, sizeof(cpuset), &cpuset);"
  "#if defined(__ANDROID__) || defined(__OHOS__)\n    err = sched_setaffinity(0, sizeof(cpuset), &cpuset);")

apply_yan_llama_patch("common/jinja/value.cpp"
  "\"\\.\\./unicode\\.h\""
  "#include \"runtime.h\""
  "#include \"../unicode.h\"\n#include \"runtime.h\"")

# ---- CMake 本该生成的文件 -------------------------------------------------
# llama-version.h / ggml-version.h / build-info.cpp 都由 CMake 从 .in 模板生成。
# 这里不引入 llama.cpp 自己的 CMakeLists（它要配置一堆后端），手动生成即可。
file(READ "${LLAMA_SRC}/src/llama-version.h.in" _v)
string(REPLACE "@LLAMA_VERSION@" "0.4.0" _v "${_v}")
string(REPLACE "@LLAMA_BUILD_COMMIT@" "yan-vendored" _v "${_v}")
file(WRITE "${LLAMA_SRC}/src/llama-version.h" "${_v}")

file(READ "${LLAMA_SRC}/ggml/src/ggml-version.h.in" _g)
string(REPLACE "@GGML_VERSION@" "0.23.0" _g "${_g}")
string(REPLACE "@GGML_BUILD_COMMIT@" "yan-vendored" _g "${_g}")
file(WRITE "${LLAMA_SRC}/ggml/src/ggml-version.h" "${_g}")

file(READ "${LLAMA_SRC}/common/build-info.cpp.in" _b)
string(REPLACE "@LLAMA_BUILD_NUMBER@" "0" _b "${_b}")
string(REPLACE "@LLAMA_BUILD_COMMIT@" "yan-vendored" _b "${_b}")
string(REPLACE "@BUILD_COMPILER@" "OHOS clang" _b "${_b}")
string(REPLACE "@BUILD_TARGET@" "ohos" _b "${_b}")
file(WRITE "${LLAMA_SRC}/common/build-info.cpp" "${_b}")

# ---- 源文件清单 -----------------------------------------------------------
#
# 清单必须**扫目录而不是手写文件名**：手写会持续漏掉新增文件，而且漏了只在
# 链接期报缺符号，甚至只在换一个模型架构时才暴露。实测踩过这些：
#   * src/models/ 下有 150+ 个模型架构实现，只扫 src 顶层会全漏
#   * ggml/src 顶层的 gguf.cpp / ggml-backend-dl.cpp / ggml-backend-meta.cpp
#   * vendor/cpp-httplib（common 的 download.cpp / hf-cache.cpp 要用）
file(GLOB _src_top "${LLAMA_SRC}/src/*.cpp")
file(GLOB_RECURSE _src_models "${LLAMA_SRC}/src/models/*.cpp")
file(GLOB_RECURSE _common "${LLAMA_SRC}/common/*.cpp")
file(GLOB _ggml_top "${LLAMA_SRC}/ggml/src/*.c" "${LLAMA_SRC}/ggml/src/*.cpp")
file(GLOB _httplib "${LLAMA_SRC}/vendor/cpp-httplib/*.cpp")

# ggml-cpu：通用部分 + **只取目标架构**的目录。
# spacemit / hexagon / kleidiai 是别的硬件的独立顶层目录，混编必然失败。
file(GLOB_RECURSE _cpu_all
  "${LLAMA_SRC}/ggml/src/ggml-cpu/*.c"
  "${LLAMA_SRC}/ggml/src/ggml-cpu/*.cpp")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
  set(_arch_dir "arm")
else()
  set(_arch_dir "x86")
endif()

set(_cpu_keep "")
foreach(_f ${_cpu_all})
  if(_f MATCHES "/spacemit/|/hexagon/|/kleidiai/")
    continue()
  endif()
  if(_f MATCHES "/arch/")
    if(_f MATCHES "/arch/${_arch_dir}/")
      list(APPEND _cpu_keep "${_f}")
    endif()
  else()
    list(APPEND _cpu_keep "${_f}")
  endif()
endforeach()

set(_sources ${_src_top} ${_src_models} ${_common} ${_ggml_top} ${_cpu_keep} ${_httplib})
list(LENGTH _sources _n)
message(STATUS "llama.cpp 源文件: ${_n} 个（arch=${_arch_dir}）")

add_library(yan_ai SHARED ${_sources} "${CMAKE_CURRENT_SOURCE_DIR}/yan_ai.cpp")

set_target_properties(yan_ai PROPERTIES
  PUBLIC_HEADER yan_ai.h
  OUTPUT_NAME "yan_ai"
)

target_include_directories(yan_ai PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${LLAMA_SRC}/include"
  "${LLAMA_SRC}/ggml/include"
  "${LLAMA_SRC}/src"
  "${LLAMA_SRC}/common"
  "${LLAMA_SRC}/ggml/src"
  "${LLAMA_SRC}/ggml/src/ggml-cpu"
  "${LLAMA_SRC}/vendor"
)

# GGML_BACKEND_DL 必须用 -U 取消定义：`-DGGML_BACKEND_DL=0` 是错的写法 ——
# `#ifdef` 只看有没有定义、不看值，等于没关掉。
target_compile_definitions(yan_ai PRIVATE GGML_USE_CPU=1 GGML_NATIVE=OFF NDEBUG _GNU_SOURCE)
target_compile_options(yan_ai PRIVATE -O2 -fPIC -pthread -UGGML_BACKEND_DL)
target_link_libraries(yan_ai PRIVATE m)

# Dart 侧用 DynamicLibrary.open 加载；yan_ai_* 都是 extern "C"，符号默认可导出。
