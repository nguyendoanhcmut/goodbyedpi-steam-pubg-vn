[CmdletBinding()]
param(
    [switch]$Restore,
    [switch]$DryRun,
    [switch]$ResetShaderCache,
    [switch]$CleanDemos,
    [switch]$DisableHrtf,
    [switch]$DisableMpo,
    [ValidateSet("DX11", "DX11_Enhanced")][string]$GraphicsAPI = "DX11",
    [int]$ResolutionX = 0,
    [int]$ResolutionY = 0,
    [ValidateRange(70, 100)][int]$ScreenScale = 80,
    [ValidateRange(30, 240)][int]$InGameFpsCap = 60,
    [switch]$NoWait,
    [string]$StateFile = "$env:LOCALAPPDATA\TslGame\Saved\pubg_iris_xe_boost_state.json",
    [string]$ConfigDir = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$isDry = $DryRun.IsPresent

. "$PSScriptRoot\iris_xe_lib_native_diag.ps1"
. "$PSScriptRoot\iris_xe_lib_ue4_cache.ps1"
. "$PSScriptRoot\iris_xe_lib_power_os.ps1"

$isAdmin = Test-IsAdministrator
if (-not $isAdmin -and -not $isDry) {
    Write-Host "[!] LOI: Vui long chay script voi quyen Administrator (hoac dung TOI_UU_PUBG_IRIS_XE.cmd)!" -ForegroundColor Red
    exit 1
}

$boostLock = Enter-IrisXeMutex -MutexName "Global\PubgIrisXeBoost_Mutex" -TimeoutMs 60000
try {
    if ($Restore) {
        Write-Host "=========================================================================" -ForegroundColor Cyan
        Write-Host " KHOI PHUC CAU HINH GOC (RESTORE MODE) - DELL LATITUDE 3450 IRIS XE" -ForegroundColor Cyan
        Write-Host "=========================================================================" -ForegroundColor Cyan
        $iniRestore = Restore-PubgIniFiles -TargetConfigDir $ConfigDir -IsDryRun $isDry
        if ($iniRestore.EngineRestored -or $iniRestore.GusRestored) {
            Write-Host "  [+] Da khoi phuc Engine.ini va GameUserSettings.ini tu .irisxe.bak (giu nguyen phim tat)." -ForegroundColor Green
        }
        $saved = Restore-SessionRuntimeState -StateFilePath $StateFile -IsDryRun $isDry
        Write-Host "  [+] Da khoi phuc Power Scheme, CPU Affinity & khoi dong lai cac dich vu nen (sc.exe start)." -ForegroundColor Green
        $allRegRestored = $true
        if ($null -ne $saved -and $null -ne $saved.Registry) {
            foreach ($rSnap in $saved.Registry) {
                if (-not (Restore-RegistryValueSnapshot -Snap $rSnap -IsDryRun $isDry)) {
                    $allRegRestored = $false
                }
            }
            if ($allRegRestored) {
                Write-Host "  [+] Da khoi phuc cac khoa Registry (GameDVR, MMCSS, IFEO, VidPN Scaling, GPU Prefs)." -ForegroundColor Green
            }
        }
        if (-not $isDry -and $isAdmin -and $allRegRestored) {
            foreach ($sfPath in @($StateFile, "$StateFile.bak")) {
                if (Test-Path -LiteralPath $sfPath) {
                    Remove-Item -LiteralPath $sfPath -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  [+] Da xoa file trang thai tam ($StateFile)." -ForegroundColor Green
        }
        Write-Host "=========================================================================" -ForegroundColor Cyan
        if (-not $NoWait) { [void](Read-Host "Nhan Enter de dong cua so...") }
        if (-not $allRegRestored) { exit 1 }
        exit 0
    }

    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host " TOI UU HOA PUBG PC CHO DELL LATITUDE 3450 (i7-1355U + INTEL IRIS XE)" -ForegroundColor Cyan
    if ($isDry) { Write-Host " [CHE DO DRY-RUN: CHI KIEM TRA VA BAO CAO, KHONG GHI THAY DOI]" -ForegroundColor Yellow }
    Write-Host "=========================================================================" -ForegroundColor Cyan

    $hw = Test-SystemHardwareAndMemory
    $topo = $hw.Topology
    Write-Host "`n[1/6] Kiem tra Phan cung, Kenh RAM DDR5 & Kien truc Hybrid CPU:" -ForegroundColor White
    Write-Host ("  - May tinh & CPU  : {0} | {1}" -f $hw.SystemModel, $hw.CpuName)
    Write-Host ("  - Topology CPU    : {0} Physical Cores / {1} Logical Threads (Hybrid={2} | P-Mask=0x{3:X3} | E-Mask=0x{4:X3})" -f $topo.PhysicalCoreCount, $topo.LogicalProcessorCount, $topo.IsHybrid, $topo.PCoreMask, $topo.ECoreMask)
    Write-Host ("  - GPU Tich hop    : {0} (Driver: {1})" -f $hw.GpuName, $hw.GpuDriverVersion)
    Write-Host ("  - Cau hinh RAM    : {0} GB ({1} DIMMs @ {2} MT/s) -> {3} (~{4} GB/s)" -f $hw.TotalCapacityGB, $hw.DimmCount, $hw.ConfiguredMTs, $hw.ChannelMode, $hw.PeakBandwidthGBs)
    if (-not $hw.IsSymmetricDual) { Write-Host "  [!] CANH BAO: He thong khong chay Symmetric Dual-Channel 128-bit! Intel Iris Xe se bi nghen bang thong!" -ForegroundColor Red }

    $vbsInfo = Test-VbsHvciOverhead
    $memHealth = Assert-MemoryAndPagefileHealth -IsAdmin $isAdmin -IsDryRun $isDry
    Write-Host ("  - Memory & Swap   : MemoryCompression={0} ({1} MB) | Pagefile={2} ({3} MB cap / {4} MB dang dung)" -f $memHealth.MemoryCompressionActive, $memHealth.CompressedWorkingSetMB, $memHealth.PagefileEnabled, $memHealth.PagefileAllocatedMB, $memHealth.PagefileCurrentUsageMB)
    if ($memHealth.PagefileAllocatedMB -lt 4096) {
        Write-Host "  [!] CANH BAO: Pagefile < 4096 MB! Shared VRAM Iris Xe (3.5-4.2 GB) + PUBG (7 GB) de bi Out of Video Memory!" -ForegroundColor Red
    }
    if ($vbsInfo.VbsRunning -or $vbsInfo.HvciRunning) {
        Write-Host "  - VBS / HVCI      : DANG BAT (Status=2). Giam ~6-15% 1% low FPS tren iGPU nhung duoc giu nguyen de bao ve BitLocker/PIN." -ForegroundColor Yellow
    } else {
        Write-Host "  - VBS / HVCI      : Da tat (Toi uu bang thong trang nho EPT cho Iris Xe)." -ForegroundColor Green
    }

    $existingState = Read-BoostStateSafely -StateFilePath $StateFile

    $activeLine = (& powercfg.exe /getactivescheme) -join " "
    $activeScheme = if ($activeLine -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $Matches[1] } else { $BalancedSchemeGuid }
    if ($activeScheme -eq $PubgBoostSchemeGuid) {
        $activeScheme = if ($existingState -and $existingState.Power -and $existingState.Power.ActiveScheme -and $existingState.Power.ActiveScheme -ne $PubgBoostSchemeGuid) { [string]$existingState.Power.ActiveScheme } else { $BalancedSchemeGuid }
    }
    $curOverlay = [Guid]::Empty
    try { [void][PubgIrisXeNative]::PowerGetActualOverlayScheme([ref]$curOverlay) } catch {}
    $targetPowerList = Get-TargetPowerSettings -IsHybrid $topo.IsHybrid
    $registrySpecs = Get-RegistrySpecTable -IncludeMpoDisable $DisableMpo.IsPresent -IsAdmin $isAdmin
    $currentBuildId = Get-SteamPubgBuildId

    $existingRegSnaps = if ($null -ne $existingState -and $null -ne $existingState.Registry) { @($existingState.Registry) } else { @() }
    $regSnapshots = Merge-RegistryValueSnapshots -ExistingSnapshots $existingRegSnaps -RegistrySpecs $registrySpecs -IfeoSpecs $IfeoSpecTable

    $powerSnapshots = @()
    $savedSchemeGuid = $activeScheme
    $savedOverlayGuid = $curOverlay.ToString()
    if ($null -ne $existingState -and $null -ne $existingState.Power -and $null -ne $existingState.Power.Settings -and @($existingState.Power.Settings).Count -gt 0) {
        $powerSnapshots = @($existingState.Power.Settings)
        if ($existingState.Power.ActiveScheme -and $existingState.Power.ActiveScheme -ne $PubgBoostSchemeGuid) { $savedSchemeGuid = [string]$existingState.Power.ActiveScheme }
        if ($existingState.Power.OverlayGuid) { $savedOverlayGuid = [string]$existingState.Power.OverlayGuid }
    } else {
        foreach ($pSpec in $targetPowerList) {
            $idx = Get-PowerSettingIndices -SchemeGuid $savedSchemeGuid -SubgroupGuid $pSpec.Subgroup -SettingGuid $pSpec.Guid
            $powerSnapshots += [ordered]@{ Subgroup = $pSpec.Subgroup; Guid = $pSpec.Guid; Name = $pSpec.Name; AC = $idx.AC; DC = $idx.DC }
        }
    }

    $existingPinned = if ($null -ne $existingState -and $null -ne $existingState.PinnedProcesses) { @($existingState.PinnedProcesses) } else { @() }
    $existingSvcs   = if ($null -ne $existingState -and $null -ne $existingState.Services) { @($existingState.Services) } else { @() }
    $preTelemetry   = Get-RunningTelemetryServicesSnapshot -ExistingServices $existingSvcs
    $savedDdmPath   = if ($preTelemetry.DdmPath) { $preTelemetry.DdmPath } elseif ($existingState -and $existingState.DdmPath) { $existingState.DdmPath } else { $null }

    # Write-Before-Mutate: persist the complete pre-mutation baseline snapshot atomically before mutating INI, Power, Registry, Affinity, or Services.
    if (-not $isDry) {
        $preStateObj = [ordered]@{
            Timestamp        = [DateTimeOffset]::UtcNow.ToString("o")
            SystemModel      = $hw.SystemModel
            GpuDriverVersion = $hw.GpuDriverVersion
            PubgBuildId      = $currentBuildId
            Power            = [ordered]@{ ActiveScheme = $savedSchemeGuid; OverlayGuid = $savedOverlayGuid; Settings = $powerSnapshots }
            Registry         = $regSnapshots
            Services         = $preTelemetry.Services
            DdmPath          = $savedDdmPath
            PinnedProcesses  = $existingPinned
        }
        Write-BoostStateAtomically -StateFilePath $StateFile -StateObject $preStateObj -IsDryRun $isDry
    }

    Write-Host "`n[2/6] Toi uu GameUserSettings.ini & Engine.ini (Bao toan 100% Phim tat/Tam ngam):" -ForegroundColor White
    $iniResult = Optimize-PubgIniFiles -TargetConfigDir $ConfigDir -TargetGraphicsAPI $GraphicsAPI -TargetResX $ResolutionX -TargetResY $ResolutionY -TargetScale $ScreenScale -TargetFpsCap $InGameFpsCap -TurnOffHrtf $DisableHrtf.IsPresent -IsDryRun $isDry
    $demosResult = Measure-PubgDemosFolder -RemoveOldDemos $CleanDemos.IsPresent -IsDryRun $isDry
    Write-Host ("  - Render Pipeline : API={0} | Fullscreen {1}x{2} @ ScreenScale {3}% (3D Internal: {4}x{5}) | Sharpen=True" -f $GraphicsAPI, $iniResult.AppliedResolutionX, $iniResult.AppliedResolutionY, $iniResult.AppliedScreenScale, $iniResult.InternalRenderX, $iniResult.InternalRenderY)
    Write-Host ("  - Frame Pacing    : Lobby=Fixed_30 | In-Game=Customizable ({0} FPS) | ClientReplay=False | KillCam=False (L96 & L145)" -f $InGameFpsCap)
    Write-Host ("  - Demos Folder    : {0} tran ({1} files, {2} MB) | Cleaned={3}" -f $demosResult.MatchCount, $demosResult.FileCount, $demosResult.SizeMB, $demosResult.Cleaned)

    Write-Host "`n[3/6] Kich hoat Power Scheme doc lap 'PUBG Iris Xe Boost' (Bao ve Balanced goc):" -ForegroundColor White
    $clonedGuid = Enable-PubgClonedPowerScheme -BaseSchemeGuid $savedSchemeGuid -PowerSpecs $targetPowerList -IsDryRun $isDry
    Write-Host ("  - Power Scheme    : Cloned {0} (Goc={1}) | RunOnce Crash Self-Heal=Active" -f $clonedGuid, $savedSchemeGuid)
    Write-Host ("  - CPU Power Cap   : P-Cores Max=3700 MHz (EPP=20, Unpark=100%) | Class0/E-Cores Hybrid={0}" -f $topo.IsHybrid)
    Write-Host "  - iGPU & Bus      : Overlay=00000000 | PCIe ASPM=Off (AC) | NVMe Idle=5000ms (0ms Latency)"

    Write-Host "`n[4/6] Toi uu Fullscreen iFlip, VidPN Scaling=3, MMCSS, IFEO Priority & Co lap E-Core:" -ForegroundColor White
    $appliedRegCount = 0
    foreach ($rSpec in $registrySpecs) {
        if (Set-RegistryValueSafely -Path $rSpec.Path -Name $rSpec.Name -Value $rSpec.Value -Type $rSpec.Type -IsDryRun $isDry) { $appliedRegCount++ }
    }
    if ($isAdmin) {
        foreach ($ifeo in $IfeoSpecTable) {
            $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$($ifeo.Exe)\PerfOptions"
            [void](Set-RegistryValueSafely -Path $ifeoPath -Name "CpuPriorityClass" -Value $ifeo.CpuPriorityClass -Type "DWord" -IsDryRun $isDry)
            [void](Set-RegistryValueSafely -Path $ifeoPath -Name "IoPriority" -Value $ifeo.IoPriority -Type "DWord" -IsDryRun $isDry)
            [void](Set-RegistryValueSafely -Path $ifeoPath -Name "PagePriority" -Value $ifeo.PagePriority -Type "DWord" -IsDryRun $isDry)
        }
        if (-not $isDry) {
            $pubgInstallDir = Resolve-SteamPubgInstallDir
            $pf86 = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }
            Add-MpPreference -ExclusionPath @($pubgInstallDir, "$env:LOCALAPPDATA\TslGame", (Join-Path $pf86 "Common Files\BattlEye"), (Join-Path $env:ProgramFiles "Common Files\PUBG")) -ExclusionProcess @("TslGame.exe", "TslGame_ZK.exe", "TslGame_BE.exe", "ExecPubg.exe", "BEService.exe", "BEService_x64.exe", "zksvc.exe", "UnrealCEFSubProcess_3071.exe") -ErrorAction SilentlyContinue
        }
    }
    $fthRes = Clear-PubgFaultTolerantHeapShim -DryRun:$DryRun
    $script:pinnedProcs = Set-BackgroundProcessesToECores -PinMask $topo.BackgroundPinMask -ExistingRecords $existingPinned -IsDryRun $isDry
    Write-Host ("  - Registry & IFEO : Da ap dung {0} khoa (FSEBehaviorMode=0 iFlip, Scaling=3, MMCSS=High, TslGame=High, FTH Cleared={1})" -f $appliedRegCount, $fthRes.ClearedCount)
    Write-Host ("  - E-Core & EcoQoS : Da ghim {0} tien trinh nen (SteamWebHelper/Browser/CEF) sang Mask 0x{1:X3} + EcoQoS" -f $script:pinnedProcs.Count, $topo.BackgroundPinMask)

    Write-Host "`n[5/6] Tam dung Dell Telemetry (Bao ve Intel DTT ipfsvc/esifsvc) & Don Shader Cache:" -ForegroundColor White
    $telemetryRes = Suspend-TelemetryServicesSafely -ExistingServices $preTelemetry.Services -IsAdmin $isAdmin -IsDryRun $isDry
    if ($telemetryRes.DdmPath -and -not $savedDdmPath) { $savedDdmPath = $telemetryRes.DdmPath }
    $driverOrBuildChanged = ($null -ne $existingState) -and (($existingState.GpuDriverVersion -and $existingState.GpuDriverVersion -ne $hw.GpuDriverVersion) -or ($existingState.PubgBuildId -and $existingState.PubgBuildId -ne $currentBuildId))
    $forceShaderSweep = $ResetShaderCache.IsPresent -or $driverOrBuildChanged
    $shaderRes = Clear-StaleDxShaderCacheSafely -ForceRebuild $forceShaderSweep -IsDryRun $isDry
    Write-Host ("  - Telemetry Pause : Da tam dung {0} dich vu nen (Giu nguyen ipfsvc/esifsvc Intel Dynamic Tuning)" -f $telemetryRes.Services.Count)
    Write-Host ("  - Shader Cache    : Da don {0} file loi/tam (Bo qua {1} file dang khoa boi DWM | FullSweep={2})" -f $shaderRes.DeletedFiles, $shaderRes.SkippedLocked, $forceShaderSweep)

    Write-Host "`n[6/6] Don dep Working Set, Modified List & Standby List RAM cho Shared VRAM Iris Xe:" -ForegroundColor White
    $ramPurge = Invoke-PreLaunchSharedVramPurge -IsDryRun $isDry
    Write-Host ("  - Physical RAM    : Free+Zeroed truoc={0} MB (Standby={1} MB) -> Sau={2} MB (Standby={3} MB) | Da giai phong +{4} MB" -f $ramPurge.BeforeFreeZeroMB, $ramPurge.BeforeStandbyMB, $ramPurge.AfterFreeZeroMB, $ramPurge.AfterStandbyMB, $ramPurge.FreedMB)

    if (-not $isDry) {
        $postStateObj = [ordered]@{
            Timestamp        = [DateTimeOffset]::UtcNow.ToString("o")
            SystemModel      = $hw.SystemModel
            GpuDriverVersion = $hw.GpuDriverVersion
            PubgBuildId      = $currentBuildId
            Power            = [ordered]@{ ActiveScheme = $savedSchemeGuid; OverlayGuid = $savedOverlayGuid; Settings = $powerSnapshots }
            Registry         = $regSnapshots
            Services         = $telemetryRes.Services
            DdmPath          = $savedDdmPath
            PinnedProcesses  = $script:pinnedProcs
        }
        Write-BoostStateAtomically -StateFilePath $StateFile -StateObject $postStateObj -IsDryRun $isDry
    }

    Write-Host "`n=========================================================================" -ForegroundColor Green
    Write-Host " HOAN TAT TOI UU PUBG CHO DELL LATITUDE 3450 (i7-1355U + IRIS XE)!" -ForegroundColor Green
    Write-Host "  - File luu trang thai Rollback : $StateFile"
    Write-Host "  - Khoi phuc mac dinh bat cu luc nao bang: TOI_UU_PUBG_IRIS_XE.cmd -Restore"
    Write-Host "=========================================================================" -ForegroundColor Green

    function Invoke-SessionAutoRestore {
        if ($null -ne $script:pinnedProcs -and @($script:pinnedProcs).Count -gt 0) {
            Restore-BackgroundProcessesAffinity -PinnedRecords $script:pinnedProcs -IsDryRun $isDry
        }
        $saved = Restore-SessionRuntimeState -StateFilePath $StateFile -IsDryRun $isDry
        $allRegOk = $true
        if ($null -ne $saved -and $null -ne $saved.Registry) {
            foreach ($rSnap in $saved.Registry) {
                if (-not (Restore-RegistryValueSnapshot -Snap $rSnap -IsDryRun $isDry)) { $allRegOk = $false }
            }
        }
        [void](Restore-PubgIniFiles -TargetConfigDir $ConfigDir -IsDryRun $isDry)
        if (-not $isDry -and $isAdmin -and $allRegOk) {
            foreach ($sfPath in @($StateFile, "$StateFile.bak")) {
                if (Test-Path -LiteralPath $sfPath) {
                    Remove-Item -LiteralPath $sfPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        Write-Host "  [+] Session Guard: Da tu dong khoi phuc Power Scheme ($savedSchemeGuid), CPU Affinity, Services, Registry & INI!" -ForegroundColor Green
    }

    function Wait-PubgSessionAndRestore {
        Write-Host "`n[SESSION GUARD] Dang giam sat TslGame.exe & UnrealCEFSubProcess_3071..." -ForegroundColor Cyan
        Write-Host "  -> Hay mo game PUBG! Khi thoat PUBG (hoac nhan Enter / Ctrl+C), Power Scheme & CPU Affinity se tu dong khoi phuc!" -ForegroundColor Yellow
        $timerLocked = $false
        try {
            $selfProc = $null
            try {
                $selfProc = [System.Diagnostics.Process]::GetCurrentProcess()
                [void][PubgIrisXeNative]::SetEcoQoSAndTimerThrottle($selfProc.Handle, [uint32]0x4, [uint32]0)
                [uint32]$curTimerRes = 0
                if ([PubgIrisXeNative]::NtSetTimerResolution(5000, $true, [ref]$curTimerRes) -eq 0) {
                    $timerLocked = $true
                    Write-Host "  [Timer] Da khoa bo dem xung nhip Kernel = $([Math]::Round($curTimerRes / 10000.0, 3)) ms (Chong ngu khi thu nho cua so)" -ForegroundColor Green
                }
            } catch {} finally {
                if ($null -ne $selfProc) { $selfProc.Dispose() }
            }
            $gameSeen = $false
            while ($true) {
                if ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.Key -eq [ConsoleKey]::Enter -or $k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Q) { break }
                }
                $tsl = @([System.Diagnostics.Process]::GetProcessesByName("TslGame"))
                foreach ($tp in $tsl) { $tp.Dispose() }
                if ($tsl.Count -gt 0) {
                    $gameSeen = $true
                    $prevPinCount = if ($null -ne $script:pinnedProcs) { @($script:pinnedProcs).Count } else { 0 }
                    $script:pinnedProcs = Set-BackgroundProcessesToECores -PinMask $topo.BackgroundPinMask -ExistingRecords $script:pinnedProcs -IsDryRun $false
                    if (@($script:pinnedProcs).Count -ne $prevPinCount) {
                        $loopStateObj = [ordered]@{
                            Timestamp        = [DateTimeOffset]::UtcNow.ToString("o")
                            SystemModel      = $hw.SystemModel
                            GpuDriverVersion = $hw.GpuDriverVersion
                            PubgBuildId      = $currentBuildId
                            Power            = [ordered]@{ ActiveScheme = $savedSchemeGuid; OverlayGuid = $savedOverlayGuid; Settings = $powerSnapshots }
                            Registry         = $regSnapshots
                            Services         = $telemetryRes.Services
                            DdmPath          = $savedDdmPath
                            PinnedProcesses  = $script:pinnedProcs
                        }
                        Write-BoostStateAtomically -StateFilePath $StateFile -StateObject $loopStateObj -IsDryRun $false
                    }
                } elseif ($gameSeen) {
                    break
                }
                Start-Sleep -Seconds 3
            }
        } finally {
            if ($timerLocked) {
                try {
                    [uint32]$relTimerRes = 0
                    [void][PubgIrisXeNative]::NtSetTimerResolution(5000, $false, [ref]$relTimerRes)
                } catch {}
            }
            Invoke-SessionAutoRestore
        }
    }

    if (-not $NoWait -and -not $isDry) { Wait-PubgSessionAndRestore }
} finally {
    Exit-IrisXeMutex -LockHandle $boostLock
}
exit 0
