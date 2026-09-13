# 把 ohos/build-profile.json5 里的 SDK 版本对齐到本机实际安装的 SDK。
#
# flutter create 生成的模板写死 "5.0.0(12)"，若本机只装了别的版本（例如 6.1.1 / API 24），
# DevEco 会报 "compileSdkVersion、compatibleSdkVersion 或 targetSdkVersion 的值不正确"。
# targetSdkVersion 在模板里是空字符串，schema 也不接受。
#
# 版本从 <SDK>/default/sdk-pkg.json 读取：platformVersion 与 apiVersion 组成 "6.1.1(24)"，
# 该格式由 hvigor schema 校验：
#   ^((?:[5-9]|[1-9]\d+)\.\d+\.\d+\(\d+\)|4\.(?:[1-9]\d*\.\d+\(\d+\)|0\.(?:...)))$
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File tool/sync_ohos_sdk_version.ps1

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\yan\app',
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio'
)

$ErrorActionPreference = 'Stop'

$sdkRoot = Join-Path $DevEco 'sdk'
if (-not (Test-Path $sdkRoot)) { throw "找不到 HarmonyOS SDK：$sdkRoot" }

# ---- 读取已安装版本 ----
$pkg = Get-ChildItem $sdkRoot -Recurse -Filter 'sdk-pkg.json' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $pkg) { throw "在 $sdkRoot 下找不到 sdk-pkg.json" }

$meta = (Get-Content $pkg.FullName -Raw -Encoding utf8 | ConvertFrom-Json).data
$platform = $meta.platformVersion
$api = $meta.apiVersion
if (-not $platform -or -not $api) { throw "sdk-pkg.json 缺少 platformVersion 或 apiVersion" }

$version = "$platform($api)"
Write-Host "本机 SDK: $version  ($($meta.displayName))" -ForegroundColor Cyan

# ---- 改写 build-profile.json5 ----
$profile = Join-Path $ProjectRoot 'ohos\build-profile.json5'
if (-not (Test-Path $profile)) { throw "找不到 $profile" }

$text = [System.IO.File]::ReadAllText($profile, [System.Text.Encoding]::UTF8)
$before = $text

# 逐个替换已有的键值（保留注释与其余结构，不用 JSON 解析器重排）
$text = $text -replace '("compatibleSdkVersion"\s*:\s*)"[^"]*"', "`$1`"$version`""
$text = $text -replace '("targetSdkVersion"\s*:\s*)"[^"]*"',     "`$1`"$version`""

# targetSdkVersion 缺失时，在 compatibleSdkVersion 之后补一行
if ($text -notmatch '"targetSdkVersion"') {
    $text = $text -replace '("compatibleSdkVersion"\s*:\s*"[^"]*",)', "`$1`r`n        `"targetSdkVersion`": `"$version`","
}

if ($text -eq $before) {
    Write-Host "已是 $version，无需改动。" -ForegroundColor DarkGray
} else {
    [System.IO.File]::WriteAllText($profile, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已把 build-profile.json5 的 SDK 版本对齐到 $version" -ForegroundColor Green
}

# ---- 回读确认 ----
$check = [System.IO.File]::ReadAllText($profile, [System.Text.Encoding]::UTF8)
foreach ($key in @('compatibleSdkVersion', 'targetSdkVersion')) {
    $m = [regex]::Match($check, """$key""\s*:\s*""([^""]*)""")
    if ($m.Success) {
        $ok = $m.Groups[1].Value -eq $version
        Write-Host ("  {0,-22} = {1}  {2}" -f $key, $m.Groups[1].Value, $(if ($ok) { 'OK' } else { '不一致' })) `
            -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    } else {
        Write-Warning "  未找到 $key"
    }
}
