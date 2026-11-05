$ErrorActionPreference = "SilentlyContinue"

$mutexName = "Local\PUBGWirelessAndHzGuard_Mutex"
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    exit 0
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class PubgNativeGuard {
    [DllImport("wlanapi.dll")]
    public static extern uint WlanOpenHandle(uint dwClientVersion, IntPtr pReserved, out uint pdwNegotiatedVersion, out IntPtr phClientHandle);

    [DllImport("wlanapi.dll")]
    public static extern uint WlanCloseHandle(IntPtr hClientHandle, IntPtr pReserved);

    [DllImport("wlanapi.dll")]
    public static extern uint WlanEnumInterfaces(IntPtr hClientHandle, IntPtr pReserved, out IntPtr ppInterfaceList);

    [DllImport("wlanapi.dll")]
    public static extern void WlanFreeMemory(IntPtr pMemory);

    [DllImport("wlanapi.dll")]
    public static extern uint WlanSetInterface(IntPtr hClientHandle, ref Guid pInterfaceGuid, uint OpCode, uint dwDataSize, ref int pData, IntPtr pReserved);

    public static void AssertLowLatencyWlan(IntPtr hClient) {
        if (hClient == IntPtr.Zero) return;
        IntPtr pList;
        if (WlanEnumInterfaces(hClient, IntPtr.Zero, out pList) != 0) return;
        try {
            int count = Marshal.ReadInt32(pList, 0);
            for (int i = 0; i < count; i++) {
                IntPtr itemPtr = new IntPtr(pList.ToInt64() + 8 + (i * 532));
                byte[] guidBytes = new byte[16];
                Marshal.Copy(itemPtr, guidBytes, 0, 16);
                Guid g = new Guid(guidBytes);
                int disableBgScan = 0;
                int enableMediaStreaming = 1;
                WlanSetInterface(hClient, ref g, 2, 4, ref disableBgScan, IntPtr.Zero);
                WlanSetInterface(hClient, ref g, 3, 4, ref enableMediaStreaming, IntPtr.Zero);
            }
        } finally {
            WlanFreeMemory(pList);
        }
    }
}
"@

& powercfg.exe /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 | Out-Null
& powercfg.exe /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 | Out-Null
& powercfg.exe /setactive SCHEME_CURRENT | Out-Null

# Windows reverts WlanSetInterface OpCodes 2 and 3 as soon as the calling WlanOpenHandle closes.
$negVer = [uint32]0
$wlanHandle = [IntPtr]::Zero
[void][PubgNativeGuard]::WlanOpenHandle(2, [IntPtr]::Zero, [ref]$negVer, [ref]$wlanHandle)

$pubgMoviesDir = "C:\Program Files (x86)\Steam\steamapps\common\PUBG\TslGame\Content\Movies"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Cloudflare WARP" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "CloudflareWARP" -ErrorAction SilentlyContinue
    foreach ($exeName in @("TslGame.exe", "TslGame_ZK.exe", "TslGame_BE.exe", "ExecPubg.exe")) {
        $ifeoPerfPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exeName\PerfOptions"
        if (-not (Test-Path -LiteralPath $ifeoPerfPath)) {
            New-Item -Path $ifeoPerfPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-ItemProperty -Path $ifeoPerfPath -Name "CpuPriorityClass" -Value 3 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Add-MpPreference -ExclusionPath @(
        "C:\Program Files (x86)\Steam\steamapps\common\PUBG",
        "C:\Users\Admin\AppData\Local\TslGame",
        "C:\Program Files (x86)\Common Files\BattlEye",
        "C:\Program Files\Common Files\PUBG"
    ) -ExclusionProcess @(
        "TslGame.exe",
        "TslGame_ZK.exe",
        "TslGame_BE.exe",
        "ExecPubg.exe",
        "BEService.exe",
        "BEService_x64.exe",
        "zksvc.exe",
        "CoherentUI_Host.exe"
    ) -ErrorAction SilentlyContinue
}

$tick = 0
try {
    while ($true) {
        if (($tick % 3) -eq 0) {
            [PubgNativeGuard]::AssertLowLatencyWlan($wlanHandle)

            $warpGui = [System.Diagnostics.Process]::GetProcessesByName("Cloudflare WARP")
            if ($warpGui.Length -gt 0) {
                $warpSvc = Get-Service -Name "CloudflareWARP" -ErrorAction SilentlyContinue
                if ($null -eq $warpSvc -or $warpSvc.Status -ne "Running") {
                    Stop-Process -Name "Cloudflare WARP" -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if (($tick % 6) -eq 0) {
            if (Test-Path -LiteralPath $pubgMoviesDir) {
                Get-ChildItem -LiteralPath $pubgMoviesDir -Filter "*.mp4" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    Move-Item -LiteralPath $_.FullName -Destination "$($_.FullName).bak" -Force -ErrorAction SilentlyContinue
                }
            }
        }

        foreach ($procName in @("TslGame", "TslGame_ZK", "TslGame_BE", "ExecPubg")) {
            $procs = [System.Diagnostics.Process]::GetProcessesByName($procName)
            foreach ($p in $procs) {
                try {
                    if ($p.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::Normal) {
                        $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
                    }
                } catch {}
            }
        }

        $tick++
        Start-Sleep -Seconds 5
    }
} finally {
    if ($wlanHandle -ne [IntPtr]::Zero) {
        [void][PubgNativeGuard]::WlanCloseHandle($wlanHandle, [IntPtr]::Zero)
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
