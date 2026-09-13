# 只重编探针源文件并重新链接。
#
# 全套 llama.cpp 有 266 个目标文件、链接一次十几分钟；改探针本身时没必要全量重跑，
# 目标文件都还在 out\<Arch>\obj 下，直接复用。

[CmdletBinding()]
param(
    [string]$ProbeDir = 'C:\ohos-ai-probe',
    [ValidateSet('x86_64', 'aarch64')]
    [string]$Arch = 'x86_64',
    [string]$Ndk = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'yan_probe.cpp'
$dst = Join-Path $ProbeDir 'yan_probe.cpp'
Copy-Item $src $dst -Force
Write-Host "已同步探针源码 -> $dst" -ForegroundColor DarkGray

$llama = Join-Path $ProbeDir 'llama.cpp'
$objDir = Join-Path $ProbeDir "out\$Arch\obj"
New-Item -ItemType Directory -Force -Path $objDir | Out-Null
$obj = Join-Path $objDir 'probe-yan_probe.o'
if (Test-Path $obj) { Remove-Item $obj -Force }

$includes = @(
    "$llama\include",
    "$llama\ggml\include",
    "$llama\src",
    "$llama\common",
    "$llama\ggml\src",
    "$llama\ggml\src\ggml-cpu",
    "$llama\vendor"
) | Where-Object { Test-Path $_ } | ForEach-Object { "-I$_" }

$cargs = @(
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
) + $includes + @('-c', '-o', $obj, $dst)

$clang = Join-Path $Ndk 'llvm\bin\clang++.exe'
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $clang
$psi.Arguments = ($cargs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
$p.WaitForExit(600000) | Out-Null

if ($p.ExitCode -ne 0) {
    Write-Host "编译失败：" -ForegroundColor Red
    ($se.Result -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    exit 1
}
if ($se.Result.Trim()) {
    Write-Host "编译告警：" -ForegroundColor Yellow
    ($se.Result -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
}
Write-Host "探针目标文件已重编" -ForegroundColor Green

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'link_probe.ps1') `
    -ProbeDir $ProbeDir -Arch $Arch -Ndk $Ndk
