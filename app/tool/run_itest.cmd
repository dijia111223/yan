@echo off
REM Build/run a single integration test target on the real Windows app.
REM Usage: run_itest.cmd <test-file-or-dir>   e.g. run_itest.cmd integration_test\font_check_test.dart
set PUB_CACHE=C:\pub-cache
set FLUTTER_SUPPRESS_ANALYTICS=true
set CI=true
cd /d C:\yan\app

set TARGET=%1
if "%TARGET%"=="" set TARGET=integration_test

echo === prepare plugin junctions === > C:\Windows\Temp\yan_itest.log
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\prepare_windows_plugins.ps1 -ProjectRoot C:\yan\app >> C:\Windows\Temp\yan_itest.log 2>&1

echo === integration test: %TARGET% === >> C:\Windows\Temp\yan_itest.log
call C:\flutter\bin\flutter.bat test %TARGET% -d windows --no-pub >> C:\Windows\Temp\yan_itest.log 2>&1
echo === EXITCODE=%ERRORLEVEL% === >> C:\Windows\Temp\yan_itest.log
