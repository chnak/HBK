<#
.SYNOPSIS
    PC 侧的蓝牙准备：让电脑可以被手机找到，并允许手机连进来。

.DESCRIPTION
    手机是 HID 从机、电脑是 HID 主机，手机要主动去连电脑。Windows 默认
    既不可发现也不接受来电连接，所以手机往往连不上。

    跑一次这个脚本，在手机扫蓝牙的时候就能看到这台电脑（地址也是当前的
    那个，不会是配对列表里的旧地址）。

.EXAMPLE
    .\tools\bt-host.ps1
    .\tools\bt-host.ps1 -Seconds 600
#>
[CmdletBinding()]
param(
    [int]$Seconds = 300
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class BtHost {
    [DllImport("bthprops.cpl", SetLastError = true)]
    public static extern uint BluetoothEnableDiscovery(IntPtr hRadio, uint duration,
        [MarshalAs(UnmanagedType.Bool)] bool fInquiry);
    [DllImport("bthprops.cpl", SetLastError = true)]
    public static extern uint BluetoothEnableIncomingConnections(IntPtr hRadio,
        [MarshalAs(UnmanagedType.Bool)] bool fEnable);
    [DllImport("bthprops.cpl", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool BluetoothIsDiscoverable(IntPtr hRadio);
}
"@

$rc = [BtHost]::BluetoothEnableIncomingConnections([IntPtr]::Zero, $true)
Write-Host "允许来电连接: rc=$rc err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"

$rc = [BtHost]::BluetoothEnableDiscovery([IntPtr]::Zero, $Seconds, $true)
Write-Host "可发现 $Seconds 秒: rc=$rc err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"

Write-Host "当前可发现: $([BtHost]::BluetoothIsDiscoverable([IntPtr]::Zero))"
Write-Host "现在可以在手机的蓝牙设置里看到这台电脑了。"
