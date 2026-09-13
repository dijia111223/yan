# Prepare Flutter plugin links on Windows without Developer Mode.
#
# Flutter links plugins from the pub cache into
# windows/flutter/ephemeral/.plugin_symlinks/ with symbolic links, which need
# Administrator rights or Developer Mode. Junctions need neither, and Flutter only
# checks that the directory exists.
#
# Re-run after: first clone, `flutter clean`, adding/removing dependencies.
#
#     pwsh -File tool/prepare_windows_plugins.ps1
#
# ASCII-only on purpose: Windows PowerShell 5.1 reads .ps1 as ANSI, so non-ASCII
# comments get mangled and can break parsing.

[CmdletBinding()]
param(
    # $PSScriptRoot is empty when invoked via `-File` from cmd.exe.
    [string]$ProjectRoot,
    [string]$PubCache = $(if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' })
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { throw "Cannot determine script path; pass -ProjectRoot explicitly." }
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
}

$depsFile = Join-Path $ProjectRoot '.flutter-plugins-dependencies'
if (-not (Test-Path $depsFile)) {
    Write-Host "Missing .flutter-plugins-dependencies - run 'flutter pub get' first." -ForegroundColor Yellow
    exit 1
}

$linkRoot = Join-Path $ProjectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $linkRoot | Out-Null

$deps = Get-Content $depsFile -Raw | ConvertFrom-Json
$windowsPlugins = $deps.plugins.windows
if (-not $windowsPlugins) {
    Write-Host "No Windows plugins in this project - nothing to do." -ForegroundColor Green
    exit 0
}

$linked = 0
foreach ($plugin in $windowsPlugins) {
    $source = $plugin.path.TrimEnd('\', '/')
    $target = Join-Path $linkRoot $plugin.name

    if (-not (Test-Path (Join-Path $source 'pubspec.yaml'))) {
        Write-Host "Skipping $($plugin.name): source not found ($source)" -ForegroundColor Yellow
        continue
    }

    if (Test-Path $target) {
        # Recreate so it points at the current pub cache version.
        Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "  junction  $($plugin.name)  ->  $source"
    $linked++
}

Write-Host ""
Write-Host "Done: created $linked plugin junction(s)." -ForegroundColor Green
Write-Host "You can now run: flutter run -d windows"
