<#
    电脑重启之后跑这个：开蓝牙可发现 -> 装 -> 启动 -> 抓日志。
#>
$ErrorActionPreference = 'Continue'

$DevEco = 'D:\Program Files\Huawei\DevEco Studio'
$Hdc = "$DevEco\sdk\default\openharmony\toolchains\hdc.exe"
$Project = 'D:\BB10\HBK'
$Log = "$Project\run.log"

function Say($t) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t
    Write-Host $line
    Add-Content -Path $Log -Value $line -Encoding UTF8
}

Set-Content -Path $Log -Value "=== 重启后测试 $(Get-Date) ===" -Encoding UTF8

Say '让电脑可以被手机找到'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Project\tools\bt-host.ps1" -Seconds 900 2>&1 |
    ForEach-Object { Say "  $_" }

# 等手机
$device = $null
for ($i = 0; $i -lt 40; $i++) {
    $targets = (& $Hdc list targets 2>&1 | Out-String)
    foreach ($line in ($targets -split "`n")) {
        $t = $line.Trim()
        if ($t -match '^\d+\.\d+\.\d+\.\d+:\d+$') { $device = $t; break }
    }
    if ($device) { break }
    if ($i -eq 0) {
        Say '连手机 192.168.50.22:37793'
        & $Hdc tconn 192.168.50.22:37793 2>&1 | ForEach-Object { Say "  $_" }
    }
    Start-Sleep -Seconds 10
}
if (-not $device) { Say '手机连不上，先用 -Device 指定'; exit 1 }
Say "手机 $device"

Say '编译、签名、安装、启动'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$Project\install.ps1" -Device $device 2>&1 |
    ForEach-Object { Say "  $_" }

Start-Sleep -Seconds 30
Say '抓日志'
$hlog = & $Hdc -t $device shell "hilog -x | grep -E 'HBK:|btm_acl_paging|conn_comp|connection state'" 2>&1 | Out-String
Add-Content -Path $Log -Value $hlog -Encoding UTF8
Say '日志在 run.log'
Write-Host $hlog
