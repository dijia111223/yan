# 让 flutter_math_fork 能在鸿蒙版 Flutter（3.27.x）下编译。
#
# 背景（本次鸿蒙适配里最硬的生态卡点）
# ------------------------------------
# `flutter_math_fork 0.7.4`（pub 上的最新版）是按**更新的 Flutter** 写的，与鸿蒙分支的
# Flutter 3.27.x 有两类不兼容：
#
#   1. `RenderObjectWithLayoutCallbackMixin` 与 `runLayoutCallback()` 是 **Flutter 3.47**
#      才加入的 API（见 3.47 的 `rendering/object.dart`），3.27 里不存在；
#      该包在 `lib/src/render/layout/layout_builder_baseline.dart` 里用了它。
#   2. 鸿蒙分支给 `TargetPlatform` 枚举**新增了 `ohos` 值**，于是第三方包里所有
#      `switch (platform)` 的穷尽匹配都编译失败 —— 该包共 4 处。
#
# 本脚本把这两类问题就地修掉，是幂等的。
#
# 实现说明（踩过坑，别改回正则）：
# 这里**按下标逐行插入**，不用 `-replace`。之前用正则生成
# `case TargetPlatform.ohos: ...case TargetPlatform.windows:` 时，PowerShell 把
# "`$1case" 解析成未定义变量 `$1case` + 字面量 `case`，插入的行被并进上一行、
# 把文件改坏了。逐行处理能精确保留缩进与行尾。
#
# 用法：
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/patch_math_for_ohos.ps1

[CmdletBinding()]
param(
    [string]$PubCache = 'C:\pub-cache-ohos327',
    [string]$Package  = 'flutter_math_fork-0.7.4'
)

$ErrorActionPreference = 'Stop'

$pkgRoot = Get-ChildItem $PubCache -Recurse -Directory -Filter $Package -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $pkgRoot) { throw "在 $PubCache 下找不到 $Package，请先 flutter pub get" }
Write-Host "包目录: $pkgRoot" -ForegroundColor Cyan

$script:changed = 0

function Save-Lines([string]$path, $lines, [bool]$useCrlf) {
    $nl = if ($useCrlf) { "`r`n" } else { "`n" }
    $text = ($lines -join $nl)
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ---- 1. layout_builder_baseline.dart --------------------------------------
# 去掉 3.27 不存在的 RenderObjectWithLayoutCallbackMixin，改用自带空实现的垫片。
$f1 = Join-Path $pkgRoot 'lib\src\render\layout\layout_builder_baseline.dart'
if (Test-Path $f1) {
    $text = [System.IO.File]::ReadAllText($f1, [System.Text.Encoding]::UTF8)
    if ($text -match '_CompatLayoutCallback') {
        Write-Host "  已是最新: layout_builder_baseline.dart" -ForegroundColor DarkGray
    } else {
        $crlf = $text.Contains("`r`n")
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($l in ($text -split "`r?`n")) { $lines.Add($l) }

        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i].Trim() -eq 'RenderObjectWithLayoutCallbackMixin,') { $lines.RemoveAt($i) }
        }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'RenderObjectWithChildMixin<RenderBox>,') {
                $indent = $lines[$i] -replace '\S.*$', ''
                $lines.Insert($i + 1, "${indent}_CompatLayoutCallback,")
                break
            }
        }
        $lines.Add('')
        $lines.Add('/// 兼容垫片：Flutter 3.27 没有 RenderObjectWithLayoutCallbackMixin。')
        $lines.Add('/// 上游该 mixin 仅用于暴露 runLayoutCallback()，此处提供等价的空实现。')
        $lines.Add('mixin _CompatLayoutCallback {')
        $lines.Add('  void runLayoutCallback() {}')
        $lines.Add('}')

        Save-Lines $f1 $lines $crlf
        Write-Host "  已打补丁: layout_builder_baseline.dart" -ForegroundColor Green
        $script:changed++
    }
} else { Write-Warning "  跳过（不存在）: layout_builder_baseline.dart" }

# ---- 2. 4 处 switch (platform) 补上 ohos ---------------------------------
foreach ($rel in @(
        'lib\src\widgets\selectable.dart',
        'lib\src\render\layout\line_editable.dart',
        'lib\src\widgets\selection\gesture_detector_builder_selectable.dart')) {
    $path = Join-Path $pkgRoot $rel
    if (-not (Test-Path $path)) { Write-Warning "  跳过（不存在）: $rel"; continue }

    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($text -match 'TargetPlatform\.ohos') {
        Write-Host "  已是最新: $rel" -ForegroundColor DarkGray
        continue
    }
    $crlf = $text.Contains("`r`n")
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($text -split "`r?`n")) { $lines.Add($l) }

    $inserted = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq 'case TargetPlatform.windows:') {
            $indent = $lines[$i] -replace '\S.*$', ''
            $lines.Insert($i, "${indent}case TargetPlatform.ohos: // HarmonyOS fork: same branch as windows")
            $i++
            $inserted++
        }
    }
    if ($inserted -gt 0) {
        Save-Lines $path $lines $crlf
        Write-Host "  已打补丁: $rel （插入 $inserted 处）" -ForegroundColor Green
        $script:changed++
    } else {
        Write-Warning "  未找到 case TargetPlatform.windows: -- $rel"
    }
}

Write-Host ""
if ($script:changed -eq 0) {
    Write-Host "无需改动（补丁已应用）。" -ForegroundColor Yellow
} else {
    Write-Host "已修改 $script:changed 个文件。" -ForegroundColor Green
}
Write-Host "提示：换 PUB_CACHE 或 pub cache clean 之后需重新运行本脚本。"
