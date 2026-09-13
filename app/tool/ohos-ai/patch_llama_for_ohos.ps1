# 把 llama.cpp 移植到 OHOS 所需的源码补丁（探针用，幂等）。
#
# 记录到的真实移植障碍：
#
# 1. OHOS 的 clang 会定义 __linux__（它是 Linux 系），于是 llama.cpp 里
#    `#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)`
#    这些块会被启用，而它们用的是 **glibc 专有** 的
#    `pthread_setaffinity_np` / `pthread_getaffinity_np`。
#    OHOS 的 musl 风格 sysroot 只提供 `sched_setaffinity`，于是编译失败：
#        error: use of undeclared identifier 'pthread_setaffinity_np'
#    处理：给这些守卫加上 !defined(__OHOS__)，与 Android 同样对待。
#    代价：OHOS 上不做 CPU 亲和性绑定与大小核识别 —— 只影响线程调度优化，
#    不影响推理正确性。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File patch_llama_for_ohos.ps1

[CmdletBinding()]
param(
    [string]$LlamaSrc = 'C:\ohos-ai-probe\llama.cpp'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path "$LlamaSrc\common\common.cpp")) { throw "找不到 llama.cpp：$LlamaSrc" }

$changed = 0

function Patch-File([string]$rel, [scriptblock]$transform) {
    $path = Join-Path $LlamaSrc $rel
    if (-not (Test-Path $path)) { Write-Warning "  跳过（不存在）: $rel"; return }
    $orig = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $new = & $transform $orig
    if ($new -eq $orig) {
        Write-Host "  已是最新: $rel" -ForegroundColor DarkGray
        return
    }
    [System.IO.File]::WriteAllText($path, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  已打补丁: $rel" -ForegroundColor Green
    $script:changed++
}

# 1. common.cpp：CPU 亲和性 / 大小核识别（glibc 专有）
Patch-File 'common\common.cpp' {
    param($text)
    $old = '#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)'
    $new = @'
// OHOS: 该平台定义了 __linux__ 但没有 glibc 的 pthread_*affinity_np，
// 与 Android 同样排除（见 patch_llama_for_ohos.ps1）
#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__) && !defined(__OHOS__)
'@
    return $text.Replace($old, $new.TrimEnd("`r","`n"))
}

# 2. ggml-cpu：同类 CPU 特性探测
Patch-File 'ggml\src\ggml-cpu\ggml-cpu.cpp' {
    param($text)
    $old = '#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__)'
    $new = @'
#if defined(__x86_64__) && defined(__linux__) && !defined(__ANDROID__) && !defined(__OHOS__)
'@
    return $text.Replace($old, $new.TrimEnd("`r","`n"))
}

# 3. common/jinja/value.cpp：用了 common_parse_utf8_codepoint，但该函数声明在
#    common/unicode.h 里，而本文件写的是 #include "unicode.h" ——
#    **src/unicode.h 与 common/unicode.h 同名**，-I 顺序下会命中的是前者，
#    于是符号找不到。
#    修法：补一条指向 common/unicode.h 的显式相对路径 include。
#
#    踩坑记录：第一版我补的是 #include "common.h"，而且判重写在 replace 之前，
#    导致重复插入、且并没有解决问题。幂等判断要放在**替换之后**。
Patch-File 'common\jinja\value.cpp' {
    param($text)
    if ($text -match '"\.\./unicode\.h"') { return $text }
    $old = '#include "runtime.h"'
    $new = @'
// common_parse_utf8_codepoint 声明在 common/unicode.h。
// 本文件的 `#include "unicode.h"` 会命中 src/unicode.h（同名，-I 顺序在前），
// 所以这里显式指向 common/unicode.h（见 patch_llama_for_ohos.ps1）。
#include "../unicode.h"
#include "runtime.h"
'@
    $out = $text.Replace($old, $new.TrimEnd("`r","`n"))
    if ($out -eq $text) { Write-Warning "  value.cpp 未找到替换点（#include \"runtime.h\"）" }
    return $out
}

Write-Host ""
if ($changed -eq 0) { Write-Host "无需改动。" -ForegroundColor Yellow }
else { Write-Host "已修改 $changed 个文件。" -ForegroundColor Green }
