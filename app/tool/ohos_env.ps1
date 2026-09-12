# 砚（Yan）· 鸿蒙（HarmonyOS NEXT / OpenHarmony）构建环境
#
# 用法（每次新开终端都要先执行一次）：
#     . C:\yan\app\tool\ohos_env.ps1
#
# 为什么单独一个脚本：鸿蒙构建依赖 Flutter 的 OpenHarmony 适配分支，
# 与 Windows 桌面版所用的官方 Flutter 是两套完全独立的 SDK，环境变量也不同。
# source 进当前会话即可，不污染系统级环境变量。
#
# 选型说明（重要，别随便改）：
#   官方仓 gitee.com/openharmony-sig/flutter_flutter 的 master 是 Flutter 3.7.12，
#   自带 Dart 2.19 —— 而砚的代码用了 records 与模式匹配（Dart 3），在 2.19 下无法编译。
#   因此这里用 CPF-Flutter 的 3.27.4-ohos 分支（Flutter 3.27.4），它是目前能看到的最新鸿蒙适配版本。
#
# 详细调研与踩坑见 docs/harmonyos.md。

$ErrorActionPreference = 'Stop'

# ---- 路径 ----------------------------------------------------------------
$OhosFlutter = 'C:\ohos-flutter-327'                    # gitcode.com/CPF-Flutter/flutter_flutter @ br_3.27.4-ohos-1.0.4
$DevEco      = 'C:\Program Files\Huawei\DevEco Studio'  # DevEco Studio（含 SDK 与命令行工具）

if (-not (Test-Path (Join-Path $OhosFlutter 'bin\flutter.bat'))) {
    throw "找不到 OHOS 版 Flutter：$OhosFlutter\bin\flutter.bat`n请先 clone：git clone --depth 1 --branch br_3.27.4-ohos-1.0.4 https://gitcode.com/CPF-Flutter/flutter_flutter.git $OhosFlutter"
}
if (-not (Test-Path $DevEco)) { throw "找不到 DevEco Studio：$DevEco" }

# ---- Flutter（OHOS 分支）-------------------------------------------------
$env:PATH = "$OhosFlutter\bin;$env:PATH"

# 依赖缓存与桌面版（C:\pub-cache）隔离，避免不同 Dart 版本的包互相污染
$env:PUB_CACHE = 'C:\pub-cache-ohos327'

# 引擎产物源：OHOS 分支的引擎不在 Google 存储上，在这个华为 OBS 桶
$env:FLUTTER_OHOS_STORAGE_BASE_URL = 'https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

# 让 fork 不因"上游不是标准 remote"而报错（doctor 的建议做法）
$env:FLUTTER_GIT_URL = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'

# ---- HarmonyOS SDK 与命令行工具 ------------------------------------------
$env:TOOL_HOME = $DevEco
$env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
$env:OHOS_SDK_HOME   = Join-Path $DevEco 'sdk'
$env:HOS_SDK_HOME    = Join-Path $DevEco 'sdk'
$env:PATH = "$DevEco\tools\ohpm\bin;$env:PATH"
$env:PATH = "$DevEco\tools\hvigor\bin;$env:PATH"
$env:PATH = "$DevEco\tools\node;$env:PATH"

# ---- JDK ------------------------------------------------------------------
# DevEco 自带 JBR 是 Java 21；官方 FAQ 提到过 JDK 相关的 zip64 报错，遇到可换 JDK17。
# 这里优先找系统已装的 JDK17，找不到再用 JBR。
$jdk17 = Get-ChildItem 'C:\Program Files\Java','C:\Program Files\Eclipse Adoptium','C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'jdk-?17|jdk17|temurin-17' } | Select-Object -First 1
if ($jdk17) {
    $env:JAVA_HOME = $jdk17.FullName
} else {
    $env:JAVA_HOME = Join-Path $DevEco 'jbr'
}
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# ---- git（不加进 PATH 时 flutter 命令会闪退，见官方 FAQ）-----------------
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
