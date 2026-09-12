# Prepare Flutter plugin links on Windows WITHOUT Developer Mode.
#
# Why this exists
# ---------------
# When building an app that has plugins, Flutter links each plugin directory from
# the pub cache into:
#
#     windows/flutter/ephemeral/.plugin_symlinks/
#
# It uses *symbolic links* by default, and creating symbolic links on Windows
# requires Administrator rights or Developer Mode. A *directory junction* needs
# neither. Flutter only checks whether that directory exists; it does not verify
# that the entries are symlinks, so pre-creating junctions lets the build proceed.
#
# When to re-run
# --------------
# - after the first clone
# - after `flutter clean` (it deletes the ephemeral directory)
# - after adding/removing dependencies (the plugin set changes)
#
# Usage
# -----
#     pwsh -File tool/prepare_windows_plugins.ps1
#
# If Developer Mode is already enabled, you do not need this script at all.
#
# NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads .ps1
# files using the ANSI code page, so non-ASCII comments get mangled and can even
# break parsing.

[CmdletBinding()]
param(
    # NOTE: $PSScriptRoot can be empty when this file is invoked via `-File` from
    # cmd.exe, so fall back to the invocation path.
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
