# 临时把 integration_test 加进 pubspec，跑完桌面端集成测试后再还原。
#
# pubspec 里不写 integration_test：鸿蒙 fork 自报 0.0.0-unknown，
# 而它要求 Flutter >= 3.18，会让鸿蒙线 pub 求解失败。
# 跑桌面端集成测试时用本脚本临时加上，跑完自动还原。
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/with_integration_test.ps1
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/with_integration_test.ps1 -Target integration_test\font_check_test.dart

[CmdletBinding()]
param(
    [ValidateSet('test', 'get')]
    [string]$Command = 'test',
    [string]$Target = 'integration_test',
    [string]$ProjectRoot = 'C:\yan\app',
    # 显式指定官方 Flutter：鸿蒙分支也在 PATH 里，靠 PATH 会取错
    [string]$Flutter = 'C:\flutter\bin\flutter.bat',
    [string]$PubCache = 'C:\pub-cache'
)

$ErrorActionPreference = 'Stop'
$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
$backup  = Join-Path $ProjectRoot 'pubspec.yaml.bak-withIT'

if (-not (Test-Path $pubspec)) { throw "找不到 $pubspec" }
if (-not (Test-Path $Flutter)) { throw "找不到官方 Flutter：$Flutter" }

# 用官方 Flutter 的 pub 缓存（与鸿蒙那份隔离）
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

        # pub get 会重建 windows/flutter/ephemeral，清掉插件目录联接。
        # 集成测试要构建 Windows 应用，必须补回来。
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
