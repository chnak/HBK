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

    不给 -Device 的话：先看 hdc 已经连上的设备，没有就扫一遍本机网段找
    开着 hdc 端口（37793）的手机。

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Device 192.168.50.22:37793
#>
[CmdletBinding()]
param(
    [string]$Device,
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

# --- 0. 找到手机 -----------------------------------------------------------

function Find-Device {
    # 已经连上的
    $targets = (& $Hdc list targets 2>&1 | Out-String)
    foreach ($line in ($targets -split "`n")) {
        $t = $line.Trim()
        if ($t -match '^\d+\.\d+\.\d+\.\d+:\d+$' -or $t -match '^\S+:\d+$') {
            return $t
        }
    }
    # 扫本机网段
    $addr = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch 'Loopback|cfw-tap|蓝牙' } |
        Select-Object -First 1)
    if (-not $addr) { return $null }
    $prefix = ($addr.IPAddress -split '\.')[0..2] -join '.'
    Say "在网段 $prefix.0/24 里找手机"
    for ($i = 1; $i -le 254; $i++) {
        $ip = "$prefix.$i"
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $ar = $c.BeginConnect($ip, 37793, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(200)) {
                $c.EndConnect($ar)
                return "$ip`:37793"
            }
        } catch { } finally { $c.Close() }
    }
    return $null
}

if (-not $Device) {
    $Device = Find-Device
    if (-not $Device) {
        throw '找不到手机。用 -Device <ip:port> 指定，或者插上 USB 线并开启 USB 调试。'
    }
    Say "找到手机 $Device"
}

# --- 1. 编译 ---------------------------------------------------------------

Say '编译'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Project\build.ps1"
if ($LASTEXITCODE -ne 0) { throw '编译失败' }

# --- 2. 签名 ---------------------------------------------------------------

Say '签名'
$cert = (Get-ChildItem $Store -Filter 'auto_debug_*.cer.cer' | Select-Object -First 1).FullName
if (-not $cert) { throw "找不到应用证书：$Store\auto_debug_*.cer.cer" }
$profilePath = Join-Path $Store $Profile
if (-not (Test-Path $profilePath)) { throw "找不到 profile：$profilePath" }

& $Java -jar $SignTool sign-app -mode localSign `
    -keyAlias xiaobai -keyPwd xiaobai123 `
    -appCertFile $cert -profileFile $profilePath `
    -inFile $Hap -signAlg SHA256withECDSA `
    -keystoreFile "$Store\xiaobai.p12" -keystorePwd xiaobai123 `
    -outFile $Signed -compatibleVersion '12'
if ($LASTEXITCODE -ne 0) { throw '签名失败' }

# --- 3. 安装 ---------------------------------------------------------------

Say "连接到 $Device"
& $Hdc tconn $Device | Out-Null

Say '安装'
$installOut = (& $Hdc -t $Device install -r $Signed 2>&1 | Out-String)
Write-Host $installOut.Trim()
if ($installOut -notmatch 'install bundle successfully') {
    throw "安装失败：$($installOut.Trim())"
}

# --- 4. 启动 ---------------------------------------------------------------

Say '启动'
& $Hdc -t $Device shell "aa start -a EntryAbility -b $Bundle"

Write-Host ''
Say "完成。日志：hdc -t $Device shell hilog | grep HBK"
