# Capture real screenshots of the running Yan (砚) Windows app.
#
# Keeps README images honest: every screenshot comes from the actual release
# binary, not from a mock-up.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File capture_shots.ps1

[CmdletBinding()]
param(
    [string]$AppExe   = 'C:\yan\app\build\windows\x64\runner\Release\yan_note.exe',
    [string]$Library  = 'C:\yan-shots-lib',
    [string]$OutDir   = 'C:\yan\docs\images',
    [string]$PrefsDir = "$env:APPDATA\dev.yan\yan_note"
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

# DPI aware so window rect and screen coords match physical pixels
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Dpi {
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
}
'@
try { [Dpi]::SetProcessDpiAwareness(2) | Out-Null } catch { }

function New-SampleLibrary([string]$dst) {
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item 'C:\yan\app\assets\sample' $dst -Recurse
    Get-ChildItem $dst | Select-Object -ExpandProperty Name
}

function Write-ViewPrefs([bool]$dark, [bool]$frontmatter, [bool]$preview) {
    if (-not (Test-Path $PrefsDir)) { New-Item -ItemType Directory -Force -Path $PrefsDir | Out-Null }
    $prefs = @{
        'flutter.yan.libraryPath'     = $Library
        'flutter.yan.recentLibraries' = @($Library)
        'flutter.yan.openTabs'        = @()
        'flutter.yan.activeTab'       = ''
        'flutter.yan.showSidebar'     = $true
        'flutter.yan.showPreview'     = $preview
        'flutter.yan.showFrontmatter' = $frontmatter
        'flutter.yan.darkMode'        = $dark
        'flutter.yan.autosave'        = $true
        'flutter.yan.sort'            = 'nameAsc'
    }
    $json = $prefs | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $PrefsDir 'shared_preferences.json'), $json,
        (New-Object System.Text.UTF8Encoding($false)))
}

function Stop-App {
    Get-Process -Name yan_note -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 700
}

# 库与"要打开的笔记"走命令行参数（--library / --open）：既是真实用户的启动方式，
# 也避免依赖会话恢复逻辑。只有"视图偏好"（深浅色/分栏开关）走偏好文件。
#
# 注意：Start-Process -ArgumentList 收到数组时**不会**给含空格的元素自动加引号，
# 于是 `--open C:\x\CUDA 编程 · 线程层次.md` 会被拆成两个参数传给进程。
# 必须自己引号包裹（见 Quote-Arg）。
function Quote-Arg([string]$value) {
    if ($value -match '[\s"]') { return '"' + ($value -replace '"', '\"') + '"' }
    return $value
}

function Capture([string]$outFile, [string]$noteToOpen, [string]$label,
                 [bool]$dark = $false, [bool]$frontmatter = $false, [bool]$noPreview = $false) {
    Stop-App
    Write-ViewPrefs -dark $dark -frontmatter $frontmatter -preview (-not $noPreview)

    $argList = @('--library', (Quote-Arg $Library))
    if ($noteToOpen) { $argList += @('--open', (Quote-Arg (Join-Path $Library $noteToOpen))) }

    $proc = Start-Process -FilePath $AppExe -ArgumentList $argList -PassThru
    Start-Sleep -Seconds 10
    $proc.Refresh()
    if ($proc.HasExited) { throw "app exited early for '$label'" }
    $h = $proc.MainWindowHandle

    # 先最小化其它窗口，避免遮挡；再最大化并置前
    Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.Id -ne $proc.Id } | ForEach-Object {
        [Win]::ShowWindow($_.MainWindowHandle, 6) | Out-Null   # 6 = minimize
    }
    Start-Sleep -Milliseconds 500
    [Win]::ShowWindow($h, 3) | Out-Null                        # 3 = maximize
    [Win]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Seconds 3

    $r = New-Object Win+RECT
    [Win]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left
    $ht = $r.Bottom - $r.Top
    if ($w -le 0 -or $ht -le 0) { throw "bad window rect for '$label': ${w}x${ht}" }

    # 用 CopyFromScreen 抓屏幕区域，**不要用 PrintWindow**。
    #
    # 实测 PrintWindow + PW_RENDERFULLCONTENT 对 Flutter 窗口会返回同一帧陈旧位图
    # （换了进程、换了内容，抓出来的哈希完全一样），据此生成的 README 截图会骗人。
    # 抓屏幕要求窗口在前台且未被遮挡——所以上面先最小化其它窗口。
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
    $gfx.Dispose()

    $bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("  {0,-28} {1}x{2}  -> {3}" -f $label, $w, $ht, (Split-Path $outFile -Leaf))
}

Write-Host "=== preparing sample library ==="
$files = New-SampleLibrary $Library
$files | ForEach-Object { Write-Host "  $_" }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

Write-Host "=== capturing ==="
Capture (Join-Path $OutDir 'shot-main.png')        'CUDA 编程 · 线程层次与访存.md' '主界面：编辑器 + 预览'
Capture (Join-Path $OutDir 'shot-dark.png')        '高等数学 · 极限与等价无穷小.md' '深色模式' -dark $true
Capture (Join-Path $OutDir 'shot-frontmatter.png') '读书笔记示例.md' 'frontmatter 面板' -frontmatter $true
Capture (Join-Path $OutDir 'shot-nopreview.png')   'CUDA 编程 · 线程层次与访存.md' '关闭预览（纯源码模式）' -noPreview $true

Stop-App
Write-Host "=== done ==="
Get-ChildItem $OutDir -Filter '*.png' | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} |
    Format-Table -AutoSize | Out-String
