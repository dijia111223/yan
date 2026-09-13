# 用鸿蒙版 Flutter 构建 HAP。
#
# 构建期间临时从 pubspec 摘掉 flutter_test / integration_test：鸿蒙 fork 自报版本号是
# 0.0.0-unknown，而这两个 SDK 包要求 Flutter >= 3.18，会让 pub 求解失败。
# 构建后自动还原。
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_ohos.ps1
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_ohos.ps1 -Mode release

[CmdletBinding()]
param(
    [ValidateSet('debug', 'release', 'profile')]
    [string]$Mode = 'debug',
    [string]$ProjectRoot = 'C:\yan\app',
    [string]$TargetPlatform = 'ohos-arm64',
    [string]$OhosFlutter = 'C:\ohos-flutter-327',
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$DesktopFlutter = 'C:\flutter\bin\flutter.bat'
)

$ErrorActionPreference = 'Continue'
$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
$backup  = Join-Path $ProjectRoot 'pubspec.yaml.bak-ohos'
$log     = 'C:\Windows\Temp\yan_ohos_build.log'

if (-not (Test-Path $pubspec)) { throw "找不到 $pubspec" }
if (-not (Test-Path (Join-Path $OhosFlutter 'bin\flutter.bat'))) { throw "找不到 OHOS Flutter：$OhosFlutter" }

# ---- 环境 ----
$env:PUB_CACHE = 'C:\pub-cache-ohos327'
$env:FLUTTER_OHOS_STORAGE_BASE_URL = 'https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'
$env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
$env:OHOS_SDK_HOME   = Join-Path $DevEco 'sdk'
$env:HOS_SDK_HOME    = Join-Path $DevEco 'sdk'
$env:JAVA_HOME       = Join-Path $DevEco 'jbr'
$env:PATH = "$OhosFlutter\bin;$DevEco\tools\ohpm\bin;$DevEco\tools\hvigor\bin;$DevEco\tools\node;$env:JAVA_HOME\bin;C:\Program Files\Git\cmd;$env:PATH"

Write-Host "=== 环境 ===" -ForegroundColor Cyan
Write-Host "  Flutter(OHOS) : $OhosFlutter"
Write-Host "  DEVECO_SDK_HOME: $env:DEVECO_SDK_HOME"
Write-Host "  JAVA_HOME     : $env:JAVA_HOME"

# ---- 临时裁剪 pubspec ----
Copy-Item $pubspec $backup -Force
Write-Host "=== 已备份 pubspec.yaml ===" -ForegroundColor Cyan

try {
    $text = [System.IO.File]::ReadAllText($pubspec, [System.Text.Encoding]::UTF8)

    $text = $text -replace '(?m)^\s*flutter_test:\s*\r?\n\s*sdk:\s*flutter\s*\r?\n', ''
    $text = $text -replace '(?m)^\s*integration_test:\s*\r?\n\s*sdk:\s*flutter\s*\r?\n', ''

    [System.IO.File]::WriteAllText($pubspec, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "=== 已临时移除 flutter_test / integration_test（仅为构建 HAP）===" -ForegroundColor Yellow

    Push-Location $ProjectRoot
    try {
        # 必须用 OHOS fork 跑 pub get。
        # 官方 Flutter 的 pub get 会抹掉 .flutter-plugins-dependencies 里的 ohos 键，
        # 导致 hvigor 插件读 undefined 崩掉（Error 00308018）。
        Write-Host "=== flutter pub get（OHOS fork，保证 ohos 键存在）===" -ForegroundColor Cyan
        & "$OhosFlutter\bin\flutter.bat" pub get 2>&1 | Tee-Object -FilePath $log

        Write-Host "=== flutter build hap --$Mode --target-platform $TargetPlatform ===" -ForegroundColor Cyan
        & "$OhosFlutter\bin\flutter.bat" build hap "--$Mode" --target-platform $TargetPlatform 2>&1 |
            Tee-Object -FilePath $log -Append
        $code = $LASTEXITCODE
        Write-Host "=== build hap 退出码: $code ===" -ForegroundColor $(if ($code -eq 0) { 'Green' } else { 'Red' })
    } finally {
        Pop-Location
    }

    # hvigor 会跑 ohpm install，可能还原 node_modules 里的插件。
    # 构建后补一次，保证下次 DevEco 同步不崩。
    $hvPatch = Join-Path $ProjectRoot 'tool\patch_hvigor_plugin.ps1'
    if (Test-Path $hvPatch) {
        Write-Host "=== 复核 hvigor 插件容错补丁 ===" -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File $hvPatch -ProjectRoot $ProjectRoot
    }
} finally {
    Copy-Item $backup $pubspec -Force
    Remove-Item $backup -Force -ErrorAction SilentlyContinue
    Write-Host "=== 已还原 pubspec.yaml ===" -ForegroundColor Green

    # pubspec 还原了，但 .dart_tool/package_config.json 还是裁剪版生成的（没有 flutter_test），
    # 桌面端测试会因此起不来。这里用官方 Flutter 重建回来。
    if (Test-Path $DesktopFlutter) {
        Write-Host "=== 用官方 Flutter 重建桌面端包配置 ===" -ForegroundColor Cyan
        $env:PUB_CACHE = 'C:\pub-cache'
        Push-Location $ProjectRoot
        try {
            & $DesktopFlutter pub get 2>&1 | Out-Null
            Write-Host "  完成（package_config.json 已恢复 flutter_test）" -ForegroundColor Green
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "找不到官方 Flutter（$DesktopFlutter），桌面端测试前请自行跑一次 flutter pub get"
    }
}

# ---- 产物 ----
Write-Host "=== 查找 HAP 产物 ===" -ForegroundColor Cyan
Get-ChildItem (Join-Path $ProjectRoot 'ohos') -Filter '*.hap' -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}, LastWriteTime |
    Format-Table -AutoSize
