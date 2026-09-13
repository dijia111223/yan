# 修复 flutter-hvigor-plugin 对缺失 `ohos` 键的崩溃（DevEco 同步 / hvigor 构建都会踩到）。
#
# 根因（已实测确认）
# ------------------
# `ohos/node_modules/flutter-hvigor-plugin` 里的 `findFlutterPlugins()` 长这样：
#
#     const ohosPlugins = JSON.parse(fileContent).plugins.ohos
#     const filteredPlugins = ohosPlugins.filter(plugin => plugin.native_build !== false)
#
# 而 **官方 Flutter 的 `pub get` 会重写 `.flutter-plugins-dependencies` 并抹掉 `ohos` 键**
# （实测：跑完官方 pub get 后顶层键只剩 ios/android/macos/linux/windows/web）。
# 此时 `.plugins.ohos` 是 undefined，`.filter` 抛：
#
#     TypeError: Cannot read properties of undefined (reading 'filter')
#     > hvigor ERROR: Error Code: 00308018 Unknown Error
#
# 也就是说：**只要用桌面版 Flutter 跑过一次 `pub get`，鸿蒙工程的 hvigor 同步/构建就会崩**。
# 这是两条工具链共用同一个工程目录必然产生的冲突。
#
# 两层修复
# --------
# 1) 本脚本：把插件改成容错，缺键时按"没有 ohos 插件"处理，而不是整个崩掉。
# 2) `build_ohos.ps1`：构建前一定用 OHOS fork 重新生成该文件，保证 ohos 键存在。
#
# 实现说明：这里用**逐行替换**（不用多行 here-string，也不用带反斜杠引用的 -replace），
# 避免踩"PowerShell 把引号后的 $1x 解析成未定义变量"以及"插入内容被并入上一行"两个坑。
#
# 用法：
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/patch_hvigor_plugin.ps1

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\yan\app'
)

$ErrorActionPreference = 'Stop'

$pluginDir = Join-Path $ProjectRoot 'ohos\node_modules\flutter-hvigor-plugin'
if (-not (Test-Path $pluginDir)) {
    throw "找不到 $pluginDir`n请先在 ohos 目录执行 ohpm install（或跑一次 tool\build_ohos.ps1）"
}

$targets = Get-ChildItem $pluginDir -Recurse -Include '*.ts' -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content $_.FullName -Raw -Encoding utf8) -match 'function findFlutterPlugins' }

if (-not $targets) { throw "在 $pluginDir 下找不到 findFlutterPlugins 实现" }

# 不写 TS 类型标注、不写中文 —— 避免依赖 hvigor 的 TS 转译行为与文件编码。
$oldLine = 'const ohosPlugins = JSON.parse(fileContent).plugins.ohos'
$newLines = @(
    'const parsedPlugins = JSON.parse(fileContent) || {}',
    'const ohosPlugins = (parsedPlugins.plugins && parsedPlugins.plugins.ohos) || []'
)

$changed = 0
foreach ($t in $targets) {
    $text = [System.IO.File]::ReadAllText($t.FullName, [System.Text.Encoding]::UTF8)
    if ($text -notmatch [regex]::Escape($oldLine)) {
        Write-Host "  已是最新: $($t.FullName.Replace($ProjectRoot, ''))" -ForegroundColor DarkGray
        continue
    }

    $crlf = $text.Contains("`r`n")
    $nl = if ($crlf) { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($text -split "`r?`n")) { $lines.Add($l) }

    $hit = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $oldLine) {
            $indent = $lines[$i] -replace '\S.*$', ''
            $lines.RemoveAt($i)
            for ($j = $newLines.Count - 1; $j -ge 0; $j--) {
                $lines.Insert($i, "$indent$($newLines[$j])")
            }
            $hit = $true
            break
        }
    }
    if (-not $hit) { Write-Warning "  未能定位替换点: $($t.FullName)"; continue }

    [System.IO.File]::WriteAllText($t.FullName, ($lines -join $nl), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  已打补丁: $($t.FullName.Replace($ProjectRoot, ''))" -ForegroundColor Green
    $changed++
}

Write-Host ""
if ($changed -eq 0) { Write-Host "无需改动。" -ForegroundColor Yellow }
else { Write-Host "已修改 $changed 个文件。" -ForegroundColor Green }
Write-Host "提示：重新 ohpm install 或换机器后需重跑本脚本（build_ohos.ps1 会自动调用）。"
