# 让 flutter_math_fork 0.7.4 能在 Flutter 3.27.x 下编译。
#
# 两处不兼容：
#   1. 它用了 `RenderObjectWithLayoutCallbackMixin` / `runLayoutCallback()` —— Flutter 3.47
#      才有的 API，3.27 没有。
#   2. 鸿蒙分支给 `TargetPlatform` 新增了 `ohos`，该包 4 处穷尽 `switch (platform)` 编译失败。
#
# 会修补 pub 缓存里的包。**只补鸿蒙缓存**。
#
# 不要顺手把桌面缓存（默认 C:\pub-cache）也补上 —— 这个补丁是鸿蒙专用的：
#   * 删掉 RenderObjectWithLayoutCallbackMixin，而官方 Flutter 3.47 **有**这个 mixin，
#     桌面端会报 "missing implementations for RenderObjectWithLayoutCallbackMixin"
#   * 加了 `TargetPlatform.ohos` 分支，而官方枚举里**没有** ohos，
#     桌面端会报 "Member not found: 'ohos'"
# 实测把桌面缓存也补上之后，桌面测试与构建全部失败。
# 若已误补，用 `dart pub cache repair` 还原（会重装所有包，需几分钟）。
#
# 鸿蒙构建用哪个缓存，由 hvigor 插件里显式设置的 PUB_CACHE 决定
# （见 patch_hvigor_plugin.ps1），所以这里只需管鸿蒙这一份。
#
# 幂等。换 PUB_CACHE 或 pub cache clean 之后要重跑（build_ohos.ps1 会自动调用）。
#
# 逐行插入而非 -replace：PowerShell 会把引号后的 $1case 当成变量名 $1case，
# 导致插入内容并进上一行、把文件改坏。
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/patch_math_for_ohos.ps1

[CmdletBinding()]
param(
    [string[]]$PubCache = @('C:\pub-cache-ohos327'),
    [string]$Package  = 'flutter_math_fork-0.7.4'
)

$ErrorActionPreference = 'Stop'

$script:changed = 0

function Save-Lines([string]$path, $lines, [bool]$useCrlf) {
    $nl = if ($useCrlf) { "`r`n" } else { "`n" }
    $text = ($lines -join $nl)
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Patch-PackageRoot([string]$pkgRoot) {
    Write-Host "包目录: $pkgRoot" -ForegroundColor Cyan

    # ---- 1. layout_builder_baseline.dart ----------------------------------
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

    # ---- 2. 4 处 switch (platform) 补上 ohos ------------------------------
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
}

# ---- 定位所有需要修补的包目录 ---------------------------------------------
$roots = New-Object System.Collections.Generic.List[string]

foreach ($cache in $PubCache) {
    if (-not (Test-Path $cache)) { continue }
    foreach ($d in (Get-ChildItem $cache -Recurse -Directory -Filter $Package -ErrorAction SilentlyContinue)) {
        if (-not $roots.Contains($d.FullName)) { $roots.Add($d.FullName) }
    }
}

if ($roots.Count -eq 0) {
    throw "在所有已知缓存下都找不到 $Package（$($PubCache -join ', ')），请先 flutter pub get"
}

Write-Host "找到 $($roots.Count) 份 $Package" -ForegroundColor Cyan
foreach ($r in $roots) { Patch-PackageRoot $r }

Write-Host ""
if ($script:changed -eq 0) {
    Write-Host "无需改动（补丁已应用）。" -ForegroundColor Yellow
} else {
    Write-Host "已修改 $script:changed 个文件。" -ForegroundColor Green
}
Write-Host "提示：换 PUB_CACHE 或 pub cache clean 之后需重新运行本脚本（build_ohos.ps1 会自动调用）。"
