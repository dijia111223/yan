# Package the Windows release into a self-contained zip.
#
# yan_note.exe links VCRUNTIME140.dll / MSVCP140.dll, so a machine without the
# VC++ redistributable would fail to start. The MSVC runtime is redistributable,
# so ship it app-local.

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\yan\app',
    [string]$Version     = '0.1.0',
    [string]$OutDir      = 'C:\yan\dist'
)

$ErrorActionPreference = 'Stop'

$release = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'yan_note.exe'))) {
    throw "Release build not found at $release - run 'flutter build windows --release' first."
}

$name = "yan-$Version-windows-x64"
$stage = Join-Path $OutDir $name
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Host "=== copying build output ==="
Copy-Item (Join-Path $release '*') $stage -Recurse -Force
Write-Host "  -> $stage"

# ---- app-local MSVC runtime -------------------------------------------------
Write-Host "=== locating MSVC runtime DLLs ==="
$crtNames = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$redistRoots = @(
    # 目录名随 VS 版本变化：VS2022 是 Microsoft.VC143.CRT，VS2026 是 Microsoft.VC145.CRT。
    # 用通配符同时匹配两代，避免绑死版本。
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT",
    "${env:ProgramFiles}\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC14*.CRT"
)
$found = @{}
foreach ($pattern in $redistRoots) {
    foreach ($dir in (Get-ChildItem $pattern -Directory -ErrorAction SilentlyContinue)) {
        foreach ($dll in $crtNames) {
            if ($found.ContainsKey($dll)) { continue }
            $candidate = Join-Path $dir.FullName $dll
            if (Test-Path $candidate) { $found[$dll] = $candidate }
        }
    }
}
# 兜底：只装了运行库本体、没有 Redist 目录的机器，从 System32 取
foreach ($dll in $crtNames) {
    if ($found.ContainsKey($dll)) { continue }
    $sys = Join-Path $env:SystemRoot "System32\$dll"
    if (Test-Path $sys) { $found[$dll] = $sys }
}

$copiedCrt = 0
foreach ($dll in $crtNames) {
    if ($found.ContainsKey($dll)) {
        Copy-Item $found[$dll] $stage -Force
        Write-Host "  + $dll"
        $copiedCrt++
    } else {
        Write-Warning "  ! $dll not found on this machine - the package may need the VC++ Redistributable installed"
    }
}

# ---- third-party notices (charter §3 requires keeping the licence list) -----
Write-Host "=== collecting third-party notices ==="
$notices = Join-Path $stage 'THIRD-PARTY-NOTICES'
New-Item -ItemType Directory -Force -Path $notices | Out-Null

$flutterNotices = Join-Path $stage 'data\flutter_assets\NOTICES.Z'
if (Test-Path $flutterNotices) {
    # NOTICES.Z is a compressed bundle of Flutter/package licences.
    Move-Item $flutterNotices (Join-Path $notices 'Flutter-Engine-and-Packages.NOTICES.Z') -Force
    Write-Host "  + Flutter 引擎与依赖的许可证清单"
}

if (Test-Path (Join-Path $ProjectRoot 'pubspec.lock')) {
    Copy-Item (Join-Path $ProjectRoot 'pubspec.lock') $notices -Force
    Write-Host "  + pubspec.lock（依赖版本，便于核对许可证）"
}

$rootLicense = 'C:\yan\LICENSE'
if (Test-Path $rootLicense) {
    Copy-Item $rootLicense $stage -Force
    Write-Host "  + LICENSE (MIT)"
}

# ---- README for end users ---------------------------------------------------
$readme = @"
砚（Yan）$Version · Windows x64 免安装版
=============================================

运行方式
--------
双击 yan_note.exe 即可，无需安装。

第一次使用
----------
1. 启动后点「打开文件夹作为库」（或按 Ctrl+O），选中你存放 Markdown 的文件夹；
2. 想先看看效果，可以打开 data\flutter_assets\assets\sample 目录作为库
   （那里是内置示例笔记）。

也可以从命令行直接打开：

    yan_note.exe --library "D:\我的笔记"
    yan_note.exe --library "D:\我的笔记" --open "D:\我的笔记\某篇.md"
    yan_note.exe "D:\我的笔记\某篇.md"

快捷键
------
Ctrl+O  打开文件夹作为库      Ctrl+F  全文搜索
Ctrl+N  新建笔记              Ctrl+W  关闭当前标签
Ctrl+S  保存                  Ctrl+B  显示/隐藏文件树
Ctrl+P  显示/隐藏预览         Ctrl+E  frontmatter 面板

关于你的数据
------------
本程序是**纯文件**编辑器：笔记就是磁盘上的 .md 文件，
没有私有数据库、不锁定格式。卸载方式就是删掉这个文件夹——你的笔记不受影响。

同步方案：把笔记文件夹放进 Git 仓库即可（v1 用 Git 顶，WebDAV / 局域网在 v2）。

系统要求
--------
Windows 10 1809 或更高（x64）。
本包已附带 MSVC 运行库（msvcp140.dll / vcruntime140.dll），
正常情况无需另行安装 Visual C++ Redistributable。

许可
----
MIT。第三方依赖的许可证清单见 THIRD-PARTY-NOTICES 目录。

已知限制
--------
- 鸿蒙与安卓端尚未适配（roadmap 中，见仓库 README）
- 行尾统一为 LF；CRLF 文件会被读为 LF 并在保存时写回 LF
- 文档内锚点链接暂不跳转
- 无外部修改监听：在别的编辑器里改了同一文件，需重新打开该标签才会刷新
"@
[System.IO.File]::WriteAllText((Join-Path $stage '读我先看.txt'), $readme,
    (New-Object System.Text.UTF8Encoding($true)))
Write-Host "  + 读我先看.txt"

# ---- zip -------------------------------------------------------------------
Write-Host "=== creating archive ==="
$zip = Join-Path $OutDir "$name.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "  -> $zip  ($size MB)"

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  staging : $stage"
Write-Host "  archive : $zip"
Write-Host "  crt dlls bundled: $copiedCrt / $($crtNames.Count)"
