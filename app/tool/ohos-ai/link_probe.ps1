# 链接 OHOS 探针可执行文件。
#
# 为什么要独立成脚本 + 参数文件：llama.cpp 有 79 个目标文件，命令行会超过
# Windows 的长度限制，且链接本身耗时十几分钟。内联长命令容易被超时打断，
# 参数文件方式更稳，也便于复现。

[CmdletBinding()]
param(
    [string]$ProbeDir = 'C:\ohos-ai-probe',
    [ValidateSet('x86_64', 'aarch64')]
    [string]$Arch = 'x86_64',
    [string]$Ndk = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
)

$ErrorActionPreference = 'Stop'

$objDir = Join-Path $ProbeDir "out\$Arch\obj"
if (-not (Test-Path $objDir)) { throw "找不到目标文件目录：$objDir" }

$objs = Get-ChildItem $objDir -Filter '*.o' | Select-Object -ExpandProperty FullName
if ($objs.Count -eq 0) { throw "$objDir 下没有 .o" }

$outExe = Join-Path $ProbeDir "out\yan_probe_ohos_$Arch"
$std = Join-Path $ProbeDir 'out'

function ToFwd([string]$p) { $p -replace '\\', '/' }

# 参数文件里含空格的项**必须加引号** —— clang 解析 @file 时同样按空格切分，
# 否则 --sysroot=C:/Program Files/... 会被拆成多个参数。
function Quote-IfNeeded([string]$s) {
    if ($s -match '\s') { return '"' + $s + '"' }
    return $s
}

$lines = @(
    "--target=$Arch-linux-ohos",
    (Quote-IfNeeded "--sysroot=$(ToFwd $Ndk)/sysroot"),
    '-O2',
    '-fPIC',
    '-pthread',
    '-o', (Quote-IfNeeded (ToFwd $outExe))
)
$lines += ($objs | ForEach-Object { Quote-IfNeeded (ToFwd $_) })
$lines += @('-lstdc++', '-lm')

$rsp = Join-Path $ProbeDir 'link_args.rsp'
[System.IO.File]::WriteAllLines($rsp, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "参数文件已写入: $rsp ($($lines.Count) 行)" -ForegroundColor Cyan

$clang = Join-Path $Ndk 'llvm\bin\clang++.exe'
$logFile = Join-Path $ProbeDir 'out\link.log'
if (Test-Path $logFile) { Remove-Item $logFile -Force }

Write-Host "开始链接 $($objs.Count) 个目标文件..." -ForegroundColor Cyan
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $clang
$psi.Arguments = "@`"$rsp`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$so = $p.StandardOutput.ReadToEndAsync()
$se = $p.StandardError.ReadToEndAsync()
$p.WaitForExit(3600000) | Out-Null

$all = $so.Result + "`n" + $se.Result
[System.IO.File]::WriteAllText($logFile, $all, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "链接退出码: $($p.ExitCode)"
if ($all.Trim()) { Write-Host "--- 输出 ---"; $all -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" } }

if (Test-Path $outExe) {
    $mb = [math]::Round((Get-Item $outExe).Length / 1MB, 1)
    Write-Host "产物: $outExe  ($mb MB)" -ForegroundColor Green
} else {
    Write-Host "未产出可执行文件" -ForegroundColor Red
}
