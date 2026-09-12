@echo off
REM Run the end-to-end integration test on the real Windows app and log everything.
REM
REM This also re-creates the plugin junctions, because `flutter pub get` recreates
REM windows/flutter/ephemeral and thereby removes them (see
REM tool/prepare_windows_plugins.ps1 for why junctions are needed at all).
set PUB_CACHE=C:\pub-cache
set FLUTTER_SUPPRESS_ANALYTICS=true
set CI=true
cd /d C:\yan\app

echo === pub get === > C:\Windows\Temp\yan_e2e.log
call C:\flutter\bin\flutter.bat pub get >> C:\Windows\Temp\yan_e2e.log 2>&1

echo === prepare plugin junctions === >> C:\Windows\Temp\yan_e2e.log
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\prepare_windows_plugins.ps1 -ProjectRoot C:\yan\app >> C:\Windows\Temp\yan_e2e.log 2>&1

echo === integration test === >> C:\Windows\Temp\yan_e2e.log
call C:\flutter\bin\flutter.bat test integration_test -d windows --no-pub >> C:\Windows\Temp\yan_e2e.log 2>&1
echo === EXITCODE=%ERRORLEVEL% === >> C:\Windows\Temp\yan_e2e.log
