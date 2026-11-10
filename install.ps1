<#
.SYNOPSIS
    编译、签名、安装并启动 HBK 到手机。

.DESCRIPTION
    签名用的是 hap_installer 已经存好的华为云调试证书：
      - 私钥   hap_installer\store\xiaobai.p12（alias xiaobai，密码 xiaobai123）
      - 应用证书 auto_debug_<developerId>.cer.cer
      - profile dev_hackeris_hish*.p7b，里面带着这台手机的 UDID

    ⚠️ profile 是和 **包名** 绑死的：AppScope\app.json5 里的 bundleName 必须和
    profile 里的 bundle-name 一致，否则安装会报 "verify signature failed"。

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Device 192.168.50.22:37793
    .\install.ps1 -Bundle dev.hackeris.hish.desktop -Profile dev_hackeris_hish_desktop.p7b
#>
[CmdletBinding()]
param(
    [string]$Device = '192.168.50.22:37793',
    [string]$Bundle = 'dev.hackeris.hish.desktop',
    [string]$Profile = 'dev_hackeris_hish_desktop.p7b'
)

$ErrorActionPreference = 'Stop'

$DevEco = 'D:\Program Files\Huawei\DevEco Studio'
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path
$Store = "$env:USERPROFILE\Documents\hap_installer\store"
$Hap = "$Project\entry\build\default\outputs\default\entry-default-unsigned.hap"
$Signed = "$Project\entry\build\default\outputs\default\entry-default-signed.hap"
$Java = "$DevEco\jbr\bin\java.exe"
$SignTool = "$DevEco\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar"
$Hdc = "$DevEco\sdk\default\openharmony\toolchains\hdc.exe"

function Say($text) { Write-Host "==> $text" -ForegroundColor Cyan }

# --- 1. 编译 ---------------------------------------------------------------

Say '编译'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Project\build.ps1"
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

# --- 2. 签名 ---------------------------------------------------------------

Say '签名'
$cert = (Get-ChildItem $Store -Filter 'auto_debug_*.cer.cer' | Select-Object -First 1).FullName
if (-not $cert) { throw "找不到应用证书：$Store\auto_debug_*.cer.cer" }
$profile = Join-Path $Store $Profile
if (-not (Test-Path $profile)) { throw "找不到 profile：$profile" }

& $Java -jar $SignTool sign-app -mode localSign `
    -keyAlias xiaobai -keyPwd xiaobai123 `
    -appCertFile $cert -profileFile $profile `
    -inFile $Hap -signAlg SHA256withECDSA `
    -keystoreFile "$Store\xiaobai.p12" -keystorePwd xiaobai123 `
    -outFile $Signed -compatibleVersion '12'
if ($LASTEXITCODE -ne 0) { throw "签名失败" }

# --- 3. 安装 ---------------------------------------------------------------

Say "连接到 $Device"
& $Hdc tconn $Device | Out-Null

Say '安装'
& $Hdc -t $Device install -r $Signed
if ($LASTEXITCODE -ne 0) { throw '安装失败' }

# --- 4. 启动 ---------------------------------------------------------------

Say '启动'
& $Hdc -t $Device shell "aa start -a EntryAbility -b $Bundle"

Write-Host ''
Say "完成。日志：hdc -t $Device shell hilog | grep HBK"
