# 鸿蒙构建环境变量。用法：. C:\yan\app\tool\ohos_env.ps1
#
# 用 CPF-Flutter 的 3.27.4-ohos 而非官方仓：后者 master 是 Flutter 3.7.12 / Dart 2.19，
# 编不了用了 records 与模式匹配的代码。详见 docs/harmonyos.md。

$ErrorActionPreference = 'Stop'

# ---- 路径 ----------------------------------------------------------------
$OhosFlutter = 'C:\ohos-flutter-327'                    # gitcode.com/CPF-Flutter/flutter_flutter @ br_3.27.4-ohos-1.0.4
$DevEco      = 'C:\Program Files\Huawei\DevEco Studio'

if (-not (Test-Path (Join-Path $OhosFlutter 'bin\flutter.bat'))) {
    throw "找不到 OHOS 版 Flutter：$OhosFlutter\bin\flutter.bat`n请先 clone：git clone --depth 1 --branch br_3.27.4-ohos-1.0.4 https://gitcode.com/CPF-Flutter/flutter_flutter.git $OhosFlutter"
}
if (-not (Test-Path $DevEco)) { throw "找不到 DevEco Studio：$DevEco" }

# ---- Flutter（OHOS 分支）----
$env:PATH = "$OhosFlutter\bin;$env:PATH"

# 与桌面版的 C:\pub-cache 隔离，避免不同 Dart 版本的包互相污染
$env:PUB_CACHE = 'C:\pub-cache-ohos327'

# OHOS 引擎不在 Google 存储上
$env:FLUTTER_OHOS_STORAGE_BASE_URL = 'https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'

# ---- HarmonyOS SDK 与命令行工具 ----
$env:TOOL_HOME = $DevEco
$env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
$env:OHOS_SDK_HOME   = Join-Path $DevEco 'sdk'
$env:HOS_SDK_HOME    = Join-Path $DevEco 'sdk'
$env:PATH = "$DevEco\tools\ohpm\bin;$env:PATH"
$env:PATH = "$DevEco\tools\hvigor\bin;$env:PATH"
$env:PATH = "$DevEco\tools\node;$env:PATH"

# ---- JDK ------------------------------------------------------------------
# 官方 FAQ 提到过 JDK 相关的 zip64 报错
# 优先用系统 JDK17，否则用 DevEco 自带 JBR
$jdk17 = Get-ChildItem 'C:\Program Files\Java','C:\Program Files\Eclipse Adoptium','C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'jdk-?17|jdk17|temurin-17' } | Select-Object -First 1
if ($jdk17) {
    $env:JAVA_HOME = $jdk17.FullName
} else {
    $env:JAVA_HOME = Join-Path $DevEco 'jbr'
}
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# ---- git（不在 PATH 时 flutter 会闪退）----
$GitCmd = 'C:\Program Files\Git\cmd'
if (Test-Path $GitCmd) { $env:PATH = "$GitCmd;$env:PATH" }

Write-Host "OHOS 构建环境已就绪：" -ForegroundColor Green
Write-Host "  flutter         : $OhosFlutter\bin\flutter.bat  (3.27.4-ohos)"
Write-Host "  PUB_CACHE       : $env:PUB_CACHE"
Write-Host "  引擎源          : $env:FLUTTER_OHOS_STORAGE_BASE_URL"
Write-Host "  DEVECO_SDK_HOME : $env:DEVECO_SDK_HOME"
Write-Host "  JAVA_HOME       : $env:JAVA_HOME"
Write-Host "  ohpm            : $(if (Get-Command ohpm -ErrorAction SilentlyContinue) { '在 PATH' } else { '未找到' })"
Write-Host "  hvigorw         : $(if (Get-Command hvigorw -ErrorAction SilentlyContinue) { '在 PATH' } else { '未找到' })"
