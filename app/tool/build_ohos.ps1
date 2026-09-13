# 用鸿蒙版 Flutter 构建 HAP。
#
# 为什么需要这个脚本（而不是直接 flutter build hap）：
#   鸿蒙版 Flutter fork 自报版本号是 `0.0.0-unknown`，而 `flutter_test` /
#   `integration_test` 这两个 SDK 包都要求 Flutter >= 3.18，于是 `pub get` 求解失败。
#   它们只在测试时需要，构建 HAP 并不需要，所以这里临时把它们从 pubspec 里摘掉，
#   构建完成后自动还原。
#
# 用法：
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_ohos.ps1
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_ohos.ps1 -Mode release

[CmdletBinding()]
param(
    [ValidateSet('debug', 'release', 'profile')]
    [string]$Mode = 'debug',
    [string]$ProjectRoot = 'C:\yan\app',
    [string]$TargetPlatform = 'ohos-arm64',
    [string]$OhosFlutter = 'C:\ohos-flutter-327',
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
)

$ErrorActionPreference = 'Continue'
$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
$backup  = Join-Path $ProjectRoot 'pubspec.yaml.bak-ohos'
$log     = 'C:\Windows\Temp\yan_ohos_build.log'

if (-not (Test-Path $pubspec)) { throw "找不到 $pubspec" }
if (-not (Test-Path (Join-Path $OhosFlutter 'bin\flutter.bat'))) { throw "找不到 OHOS Flutter：$OhosFlutter" }

# ---- 环境 -----------------------------------------------------------------
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

# ---- 临时裁剪 pubspec -----------------------------------------------------
Copy-Item $pubspec $backup -Force
Write-Host "=== 已备份 pubspec.yaml ===" -ForegroundColor Cyan

try {
    $text = [System.IO.File]::ReadAllText($pubspec, [System.Text.Encoding]::UTF8)

    # 移除 dev_dependencies 下的 flutter_test / integration_test 两条 SDK 依赖
    $text = $text -replace '(?m)^\s*flutter_test:\s*\r?\n\s*sdk:\s*flutter\s*\r?\n', ''
    $text = $text -replace '(?m)^\s*integration_test:\s*\r?\n\s*sdk:\s*flutter\s*\r?\n', ''

    [System.IO.File]::WriteAllText($pubspec, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "=== 已临时移除 flutter_test / integration_test（仅为构建 HAP）===" -ForegroundColor Yellow

    Push-Location $ProjectRoot
    try {
        # 关键：必须用 **OHOS fork** 跑 pub get。
        # 官方 Flutter 的 pub get 会重写 .flutter-plugins-dependencies 并抹掉 `ohos` 键，
        # 导致 hvigor 插件里 `.plugins.ohos.filter(...)` 读 undefined 而崩（Error 00308018）。
        # 这也是"先跑桌面 Flutter、再开 DevEco"时同步失败的根本原因。
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

    # hvigor 在构建时会跑 `ohpm install`，可能把 node_modules 里的插件还原。
    # 因此在构建后再补一次补丁，保证下次 DevEco 同步 / 直接调 hvigor 也不会崩。
    $hvPatch = Join-Path $ProjectRoot 'tool\patch_hvigor_plugin.ps1'
    if (Test-Path $hvPatch) {
        Write-Host "=== 复核 hvigor 插件容错补丁 ===" -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File $hvPatch -ProjectRoot $ProjectRoot
    }
} finally {
    Copy-Item $backup $pubspec -Force
    Remove-Item $backup -Force -ErrorAction SilentlyContinue
    Write-Host "=== 已还原 pubspec.yaml ===" -ForegroundColor Green
}

# ---- 产物 -----------------------------------------------------------------
Write-Host "=== 查找 HAP 产物 ===" -ForegroundColor Cyan
Get-ChildItem (Join-Path $ProjectRoot 'ohos') -Filter '*.hap' -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}, LastWriteTime |
    Format-Table -AutoSize
