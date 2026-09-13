# 给含中文的 .ps1 补 UTF-8 BOM。
#
# Windows PowerShell 5.1 在无 BOM 时按系统 ANSI 代码页（简体中文为 GBK）读脚本，
# 中文注释与字符串会变成乱码，且**乱码里若恰好含引号就会破坏语法**，
# 报成 "The string is missing the terminator" 这种与真实原因无关的错。
# 编辑器与工具写入经常会丢掉 BOM，所以改完脚本跑一下这个。
#
# 注意：$PSScriptRoot 在 `powershell -File` 下可能为空，会导致只扫到当前目录，
# 用 MyInvocation 兜底。

[CmdletBinding()]
param([string]$Dir)

$ErrorActionPreference = 'Stop'

if (-not $Dir) {
    $Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $Dir) { $Dir = (Get-Location).Path }
}

$enc = New-Object System.Text.UTF8Encoding($true)
$files = @(Get-ChildItem $Dir -Filter '*.ps1' -Recurse -File)
$fixed = 0

foreach ($f in $files) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    if ($hasBom) { continue }

    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($f.FullName, $text, $enc)

    # 回读确认，不凭"写过了"就认为成功
    $b2 = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($b2[0] -eq 0xEF -and $b2[1] -eq 0xBB -and $b2[2] -eq 0xBF) {
        Write-Host "已补 BOM: $($f.Name)" -ForegroundColor Yellow
        $fixed++
    } else {
        Write-Host "补 BOM 失败: $($f.FullName)" -ForegroundColor Red
    }
}

Write-Host "扫描 $Dir：共 $($files.Count) 个脚本，本次补了 $fixed 个" -ForegroundColor Green
