# 临时把 integration_test 加进 pubspec，跑完桌面端集成测试后再还原。
#
# 为什么需要这个脚本：
#   pubspec.yaml 里刻意不写 integration_test —— 鸿蒙用的 Flutter fork 自报版本号是
#   `0.0.0-unknown`，而 integration_test 要求 Flutter >= 3.18，它会让鸿蒙那条线的
#   pub 求解直接失败（见 docs/harmonyos.md）。
#   桌面端（官方 Flutter 3.47）想跑集成测试时，用本脚本临时加上、跑完自动还原。
#
# 用法：
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/with_integration_test.ps1
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/with_integration_test.ps1 -Target integration_test\font_check_test.dart

[CmdletBinding()]
param(
    [ValidateSet('test', 'get')]
    [string]$Command = 'test',
    [string]$Target = 'integration_test',
    [string]$ProjectRoot = 'C:\yan\app',
    # 显式指定官方 Flutter，避免依赖当前会话的 PATH（鸿蒙分支也在 PATH 里时会用错）
    [string]$Flutter = 'C:\flutter\bin\flutter.bat',
    [string]$PubCache = 'C:\pub-cache'
)

$ErrorActionPreference = 'Stop'
$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
$backup  = Join-Path $ProjectRoot 'pubspec.yaml.bak-withIT'

if (-not (Test-Path $pubspec)) { throw "找不到 $pubspec" }
if (-not (Test-Path $Flutter)) { throw "找不到官方 Flutter：$Flutter" }

# 桌面端要用官方 Flutter 的 pub 缓存（与鸿蒙那份隔离）
$env:PUB_CACHE = $PubCache
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'

Copy-Item $pubspec $backup -Force
Write-Host "已备份 pubspec.yaml -> $(Split-Path $backup -Leaf)"

try {
    $text = [System.IO.File]::ReadAllText($pubspec, [System.Text.Encoding]::UTF8)
    if ($text -notmatch '(?m)^\s*integration_test:\s*$') {
        $text = $text -replace "(?m)^(dev_dependencies:\s*\r?\n)", "`$1  integration_test:`r`n    sdk: flutter`r`n"
        [System.IO.File]::WriteAllText($pubspec, $text, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "已临时加入 integration_test 依赖" -ForegroundColor Yellow
    }

    Push-Location $ProjectRoot
    try {
        Write-Host "=== $Flutter pub get ===" -ForegroundColor Cyan
        & $Flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "pub get 失败" }

        # pub get 会重建 windows/flutter/ephemeral，从而清掉插件目录联接。
        # 集成测试要构建 Windows 应用，所以必须在这里补回来。
        $prep = Join-Path $ProjectRoot 'tool\prepare_windows_plugins.ps1'
        if (Test-Path $prep) {
            Write-Host "=== 补齐插件目录联接 ===" -ForegroundColor Cyan
            & powershell -NoProfile -ExecutionPolicy Bypass -File $prep -ProjectRoot $ProjectRoot
        }

        if ($Command -eq 'test') {
            Write-Host "=== 集成测试: $Target (真实 Windows 应用) ===" -ForegroundColor Cyan
            & $Flutter test $Target -d windows --no-pub
            Write-Host "=== 集成测试退出码: $LASTEXITCODE ===" -ForegroundColor $(if ($LASTEXITCODE -eq 0) { 'Green' } else { 'Red' })
        }
    } finally {
        Pop-Location
    }
} finally {
    Copy-Item $backup $pubspec -Force
    Remove-Item $backup -Force -ErrorAction SilentlyContinue
    Write-Host "已还原 pubspec.yaml" -ForegroundColor Green
}
