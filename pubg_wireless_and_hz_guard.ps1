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

function Disable-PubgStartupMovies {
    param(
        [string]$MoviesDir,
        [string]$EngineIniPath
    )
    if ($MoviesDir -and [System.IO.Directory]::Exists($MoviesDir)) {
        try {
            $mp4Files = [System.IO.Directory]::GetFiles($MoviesDir, "*.mp4", [System.IO.SearchOption]::AllDirectories)
            foreach ($mp4 in $mp4Files) {
                $bak = "$mp4.bak"
                try {
                    if ([System.IO.File]::Exists($bak)) {
                        [System.IO.File]::SetAttributes($bak, [System.IO.FileAttributes]::Normal)
                        [System.IO.File]::Delete($bak)
                    }
                    [System.IO.File]::Move($mp4, $bak)
                } catch {}
            }
        } catch {}
    }
    if ($EngineIniPath -and [System.IO.File]::Exists($EngineIniPath)) {
        try {
            $rawIni = [System.IO.File]::ReadAllText($EngineIniPath, [System.Text.Encoding]::UTF8)
            $needsUpdate = ($rawIni -notmatch 'bWaitForMoviesToComplete=False') -or
                           ($rawIni -notmatch 'bMoviesAreSkippable=True') -or
                           ($rawIni -notmatch '-StartupMovies=')
            if ($needsUpdate) {
                [System.IO.File]::SetAttributes($EngineIniPath, [System.IO.FileAttributes]::Normal)
                if ($rawIni -notmatch '\[/Script/MoviePlayer\.MoviePlayerSettings\]') {
                    $rawIni = $rawIni.TrimEnd() + "`r`n`r`n[/Script/MoviePlayer.MoviePlayerSettings]`r`nbWaitForMoviesToComplete=False`r`nbMoviesAreSkippable=True`r`n-StartupMovies=`r`n"
                } else {
                    if ($rawIni -notmatch 'bWaitForMoviesToComplete=False') {
                        $rawIni = $rawIni -replace '(\[/Script/MoviePlayer\.MoviePlayerSettings\])', "`$1`r`nbWaitForMoviesToComplete=False"
                    }
                    if ($rawIni -notmatch 'bMoviesAreSkippable=True') {
                        $rawIni = $rawIni -replace '(\[/Script/MoviePlayer\.MoviePlayerSettings\])', "`$1`r`nbMoviesAreSkippable=True"
                    }
                    if ($rawIni -notmatch '-StartupMovies=') {
                        $rawIni = $rawIni -replace '(\[/Script/MoviePlayer\.MoviePlayerSettings\])', "`$1`r`n-StartupMovies="
                    }
                }
                [System.IO.File]::WriteAllText($EngineIniPath, $rawIni, (New-Object System.Text.UTF8Encoding($false)))
            }
        } catch {}
    }
}

function Sync-PubgIntegrityCheckHistory {
    param(
        [string]$BinariesWin64Dir,
        [string]$HistoryCsvPath
    )
    if (-not $BinariesWin64Dir -or -not $HistoryCsvPath) { return 0 }
    $hashCsvPath = Join-Path $BinariesWin64Dir "TslGame_Hash.csv"
    if (-not [System.IO.File]::Exists($hashCsvPath)) { return 0 }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $clientVersion = $null
    $existingLines = @()
    if ([System.IO.File]::Exists($HistoryCsvPath)) {
        try {
            $existingLines = [System.IO.File]::ReadAllLines($HistoryCsvPath, [System.Text.Encoding]::UTF8)
            foreach ($el in $existingLines) {
                $parts = $el -split ','
                if ($parts.Count -ge 3 -and $parts[1] -match '^\d+\.\d+\.\d+\.\d+$') {
                    $vCandidate = $parts[1].Trim()
                    if (-not $clientVersion -or ([version]$vCandidate -gt [version]$clientVersion)) {
                        $clientVersion = $vCandidate
                    }
                }
            }
        } catch {}
    }

    $tslExePath = Join-Path $BinariesWin64Dir "TslGame.exe"
    if ([System.IO.File]::Exists($tslExePath)) {
        try {
            $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($tslExePath)
            if ($vi.FileMajorPart -gt 0) {
                $exeVer = "$($vi.FileMajorPart).$($vi.FileMinorPart).$($vi.FileBuildPart).$($vi.FilePrivatePart)"
                if (-not $clientVersion -or ([version]$exeVer -ge [version]$clientVersion)) {
                    $clientVersion = $exeVer
                }
            }
        } catch {}
    }
    if (-not $clientVersion) { return 0 }

    $existingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($el in $existingLines) {
        if ($el) { [void]$existingSet.Add($el.Trim()) }
    }

    $rawHashLines = [System.IO.File]::ReadAllLines($hashCsvPath, [System.Text.Encoding]::UTF8)
    $targetLines = New-Object System.Collections.Generic.List[string]($rawHashLines.Count)
    $needsWrite = $false

    foreach ($hl in $rawHashLines) {
        if ($hl -match '^"([^"]+)"') {
            $relPath = $Matches[1]
            try {
                $fullPath = [System.IO.Path]::GetFullPath((Join-Path $BinariesWin64Dir $relPath))
                if ([System.IO.File]::Exists($fullPath)) {
                    $fi = [System.IO.FileInfo]::new($fullPath)
                    $stamp = $fi.LastWriteTimeUtc.ToString("yyyy.MM.dd-HH.mm.ss", $inv)
                    $normPath = $fullPath.Replace('\', '/')
                    $entry = "$normPath,$clientVersion,$stamp"
                    $targetLines.Add($entry)
                    if (-not $existingSet.Contains($entry)) {
                        $needsWrite = $true
                    }
                }
            } catch {}
        }
    }

    if ($targetLines.Count -gt 0 -and ($needsWrite -or $existingLines.Count -ne $targetLines.Count)) {
        try {
            $histDir = [System.IO.Path]::GetDirectoryName($HistoryCsvPath)
            if ($histDir -and -not [System.IO.Directory]::Exists($histDir)) {
                [System.IO.Directory]::CreateDirectory($histDir) | Out-Null
            }
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            $tmpHist = "$HistoryCsvPath.tmp"
            [System.IO.File]::WriteAllLines($tmpHist, $targetLines.ToArray(), $utf8NoBom)
            [System.IO.File]::Copy($tmpHist, $HistoryCsvPath, $true)
            [System.IO.File]::Delete($tmpHist)
            return $targetLines.Count
        } catch {}
    }
    return 0
}

function Invoke-PubgBinaryPageCacheWarmup {
    param([string]$BinariesWin64Dir)
    if (-not $BinariesWin64Dir -or -not [System.IO.Directory]::Exists($BinariesWin64Dir)) { return }
    $buf = New-Object byte[] 4194304
    $warmTargets = @(
        (Join-Path $BinariesWin64Dir "TslGame.exe"),
        (Join-Path $BinariesWin64Dir "TslGame_ZK.exe"),
        (Join-Path $BinariesWin64Dir "ExecPubg.exe"),
        (Join-Path $BinariesWin64Dir "TslGame_BE.exe"),
        "C:\Program Files (x86)\Common Files\BattlEye\BEService.exe"
    )
    foreach ($fp in $warmTargets) {
        if ([System.IO.File]::Exists($fp)) {
            try {
                $fs = New-Object System.IO.FileStream($fp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 4194304, [System.IO.FileOptions]::SequentialScan)
                try {
                    while ($fs.Read($buf, 0, $buf.Length) -gt 0) {}
                } finally {
                    $fs.Dispose()
                }
            } catch {}
        }
    }
}

& powercfg.exe /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 | Out-Null
& powercfg.exe /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 | Out-Null
& powercfg.exe /setactive SCHEME_CURRENT | Out-Null

# Windows reverts WlanSetInterface OpCodes 2 and 3 as soon as the calling WlanOpenHandle closes.
$negVer = [uint32]0
$wlanHandle = [IntPtr]::Zero
[void][PubgNativeGuard]::WlanOpenHandle(2, [IntPtr]::Zero, [ref]$negVer, [ref]$wlanHandle)

$pubgAcfPath = "C:\Program Files (x86)\Steam\steamapps\appmanifest_578080.acf"
$pubgBinariesWin64Dir = "C:\Program Files (x86)\Steam\steamapps\common\PUBG\TslGame\Binaries\Win64"
$pubgMoviesDir = "C:\Program Files (x86)\Steam\steamapps\common\PUBG\TslGame\Content\Movies"
$engineIniPath = Join-Path $env:LOCALAPPDATA "TslGame\Saved\Config\WindowsNoEditor\Engine.ini"
$integrityCsvPath = Join-Path $env:LOCALAPPDATA "TslGame\Saved\IntegrityCheck\IntegrityCheckHistory.csv"

Disable-PubgStartupMovies -MoviesDir $pubgMoviesDir -EngineIniPath $engineIniPath
[void](Sync-PubgIntegrityCheckHistory -BinariesWin64Dir $pubgBinariesWin64Dir -HistoryCsvPath $integrityCsvPath)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Cloudflare WARP" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "CloudflareWARP" -ErrorAction SilentlyContinue
    foreach ($exeName in @("TslGame.exe", "ExecPubg.exe")) {
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
        "C:\Program Files (x86)\Common Files\BattlEye\BEDaisy.sys",
        "C:\Program Files\Common Files\PUBG",
        "C:\Program Files\Common Files\PUBG\navagio.sys"
    ) -ExclusionProcess @(
        "TslGame.exe",
        "TslGame_ZK.exe",
        "TslGame_BE.exe",
        "ExecPubg.exe",
        "BEService.exe",
        "BEService_pubg.exe",
        "BEService_x64.exe",
        "BEDaisy.sys",
        "zksvc.exe",
        "navagio.sys",
        "CoherentUI_Host.exe"
    ) -ErrorAction SilentlyContinue
}

$lastAcfWriteUtc = if ([System.IO.File]::Exists($pubgAcfPath)) { [System.IO.File]::GetLastWriteTimeUtc($pubgAcfPath) } else { [DateTime]::MinValue }
$wasLaunching = $false

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

        $launchDetected = ([System.Diagnostics.Process]::GetProcessesByName("ExecPubg").Length -gt 0) -or ([System.Diagnostics.Process]::GetProcessesByName("TslGame_ZK").Length -gt 0)
        foreach ($procName in @("ExecPubg", "TslGame")) {
            $procs = [System.Diagnostics.Process]::GetProcessesByName($procName)
            foreach ($p in $procs) {
                try {
                    if ($p.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::Normal) {
                        $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
                    }
                } catch {}
            }
        }

        if ($launchDetected) {
            Disable-PubgStartupMovies -MoviesDir $pubgMoviesDir -EngineIniPath $engineIniPath
            if (-not $wasLaunching) {
                [void](Sync-PubgIntegrityCheckHistory -BinariesWin64Dir $pubgBinariesWin64Dir -HistoryCsvPath $integrityCsvPath)
                Invoke-PubgBinaryPageCacheWarmup -BinariesWin64Dir $pubgBinariesWin64Dir
            }
        }
        $wasLaunching = $launchDetected

        if (($tick % 6) -eq 0) {
            Disable-PubgStartupMovies -MoviesDir $pubgMoviesDir -EngineIniPath $engineIniPath
            if ([System.IO.File]::Exists($pubgAcfPath)) {
                $curWriteUtc = [System.IO.File]::GetLastWriteTimeUtc($pubgAcfPath)
                if ($curWriteUtc -ne $lastAcfWriteUtc) {
                    $lastAcfWriteUtc = $curWriteUtc
                    Disable-PubgStartupMovies -MoviesDir $pubgMoviesDir -EngineIniPath $engineIniPath
                    [void](Sync-PubgIntegrityCheckHistory -BinariesWin64Dir $pubgBinariesWin64Dir -HistoryCsvPath $integrityCsvPath)
                }
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
