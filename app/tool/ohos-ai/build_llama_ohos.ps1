# 把 llama.cpp 交叉编译成 OHOS 可执行文件（探针用）。
#
# 为什么不用 CMake：llama.cpp 没有 ohos.toolchain.cmake，自造 toolchain 后
# CMake 会在编译器 ABI 探测阶段崩掉（它要运行产物，而 OHOS ELF 在 Windows 宿主上
# 跑不起来）。直接调 clang 更可控，也更容易复现。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_llama_ohos.ps1
#   powershell ... -File build_llama_ohos.ps1 -Arch aarch64

[CmdletBinding()]
param(
    [string]$LlamaSrc = 'C:\ohos-ai-probe\llama.cpp',
    [ValidateSet('x86_64', 'aarch64')]
    [string]$Arch = 'x86_64',
    [string]$Ndk = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native',
    [string]$OutDir = 'C:\ohos-ai-probe\out',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path "$LlamaSrc\CMakeLists.txt")) { throw "找不到 llama.cpp：$LlamaSrc" }
if (-not (Test-Path "$Ndk\llvm\bin\clang++.exe")) { throw "找不到 OHOS NDK：$Ndk" }

$clang = "$Ndk\llvm\bin\clang++.exe"
$out = Join-Path $OutDir $Arch
if ($Clean -and (Test-Path $out)) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$out\obj" | Out-Null

# ---- 先打移植补丁 ---------------------------------------------------------
# OHOS 定义了 __linux__ 但没有 glibc 的 pthread_*affinity_np，
# 不补的话 common.cpp 直接编不过。详见 patch_llama_for_ohos.ps1。
$patchScript = Join-Path $PSScriptRoot 'patch_llama_for_ohos.ps1'
if (Test-Path $patchScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $patchScript -LlamaSrc $LlamaSrc |
        Where-Object { $_ -match '已打补丁|已是最新|修改' } | ForEach-Object { Write-Host "  $_" }
}

# ---- 生成版本头 -----------------------------------------------------------
# llama-version.h / ggml-version.h 由 CMake 从 .in 模板生成；
# 不走 CMake 就得自己生成，否则 src/llama.cpp 直接因缺头文件编不过。
$commit = (& git -C $LlamaSrc rev-parse --short HEAD 2>$null)
if (-not $commit) { $commit = 'unknown' }
$commit = $commit.Trim()

$versionValues = @{
    '@LLAMA_VERSION@'      = '0.4.0'
    '@LLAMA_BUILD_COMMIT@' = $commit
    '@GGML_VERSION@'       = '0.23.0'
    '@GGML_BUILD_COMMIT@'  = $commit
}
foreach ($pair in @(
        @("$LlamaSrc\src\llama-version.h.in", "$LlamaSrc\src\llama-version.h"),
        @("$LlamaSrc\ggml\src\ggml-version.h.in", "$LlamaSrc\ggml\src\ggml-version.h"))) {
    if (-not (Test-Path $pair[0])) { continue }
    $t = [System.IO.File]::ReadAllText($pair[0], [System.Text.Encoding]::UTF8)
    foreach ($k in $versionValues.Keys) { $t = $t.Replace($k, $versionValues[$k]) }
    [System.IO.File]::WriteAllText($pair[1], $t, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  生成 $(Split-Path $pair[1] -Leaf)" -ForegroundColor DarkGray
}

# common/build-info.cpp 同样由 CMake 从 .in 生成。少了它链接会报
# undefined symbol: llama_print_build_info。
$biIn = "$LlamaSrc\common\build-info.cpp.in"
if (Test-Path $biIn) {
    $t = [System.IO.File]::ReadAllText($biIn, [System.Text.Encoding]::UTF8)
    $t = $t.Replace('@LLAMA_BUILD_NUMBER@', '0')
    $t = $t.Replace('@LLAMA_BUILD_COMMIT@', $commit)
    $t = $t.Replace('@BUILD_COMPILER@', 'OHOS clang 15.0.4')
    $t = $t.Replace('@BUILD_TARGET@', "$Arch-linux-ohos")
    [System.IO.File]::WriteAllText("$LlamaSrc\common\build-info.cpp", $t, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  生成 build-info.cpp" -ForegroundColor DarkGray
}

# ---- 源文件清单 -----------------------------------------------------------
# 只要 CPU 后端：探针的目的是验证"能不能在鸿蒙上跑推理"，
# GPU/NPU 后端涉及驱动与厂商 SDK，是另一件事。
$sources = New-Object System.Collections.Generic.List[string]

Get-ChildItem "$LlamaSrc\src" -Filter '*.cpp' | ForEach-Object { $sources.Add($_.FullName) }
# 必须**递归**：common 下有子目录（common/parsers/ 等），
# 只扫顶层会漏掉 lfm2.cpp / parsers.cpp，链接时报 undefined symbol。
Get-ChildItem "$LlamaSrc\common" -Filter '*.cpp' -Recurse | ForEach-Object { $sources.Add($_.FullName) }
foreach ($f in @('ggml.c', 'ggml-alloc.c', 'ggml-quants.c', 'ggml-backend.cpp', 'ggml-backend-reg.cpp', 'ggml-threading.cpp', 'ggml-opt.cpp')) {
    $p = Join-Path "$LlamaSrc\ggml\src" $f
    if (Test-Path $p) { $sources.Add($p) }
}
# ggml-cpu 里的 CPU 内核。
# 注意：ggml-cpu/arch 下按架构分目录，只该编**目标架构 + 通用部分** ——
# 把 riscv/powerpc/s390 等一起编会有约 10 个必然失败
# （'riscv not enabled in this build'、'auto not allowed in function prototype' 等），
# 它们与 x86_64 / arm64 的构建无关。
$archDir = if ($Arch -eq 'aarch64') { 'arm' } else { 'x86' }
$cpuRoot = "$LlamaSrc\ggml\src\ggml-cpu"
# 只属于其它架构/厂商的顶层目录，直接排除 —— 它们不在 arch/ 下，靠下面的规则拦不住。
# kleidiai 是 ARM 专用矩阵内核（要 kai/ukernels 头 + NEON 且与 soft-float ABI 冲突），
# x86_64 构建必须排除。
$skipDirs = @('spacemit', 'hexagon', 'kleidiai')
Get-ChildItem $cpuRoot -Include '*.c','*.cpp' -Recurse |
    Where-Object {
        $rel = $_.FullName.Substring($cpuRoot.Length)
        $skip = $false
        foreach ($d in $skipDirs) { if ($rel -match "[\\/]$d[\\/]") { $skip = $true } }
        if ($skip) { return $false }
        if ($rel -notmatch '[\\/]arch[\\/]') { return $true }   # 通用代码全要
        return $rel -match "[\\/]arch[\\/]$archDir[\\/]"        # 架构代码只要目标的
    } |
    ForEach-Object { $sources.Add($_.FullName) }

# ---- 编译选项 -------------------------------------------------------------
$includes = @(
    "$LlamaSrc\include",
    "$LlamaSrc\ggml\include",
    "$LlamaSrc\src",
    "$LlamaSrc\common",
    "$LlamaSrc\ggml\src",
    "$LlamaSrc\ggml\src\ggml-cpu",
    "$LlamaSrc\vendor"
) | Where-Object { Test-Path $_ } | ForEach-Object { "-I$_" }

$defines = @(
    '-DGGML_USE_CPU=1',
    '-DGGML_BACKEND_DL=0',
    '-DGGML_NATIVE=OFF',
    '-DNDEBUG',
    '-D_GNU_SOURCE'
)

$common = @(
    "--target=$Arch-linux-ohos",
    "--sysroot=$Ndk/sysroot",
    '-std=c++17',
    '-O2',
    '-fPIC',
    '-pthread'
) + $includes + $defines

Write-Host "=== 目标: $Arch  源文件: $($sources.Count) 个 ===" -ForegroundColor Cyan

# ---- 逐文件编译 -----------------------------------------------------------
$objects = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]
$i = 0
foreach ($s in $sources) {
    $i++
    # 用**相对路径**做唯一键：ggml-cpu 下不同 arch 目录里有同名文件
    # （arm/quants.c 与 x86/quants.c），只用 basename 会让它们互相覆盖。
    $rel = $s.Substring($LlamaSrc.Length).TrimStart('\')
    $key = ($rel -replace '[\\/]', '-') -replace '\.(c|cpp)$', ''
    $obj = Join-Path "$out\obj" "$key.o"
    $objects.Add($obj)

    if ((Test-Path $obj) -and -not $Clean) { continue }

    $isC = $s.EndsWith('.c')
    $compiler = if ($isC) { "$Ndk\llvm\bin\clang.exe" } else { $clang }
    # 注意：PowerShell 不能在 if(...) { ... + @(...) } 这种表达式位置用数组 +，
    # 它会被当成位置参数报 "cannot be found that accepts argument '+'"。必须写成语句块。
    if ($isC) {
        $cflags = @($common | Where-Object { $_ -ne '-std=c++17' }) + @('-std=c11')
    } else {
        $cflags = $common
    }

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $compiler
    $allArgs = @($cflags) + @('-c', '-o', $obj, $s)
    $psi.Arguments = ($allArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $pr = [Diagnostics.Process]::Start($psi)
    $so = $pr.StandardOutput.ReadToEndAsync(); $se = $pr.StandardError.ReadToEndAsync()
    $pr.WaitForExit(600000) | Out-Null
    if ($pr.ExitCode -ne 0) {
        $failed.Add("$name : $(($se.Result -split "`n" | Select-Object -First 2) -join ' / ')")
        Write-Host "  [$i/$($sources.Count)] ✘ $name" -ForegroundColor Red
    } elseif ($i % 10 -eq 0 -or $i -eq $sources.Count) {
        Write-Host "  [$i/$($sources.Count)] ok" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "=== 编译失败 $($failed.Count) 个 ===" -ForegroundColor Red
    $failed | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

$okObjects = $objects | Where-Object { Test-Path $_ }
Write-Host "=== 成功产出 $($okObjects.Count)/$($sources.Count) 个目标文件 ===" -ForegroundColor Cyan

# 硬失败：任何源文件编不过都直接退出。
# 否则会出现"107/116 成功"看着还行、实际链接报一堆 undefined symbol 的情况 ——
# 排查起来比一开始就报错麻烦得多。
if ($failed.Count -gt 0) {
    Write-Host "有 $($failed.Count) 个源文件未编过，后续链接必然失败；请先修掉。" -ForegroundColor Red
    exit 1
}
