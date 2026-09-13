# 让 flutter-hvigor-plugin 容忍缺失的 `ohos` 键。
#
# 官方 Flutter 的 pub get 会重写 .flutter-plugins-dependencies，且不含 ohos 平台，
# 于是 plugins.ohos 变成 undefined，插件里的 ohosPlugins.filter(...) 抛
# TypeError，hvigor 同步失败（Error Code: 00308018）。
#
# 改的是 pub 缓存外的 node_modules，所以重新 ohpm install 后要重跑本脚本
# （build_ohos.ps1 会自动调用）。
#
# 逐行替换而非 -replace：避免 PowerShell 把引号后的 $1x 当变量名。
#
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
if ($changed -eq 0) {
    Write-Host "无需改动。" -ForegroundColor Yellow
} else {
    Write-Host "已修改 $changed 个文件。" -ForegroundColor Green

    # 改完必须重启 hvigor 守护进程。
    # 守护进程把插件代码缓存在内存里（Node 的 require 缓存），文件被改不会让已加载的模块
    # 失效 —— 结果是"补丁明明打上了，DevEco 构建仍然报 00308018 filter 错误"。
    # 实测：worker 于 12:47 启动、补丁于 12:53 写入，13:24 构建仍走旧代码；
    # 杀掉守护进程后同一命令立即恢复正常。
    Write-Host ""
    Write-Host "重启 hvigor 守护进程（否则它会继续用内存里的旧插件）..." -ForegroundColor Yellow
    $stopped = 0
    # 只杀 hvigor 自己的 node 进程，不碰用户其它 node 程序
    foreach ($proc in (Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue)) {
        $cmd = [string]$proc.CommandLine
        $exe = [string]$proc.ExecutablePath
        if ($cmd -match 'hvigor' -or $exe -like '*DevEco Studio*') {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped++
        }
    }
    Write-Host "  已停止 $stopped 个 hvigor 守护进程（下次构建会自动重启并重新读插件）" -ForegroundColor Green
}

Write-Host "提示：重新 ohpm install 或换机器后需重跑本脚本（build_ohos.ps1 会自动调用）。"
