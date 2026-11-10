<#
.SYNOPSIS
    编译 HBK（鸿蒙版蓝牙键鼠）。

.DESCRIPTION
    用 DevEco Studio 自带的 JDK 和 SDK 调 hvigor，不用装在系统里的 JDK 24 ——
    app_packing_tool.jar 在 JDK 24 上会直接崩（0xC0000005）。

    签名：如果 DevEco 里给这个工程开过「自动签名」，build-profile.json5 里就有
    signingConfigs，hvigor 会自动签。没有的话产出的是未签名的 hap。

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Release
#>
[CmdletBinding()]
param(
    [switch]$Release
)

$ErrorActionPreference = 'Stop'

$DevEco = 'D:\Program Files\Huawei\DevEco Studio'
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path "$DevEco\tools\hvigor\bin\hvigorw.bat")) {
    throw "找不到 DevEco Studio：$DevEco"
}

$BuildMode = if ($Release) { 'release' } else { 'debug' }

$env:DEVECO_SDK_HOME = "$DevEco\sdk"
$env:JAVA_HOME = "$DevEco\jbr"
$env:PATH = "$DevEco\jbr\bin;$env:PATH"

Write-Host "==> 编译 ($BuildMode)" -ForegroundColor Cyan

Push-Location $Project
try {
    & "$DevEco\tools\hvigor\bin\hvigorw.bat" `
        --mode module -p product=default -p "module=entry@default" `
        -p "buildMode=$BuildMode" assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) {
        throw "编译失败（exit $LASTEXITCODE）"
    }
}
finally {
    Pop-Location
}

$Out = "$Project\entry\build\default\outputs\default"
Get-ChildItem $Out -Filter '*.hap' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 3 Name, Length, LastWriteTime

Write-Host ''
Write-Host "产物目录：$Out" -ForegroundColor Green
