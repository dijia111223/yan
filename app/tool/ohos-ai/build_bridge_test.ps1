# 编译并链接桥接层测试程序（yan_ai + yan_bridge_test）。
#
# 与 rebuild_probe.ps1 的区别：这个链接的是桥接层，不是探针。
# 桥接层是应用真正要用的接口，所以在设备上先把它验通再谈集成。

[CmdletBinding()]
param(
    [string]$ProbeDir = 'C:\ohos-ai-probe',
    [ValidateSet('x86_64', 'aarch64')]
    [string]$Arch = 'x86_64',
    [string]$Ndk = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
)

$ErrorActionPreference = 'Stop'

$llama = Join-Path $ProbeDir 'llama.cpp'
$objDir = Join-Path $ProbeDir "out\$Arch\obj"
if (-not (Test-Path $objDir)) { throw "找不到目标文件目录：$objDir（先跑 build_llama_ohos.ps1）" }

$srcDir = Join-Path $ProbeDir 'bridge'
New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'yan_ai.cpp')        (Join-Path $srcDir 'yan_ai.cpp') -Force
Copy-Item (Join-Path $PSScriptRoot 'yan_ai.h')          (Join-Path $srcDir 'yan_ai.h')   -Force
Copy-Item (Join-Path $PSScriptRoot 'yan_bridge_test.cpp') (Join-Path $srcDir 'yan_bridge_test.cpp') -Force

$includes = @(
    $srcDir,
    "$llama\include",
    "$llama\ggml\include",
    "$llama\src",
    "$llama\common",
    "$llama\ggml\src",
    "$llama\ggml\src\ggml-cpu",
    "$llama\vendor"
) | Where-Object { Test-Path $_ } | ForEach-Object { "-I$_" }

$base = @(
    "--target=$Arch-linux-ohos",
    "--sysroot=$Ndk/sysroot",
    '-std=c++17',
    '-O2',
    '-fPIC',
    '-pthread',
    '-DGGML_USE_CPU=1',
    '-DNDEBUG',
    '-D_GNU_SOURCE',
    '-UGGML_BACKEND_DL'
) + $includes

$clang = Join-Path $Ndk 'llvm\bin\clang++.exe'

function Compile-One([string]$src, [string]$obj) {
    if (Test-Path $obj) { Remove-Item $obj -Force }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $clang
    $psi.Arguments = (@($base) + @('-c', '-o', $obj, $src) |
        ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit(600000) | Out-Null
    if ($p.ExitCode -ne 0) {
        Write-Host "编译失败: $(Split-Path $src -Leaf)" -ForegroundColor Red
        ($se.Result -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host "  已编译 $(Split-Path $src -Leaf)" -ForegroundColor DarkGray
}

Compile-One (Join-Path $srcDir 'yan_ai.cpp')         (Join-Path $objDir 'bridge-yan_ai.o')
Compile-One (Join-Path $srcDir 'yan_bridge_test.cpp') (Join-Path $objDir 'bridge-yan_bridge_test.o')

# ---- 链接 -----------------------------------------------------------------
# 参数文件方式：266+ 个目标文件会超 Windows 命令行长度限制。
$objs = Get-ChildItem $objDir -Filter '*.o' | Select-Object -ExpandProperty FullName
$outExe = Join-Path $ProbeDir "out\yan_bridge_ohos_$Arch"
$rsp = Join-Path $ProbeDir "bridge_link_args_$Arch.rsp"

function ToFwd([string]$p) { $p -replace '\\', '/' }
function Quote-IfNeeded([string]$s) { if ($s -match '\s') { return '"' + $s + '"' }; return $s }

$lines = @(
    "--target=$Arch-linux-ohos",
    (Quote-IfNeeded "--sysroot=$(ToFwd $Ndk)/sysroot"),
    '-O2', '-fPIC', '-pthread',
    '-o', (Quote-IfNeeded (ToFwd $outExe))
)
$lines += ($objs | ForEach-Object { Quote-IfNeeded (ToFwd $_) })
$lines += @('-lstdc++', '-lm')
[System.IO.File]::WriteAllLines($rsp, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "链接 $($objs.Count) 个目标文件..." -ForegroundColor Cyan
$logFile = Join-Path $ProbeDir "out\bridge_link_$Arch.log"
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $clang
$psi.Arguments = "@`"$rsp`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
$p.WaitForExit(3600000) | Out-Null
$all = $so.Result + "`n" + $se.Result
[System.IO.File]::WriteAllText($logFile, $all, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "链接退出码: $($p.ExitCode)"
if ($p.ExitCode -ne 0) {
    ($all -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }
    exit 1
}
if (Test-Path $outExe) {
    $mb = [math]::Round((Get-Item $outExe).Length / 1MB, 1)
    Write-Host "产物: $outExe  ($mb MB)" -ForegroundColor Green
}
