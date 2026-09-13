# 编译桥接测试程序、推到模拟器、运行并回显输出。
#
# 之所以要串成一条：OHOS ELF 不能在 Windows 宿主运行，每次改动都必须走
# "编译 → 推送 → 设备执行"三步，手工重复容易漏步骤或看错产物。

[CmdletBinding()]
param(
    [string]$ProbeDir = 'C:\ohos-ai-probe',
    [ValidateSet('x86_64', 'aarch64')]
    [string]$Arch = 'x86_64',
    [string]$Device = '127.0.0.1:5555',
    [string]$Model = 'model.gguf',
    [string]$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [int]$TimeoutSec = 1800,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build_bridge_test.ps1') `
        -ProbeDir $ProbeDir -Arch $Arch
    if ($LASTEXITCODE -ne 0) { throw "编译失败" }
}

$exe = Join-Path $ProbeDir "out\yan_bridge_ohos_$Arch"
if (-not (Test-Path $exe)) { throw "找不到产物：$exe" }

Write-Host "推送到设备..." -ForegroundColor Cyan
& $Hdc -t $Device file send $exe '/data/local/tmp/yanprobe/yan_bridge' | Out-Null
& $Hdc -t $Device shell "chmod 755 /data/local/tmp/yanprobe/yan_bridge"

Write-Host "在设备上运行..." -ForegroundColor Cyan
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $Hdc
$psi.Arguments = "-t $Device shell `"cd /data/local/tmp/yanprobe && ./yan_bridge $Model 2>&1`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$o = $p.StandardOutput.ReadToEndAsync()
$e = $p.StandardError.ReadToEndAsync()
$sw = [Diagnostics.Stopwatch]::StartNew()
if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); throw "设备侧超时" }

Write-Host "耗时 $([math]::Round($sw.Elapsed.TotalSeconds,1)) 秒" -ForegroundColor DarkGray
Write-Host "=========== 设备输出 ==========="
$o.Result
if ($e.Result.Trim()) { Write-Host "--- stderr ---"; $e.Result }
