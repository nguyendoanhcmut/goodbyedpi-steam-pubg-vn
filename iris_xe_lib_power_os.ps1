$SubProcessor  = "54533251-82be-4824-96c1-47b60b740d00"
$SubGraphics   = "5fb4938d-1ee8-4b0f-9a3c-5036b0ab995c"
$SubIntelGfx   = "44f3beca-a7c0-460e-9df2-bb8b99e0cba6"
$SubPciExpress = "501a4d13-42af-4429-9fd1-a8218c268e20"
$SubDisk       = "0012ee47-9041-4b5d-9b77-535fba8b1442"
$SubWireless   = "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1"
$PubgBoostSchemeGuid = "d4e34500-1355-496e-96e0-735167616d65"
$PubgPowerSchemeGuid = $PubgBoostSchemeGuid
$BalancedSchemeGuid  = "381b4222-f694-41f0-9685-ff5bb260df2e"

# Intel Dynamic Tuning and Dell EC services must never stop or PL1 drops to a 15W static fail-safe.
$ProtectedThermalServices = @("ipfsvc", "ipf_uf", "esifsvc", "dptftcs", "DellOptimizer", "DPMService", "TPMProvisioningService")

$SuspendableTelemetryServices = @(
    "SupportAssistAgent", "DellTechHub", "DDVDataCollector", "DDVRulesProcessor", "DDVCollectorSvcApi",
    "DellClientManagementService", "Dell SupportAssist Remediation", "Dell Digital Delivery Services",
    "WSearch", "DiagTrack", "SysMain"
)

$BackgroundPinTargets = @(
    "steamwebhelper", "Discord", "chrome", "msedge", "msedgewebview2", "brave", "firefox",
    "SearchHost", "Widgets", "OneDrive", "EpicWebHelper", "UnrealCEFSubProcess_3071", "UnrealCEFSubProcess", "CoherentUI_Host"
)

$IfeoSpecTable = @(
    @{ Exe = "TslGame.exe";                  CpuPriorityClass = 3; IoPriority = 3; PagePriority = 5 },
    @{ Exe = "ExecPubg.exe";                 CpuPriorityClass = 3; IoPriority = 3; PagePriority = 5 },
    # Keep anti-cheat wrappers at Normal (2) so scans do not preempt TslGame.exe GameThread on the 2 P-cores.
    @{ Exe = "TslGame_BE.exe";               CpuPriorityClass = 2; IoPriority = 2; PagePriority = 5 },
    @{ Exe = "TslGame_ZK.exe";               CpuPriorityClass = 2; IoPriority = 2; PagePriority = 5 },
    @{ Exe = "UnrealCEFSubProcess_3071.exe"; CpuPriorityClass = 5; IoPriority = 1; PagePriority = 3 },
    @{ Exe = "UnrealCEFSubProcess.exe";      CpuPriorityClass = 5; IoPriority = 1; PagePriority = 3 },
    @{ Exe = "CoherentUI_Host.exe";          CpuPriorityClass = 5; IoPriority = 1; PagePriority = 3 }
)

function Get-RegistrySpecTable {
    param([bool]$IncludeMpoDisable = $false, [bool]$IsAdmin = $false)
    $specs = @()
    if ($IncludeMpoDisable) {
        $specs += @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayTestMode"; Value = 5; Type = "DWord" }
        $specs += @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayMinFPS"; Value = 0; Type = "DWord" }
    }
    $specs += @(
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehaviorMode"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "SystemResponsiveness"; Value = 10; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; Value = 4294967295; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Value = 8; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Value = 6; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Value = "High"; Type = "String" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "SFIO Priority"; Value = "High"; Type = "String" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"; Name = "GlobalTimerResolutionRequests"; Value = 1; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Value = 1; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows Search\Gather\Windows\SystemIndex"; Name = "RespectPowerModes"; Type = "DWord"; Value = 1 }
    )
    $pubgBaseDir = if (Get-Command Resolve-SteamPubgInstallDir -ErrorAction SilentlyContinue) {
        Resolve-SteamPubgInstallDir
    } else {
        $pf86 = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }
        Join-Path (Join-Path $pf86 "Steam") "steamapps\common\PUBG"
    }
    $pubgWin64Dir = Join-Path $pubgBaseDir "TslGame\Binaries\Win64"
    foreach ($gpuExe in @("TslGame.exe", "ExecPubg.exe", "TslGame_BE.exe", "TslGame_ZK.exe")) {
        $specs += @{ Path = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"; Name = (Join-Path $pubgWin64Dir $gpuExe); Value = "GpuPreference=2;"; Type = "String" }
    }
    if ($IsAdmin) {
        try {
            $cfgKeys = @(Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" -ErrorAction SilentlyContinue)
            foreach ($ck in $cfgKeys) {
                $sub00 = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration\$($ck.PSChildName)\00\00"
                if (Test-Path -LiteralPath $sub00) { $specs += @{ Path = $sub00; Name = "Scaling"; Value = 3; Type = "DWord" } }
            }
        } catch {}
    }
    return $specs
}

function Get-TargetPowerSettings {
    param([bool]$IsHybrid = $true)
    # On hybrid CPUs (i7-1355U), Class 0 controls the 8 E-cores and Class 1 controls the 2 P-cores.
    $c0FreqAC = if ($IsHybrid) { 2800 } else { 3700 }; $c0FreqDC = if ($IsHybrid) { 2400 } else { 3200 }
    $c0EppAC  = if ($IsHybrid) { 40 }   else { 20 };   $c0EppDC  = if ($IsHybrid) { 50 }   else { 35 }
    $c0ParkAC = if ($IsHybrid) { 50 }   else { 100 };  $c0ParkDC = if ($IsHybrid) { 25 }   else { 100 }
    $settings = @(
        @{ Subgroup = $SubProcessor;  Guid = "893dee8e-2bef-41e0-89c6-b55d0929964c"; Name = "PROCTHROTTLEMIN (Class 0)";  AC = 5;        DC = 5        },
        @{ Subgroup = $SubProcessor;  Guid = "893dee8e-2bef-41e0-89c6-b55d0929964d"; Name = "PROCTHROTTLEMIN1 (P-cores)"; AC = 5;        DC = 5        },
        @{ Subgroup = $SubProcessor;  Guid = "bc5038f7-23e0-4960-96da-33abaf5935ec"; Name = "PROCTHROTTLEMAX (Class 0)";  AC = 100;      DC = 100      },
        @{ Subgroup = $SubProcessor;  Guid = "bc5038f7-23e0-4960-96da-33abaf5935ed"; Name = "PROCTHROTTLEMAX1 (P-cores)"; AC = 100;      DC = 100      },
        @{ Subgroup = $SubProcessor;  Guid = "75b0ae3f-bce0-45a7-8c89-c9611c25e100"; Name = "PROCFREQMAX (Class 0 MHz)";  AC = $c0FreqAC; DC = $c0FreqDC },
        @{ Subgroup = $SubProcessor;  Guid = "75b0ae3f-bce0-45a7-8c89-c9611c25e101"; Name = "PROCFREQMAX1 (P-cores MHz)"; AC = 3700;     DC = 3200     },
        @{ Subgroup = $SubProcessor;  Guid = "36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Name = "PERFEPP (Class 0)";          AC = $c0EppAC; DC = $c0EppDC },
        @{ Subgroup = $SubProcessor;  Guid = "36687f9e-e3a5-4dbf-b1dc-15eb381c6864"; Name = "PERFEPP1 (P-cores)";         AC = 20;       DC = 35       },
        @{ Subgroup = $SubProcessor;  Guid = "be337238-0d82-4146-a960-4f3749d470c7"; Name = "PERFBOOSTMODE";              AC = 3;        DC = 3        },
        @{ Subgroup = $SubProcessor;  Guid = "0cc5b647-c1df-4637-891a-dec35c318583"; Name = "CPMINCORES (Class 0)";       AC = $c0ParkAC; DC = $c0ParkDC },
        @{ Subgroup = $SubProcessor;  Guid = "0cc5b647-c1df-4637-891a-dec35c318584"; Name = "CPMINCORES1 (P-cores)";      AC = 100;      DC = 100      },
        @{ Subgroup = $SubProcessor;  Guid = "7f2f5cfa-f10c-4823-b5e1-e93ae85f46b5"; Name = "HETEROPOLICY";               AC = 0;        DC = 4        },
        @{ Subgroup = $SubProcessor;  Guid = "93b8b6dc-0698-4d1c-9ee4-0644e900c85d"; Name = "SCHEDPOLICY";                AC = 2;        DC = 5        },
        @{ Subgroup = $SubProcessor;  Guid = "bae08b81-2d5e-4688-ad6a-13243356654b"; Name = "SHORTSCHEDPOLICY";           AC = 4;        DC = 4        },
        @{ Subgroup = $SubProcessor;  Guid = "94d3a615-a899-4ac5-ae2b-e4d8f634367f"; Name = "SYSCOOLPOL";                 AC = 1;        DC = 1        },
        @{ Subgroup = $SubGraphics;   Guid = "dd848b2a-8a5d-4451-9ae2-39cd41658f6c"; Name = "GPUPREFERENCEPOLICY";        AC = 0;        DC = 0        },
        @{ Subgroup = $SubPciExpress; Guid = "ee12f906-d277-404b-b6da-e5fa1a576df5"; Name = "PCIE_ASPM";                  AC = 0;        DC = 1        },
        @{ Subgroup = $SubDisk;       Guid = "d639518a-e56d-4345-8af2-b9f32fb26109"; Name = "NVME_IDLE_TIMEOUT_MS";       AC = 5000;     DC = 200      },
        @{ Subgroup = $SubDisk;       Guid = "fc95af4d-40e7-4b6d-835a-56d131dbc80e"; Name = "NVME_LATENCY_TOLERANCE_MS";  AC = 0;        DC = 15       },
        @{ Subgroup = $SubWireless;   Guid = "12bbebe6-58d6-4636-95bb-3217ef867c1a"; Name = "WLAN_POWER_SAVING";          AC = 0;        DC = 0        }
    )
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\$SubIntelGfx\3619c3f2-afb2-4afc-b0e9-e7fef372de36") {
        $settings += @{ Subgroup = $SubIntelGfx; Guid = "3619c3f2-afb2-4afc-b0e9-e7fef372de36"; Name = "INTEL_GFX_POWER_PLAN"; AC = 2; DC = 1 }
    }
    foreach ($st in $settings) { $st.Setting = $st.Guid }
    return $settings
}

function Get-PowerSettingIndices {
    param([string]$SchemeGuid, [string]$SubgroupGuid, [string]$SettingGuid)
    try {
        [Guid]$sGuid = [Guid]$SchemeGuid; [Guid]$subGuid = [Guid]$SubgroupGuid; [Guid]$setGuid = [Guid]$SettingGuid
        [uint32]$acVal = 0; [uint32]$dcVal = 0
        $rAc = [PubgIrisXeNative]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$sGuid, [ref]$subGuid, [ref]$setGuid, [ref]$acVal)
        $rDc = [PubgIrisXeNative]::PowerReadDCValueIndex([IntPtr]::Zero, [ref]$sGuid, [ref]$subGuid, [ref]$setGuid, [ref]$dcVal)
        if ($rAc -eq 0 -or $rDc -eq 0) { return [ordered]@{ AC = $(if ($rAc -eq 0) { $acVal } else { $null }); DC = $(if ($rDc -eq 0) { $dcVal } else { $null }) } }
    } catch {}
    $out = & powercfg.exe /qh $SchemeGuid $SubgroupGuid $SettingGuid
    $ac = $null; $dc = $null
    foreach ($line in $out) {
        if ($line -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $ac = [Convert]::ToUInt32($Matches[1], 16) }
        if ($line -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $dc = [Convert]::ToUInt32($Matches[1], 16) }
    }
    return [ordered]@{ AC = $ac; DC = $dc }
}

function Enable-PubgClonedPowerScheme {
    param([string]$BaseSchemeGuid, [object[]]$PowerSpecs, [bool]$IsDryRun = $false)
    $baseGuid = if (-not [string]::IsNullOrWhiteSpace($BaseSchemeGuid) -and $BaseSchemeGuid -ne $PubgPowerSchemeGuid) { $BaseSchemeGuid } else { $BalancedSchemeGuid }
    if ($IsDryRun) { return $PubgPowerSchemeGuid }
    [void](Set-RegistryValueSafely -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "PubgIrisXeCrashRecovery" -Value "powercfg.exe /setactive $baseGuid" -Type "String" -IsDryRun $false)
    if (((& powercfg.exe /list) -join " ") -notmatch [regex]::Escape($PubgPowerSchemeGuid)) {
        & powercfg.exe /duplicatescheme $baseGuid $PubgPowerSchemeGuid | Out-Null
    }
    & powercfg.exe /changename $PubgPowerSchemeGuid "PUBG Iris Xe Boost" "Dedicated 2P+8E & Iris Xe 96EU Boost" | Out-Null
    [Guid]$cGuid = [Guid]$PubgPowerSchemeGuid
    foreach ($s in $PowerSpecs) {
        [Guid]$subGuid = [Guid]$s.Subgroup
        [Guid]$setGuid = [Guid]$(if ($s.Setting) { $s.Setting } else { $s.Guid })
        if ($null -ne $s.AC) { [void][PubgIrisXeNative]::PowerWriteACValueIndex([IntPtr]::Zero, [ref]$cGuid, [ref]$subGuid, [ref]$setGuid, [uint32]$s.AC) }
        if ($null -ne $s.DC) { [void][PubgIrisXeNative]::PowerWriteDCValueIndex([IntPtr]::Zero, [ref]$cGuid, [ref]$subGuid, [ref]$setGuid, [uint32]$s.DC) }
    }
    $zeroOverlay = [Guid]::Empty
    try { [void][PubgIrisXeNative]::PowerSetActiveOverlayScheme([ref]$zeroOverlay) } catch {}
    if ([PubgIrisXeNative]::PowerSetActiveScheme([IntPtr]::Zero, [ref]$cGuid) -ne 0) {
        & powercfg.exe /setactive $PubgPowerSchemeGuid | Out-Null
    }
    return $PubgPowerSchemeGuid
}

function Restore-PubgOriginalPowerScheme {
    [Alias("Disable-PubgClonedPowerScheme")]
    param([string]$OriginalSchemeGuid, [string]$OriginalOverlayGuid, [object[]]$PowerSnapshots = @(), [bool]$IsDryRun = $false)
    if ($IsDryRun) { return }
    $targetGuid = if (-not [string]::IsNullOrWhiteSpace($OriginalSchemeGuid) -and $OriginalSchemeGuid -ne $PubgBoostSchemeGuid) { $OriginalSchemeGuid } else { $BalancedSchemeGuid }
    try {
        if (-not [PubgIrisXeNative]::SetActivePowerSchemeNative([Guid]$targetGuid)) { & powercfg.exe /setactive $targetGuid | Out-Null }
    } catch { & powercfg.exe /setactive $targetGuid | Out-Null }
    if ($OriginalOverlayGuid) {
        try { $ovGuid = [Guid]([string]$OriginalOverlayGuid); [void][PubgIrisXeNative]::PowerSetActiveOverlayScheme([ref]$ovGuid) } catch {}
    }
    if (((& powercfg.exe /list) -join " ") -match [regex]::Escape($PubgBoostSchemeGuid)) {
        & powercfg.exe /delete $PubgBoostSchemeGuid | Out-Null
    }
    Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "PubgIrisXeCrashRecovery" -Force -ErrorAction SilentlyContinue
}

function Get-RegistryValueSnapshot {
    param([string]$Path, [string]$Name)
    $parentPath = Split-Path -Path $Path -Parent
    $parentExisted = if ($parentPath) { Test-Path -LiteralPath $parentPath } else { $true }
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ Path = $Path; Name = $Name; ParentPath = $parentPath; ParentKeyExisted = $parentExisted; KeyExisted = $false; ValueExisted = $false; Value = $null; Kind = $null }
    }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $val = $item.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $val) {
            return [ordered]@{ Path = $Path; Name = $Name; ParentPath = $parentPath; ParentKeyExisted = $parentExisted; KeyExisted = $true; ValueExisted = $false; Value = $null; Kind = $null }
        }
        return [ordered]@{ Path = $Path; Name = $Name; ParentPath = $parentPath; ParentKeyExisted = $parentExisted; KeyExisted = $true; ValueExisted = $true; Value = $val; Kind = $item.GetValueKind($Name).ToString() }
    } catch {
        return [ordered]@{ Path = $Path; Name = $Name; ParentPath = $parentPath; ParentKeyExisted = $parentExisted; KeyExisted = $true; ValueExisted = $false; Value = $null; Kind = $null }
    }
}

function Merge-RegistryValueSnapshots {
    param([object[]]$ExistingSnapshots = @(), [object[]]$RegistrySpecs = @(), [object[]]$IfeoSpecs = @())
    $merged = New-Object System.Collections.Generic.List[object]
    $seenKeys = @{}
    if ($null -ne $ExistingSnapshots) {
        foreach ($snap in $ExistingSnapshots) {
            if ($null -ne $snap -and $snap.Path -and $snap.Name) {
                $k = "$($snap.Path)|$($snap.Name)"
                if (-not $seenKeys.ContainsKey($k)) {
                    $seenKeys[$k] = $true
                    $merged.Add($snap)
                }
            }
        }
    }
    if ($null -ne $RegistrySpecs) {
        foreach ($rSpec in $RegistrySpecs) {
            if ($null -eq $rSpec -or -not $rSpec.Path -or -not $rSpec.Name) { continue }
            $k = "$($rSpec.Path)|$($rSpec.Name)"
            if (-not $seenKeys.ContainsKey($k)) {
                $seenKeys[$k] = $true
                $merged.Add((Get-RegistryValueSnapshot -Path $rSpec.Path -Name $rSpec.Name))
            }
        }
    }
    if ($null -ne $IfeoSpecs) {
        foreach ($ifeo in $IfeoSpecs) {
            if ($null -eq $ifeo -or -not $ifeo.Exe) { continue }
            $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$($ifeo.Exe)\PerfOptions"
            foreach ($propName in @("CpuPriorityClass", "IoPriority", "PagePriority")) {
                $k = "$ifeoPath|$propName"
                if (-not $seenKeys.ContainsKey($k)) {
                    $seenKeys[$k] = $true
                    $merged.Add((Get-RegistryValueSnapshot -Path $ifeoPath -Name $propName))
                }
            }
        }
    }
    return $merged.ToArray()
}

function Read-BoostStateSafely {
    param([string]$StateFilePath)
    if ([string]::IsNullOrWhiteSpace($StateFilePath)) { return $null }
    foreach ($candidate in @($StateFilePath, "$StateFilePath.bak")) {
        if (Test-Path -LiteralPath $candidate) {
            try {
                $parsed = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $parsed -and $null -ne $parsed.Registry) { return $parsed }
            } catch {}
        }
    }
    return $null
}

function Write-BoostStateAtomically {
    param([string]$StateFilePath, [object]$StateObject, [bool]$IsDryRun = $false)
    if ($IsDryRun -or [string]::IsNullOrWhiteSpace($StateFilePath) -or $null -eq $StateObject) { return }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $mtx = $null; $acquired = $false
    try {
        try {
            $mtx = New-Object System.Threading.Mutex($false, "Global\PubgIrisXeState_Mutex")
        } catch {
            $mtx = New-Object System.Threading.Mutex($false, "Local\PubgIrisXeState_Mutex")
        }
        try { $acquired = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }

        $parentDir = Split-Path -Path $StateFilePath -Parent
        if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

        $existingOnDisk = Read-BoostStateSafely -StateFilePath $StateFilePath
        if ($null -ne $existingOnDisk) {
            if ($null -ne $existingOnDisk.Registry -and @($existingOnDisk.Registry).Count -gt 0) {
                $mergedReg = New-Object System.Collections.Generic.List[object]
                $seenReg = @{}
                foreach ($er in @($existingOnDisk.Registry)) {
                    if ($null -ne $er -and $er.Path -and $er.Name) {
                        $rk = "$($er.Path)|$($er.Name)"
                        if (-not $seenReg.ContainsKey($rk)) { $seenReg[$rk] = $true; $mergedReg.Add($er) }
                    }
                }
                if ($null -ne $StateObject.Registry) {
                    foreach ($nr in @($StateObject.Registry)) {
                        if ($null -ne $nr -and $nr.Path -and $nr.Name) {
                            $rk = "$($nr.Path)|$($nr.Name)"
                            if (-not $seenReg.ContainsKey($rk)) { $seenReg[$rk] = $true; $mergedReg.Add($nr) }
                        }
                    }
                }
                $StateObject.Registry = $mergedReg.ToArray()
            }
            if ($null -ne $existingOnDisk.Services -and @($existingOnDisk.Services).Count -gt 0) {
                $mergedSvc = New-Object System.Collections.Generic.List[object]
                $seenSvc = @{}
                foreach ($es in @($existingOnDisk.Services)) {
                    if ($null -ne $es -and $es.Name -and -not $seenSvc.ContainsKey($es.Name)) {
                        $seenSvc[$es.Name] = $true; $mergedSvc.Add($es)
                    }
                }
                if ($null -ne $StateObject.Services) {
                    foreach ($ns in @($StateObject.Services)) {
                        if ($null -ne $ns -and $ns.Name -and -not $seenSvc.ContainsKey($ns.Name)) {
                            $seenSvc[$ns.Name] = $true; $mergedSvc.Add($ns)
                        }
                    }
                }
                $StateObject.Services = $mergedSvc.ToArray()
            }
            if ($null -ne $existingOnDisk.PinnedProcesses -and @($existingOnDisk.PinnedProcesses).Count -gt 0) {
                $mergedPin = New-Object System.Collections.Generic.List[object]
                $seenPin = @{}
                foreach ($ep in @($existingOnDisk.PinnedProcesses)) {
                    if ($null -ne $ep -and $null -ne $ep.Id) {
                        $pk = "$($ep.Id):$($ep.ProcessName)"
                        if (-not $seenPin.ContainsKey($pk)) { $seenPin[$pk] = $true; $mergedPin.Add($ep) }
                    }
                }
                if ($null -ne $StateObject.PinnedProcesses) {
                    foreach ($np in @($StateObject.PinnedProcesses)) {
                        if ($null -ne $np -and $null -ne $np.Id) {
                            $pk = "$($np.Id):$($np.ProcessName)"
                            if (-not $seenPin.ContainsKey($pk)) { $seenPin[$pk] = $true; $mergedPin.Add($np) }
                        }
                    }
                }
                $StateObject.PinnedProcesses = $mergedPin.ToArray()
            }
        }

        $jsonPayload = $StateObject | ConvertTo-Json -Depth 6
        $tmpPath = "$StateFilePath.tmp.$PID"
        try {
            [System.IO.File]::WriteAllText($tmpPath, $jsonPayload, $utf8NoBom)
            if (Test-Path -LiteralPath $StateFilePath) { [System.IO.File]::SetAttributes($StateFilePath, [System.IO.FileAttributes]::Normal) }
            [System.IO.File]::Copy($tmpPath, $StateFilePath, $true)
            $bakPath = "$StateFilePath.bak"
            if (Test-Path -LiteralPath $bakPath) { [System.IO.File]::SetAttributes($bakPath, [System.IO.FileAttributes]::Normal) }
            [System.IO.File]::Copy($tmpPath, $bakPath, $true)
        } finally {
            if ([System.IO.File]::Exists($tmpPath)) { try { [System.IO.File]::Delete($tmpPath) } catch {} }
        }
    } finally {
        if ($null -ne $mtx) {
            try { if ($acquired) { $mtx.ReleaseMutex() } } catch {}
            try { $mtx.Dispose() } catch {}
        }
    }
}

function Set-RegistryValueSafely {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type, [bool]$IsDryRun = $false)
    if ($IsDryRun) { return $true }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        if ($Type -eq "DWord") {
            $bytes = [BitConverter]::GetBytes([int64]$Value)
            $int32Val = [BitConverter]::ToInt32($bytes, 0)
            New-ItemProperty -LiteralPath $Path -Name $Name -Value $int32Val -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        } else {
            New-ItemProperty -LiteralPath $Path -Name $Name -Value ([string]$Value) -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        }
        return $true
    } catch { return $false }
}

function Restore-RegistryValueSnapshot {
    param([object]$Snap, [bool]$IsDryRun = $false)
    if ($IsDryRun -or $null -eq $Snap) { return $true }
    try {
        if (-not $Snap.KeyExisted) {
            if (Test-Path -LiteralPath $Snap.Path) {
                $kItemBefore = Get-Item -LiteralPath $Snap.Path -ErrorAction Stop
                if ($Snap.Name -and ($null -ne $kItemBefore.GetValue($Snap.Name, $null))) {
                    Remove-ItemProperty -LiteralPath $Snap.Path -Name $Snap.Name -Force -ErrorAction Stop
                }
                $kItem = Get-Item -LiteralPath $Snap.Path -ErrorAction Stop
                if ($null -ne $kItem -and $kItem.SubKeyCount -eq 0 -and $kItem.ValueCount -eq 0) {
                    Remove-Item -LiteralPath $Snap.Path -Force -ErrorAction Stop
                }
            }
            $parentPath = if ($Snap.PSObject.Properties['ParentPath'] -and $Snap.ParentPath) { [string]$Snap.ParentPath } else { Split-Path -Path $Snap.Path -Parent }
            $parentExisted = if ($Snap.PSObject.Properties['ParentKeyExisted'] -and $null -ne $Snap.ParentKeyExisted) { [bool]$Snap.ParentKeyExisted } else { $true }
            if ((-not $parentExisted) -and $parentPath -and (Test-Path -LiteralPath $parentPath)) {
                $pItem = Get-Item -LiteralPath $parentPath -ErrorAction Stop
                if ($null -ne $pItem -and $pItem.SubKeyCount -eq 0 -and $pItem.ValueCount -eq 0) {
                    Remove-Item -LiteralPath $parentPath -Force -ErrorAction Stop
                }
            }
            return $true
        }
        if (-not $Snap.ValueExisted) {
            if (Test-Path -LiteralPath $Snap.Path) {
                $kItem = Get-Item -LiteralPath $Snap.Path -ErrorAction Stop
                if ($null -ne $kItem.GetValue($Snap.Name, $null)) {
                    Remove-ItemProperty -LiteralPath $Snap.Path -Name $Snap.Name -Force -ErrorAction Stop
                }
            }
            return $true
        }
        $kind = if ($Snap.Kind) { [string]$Snap.Kind } else { "DWord" }
        if (Set-RegistryValueSafely -Path $Snap.Path -Name $Snap.Name -Value $Snap.Value -Type $kind -IsDryRun $IsDryRun) {
            return $true
        }
        $cur = Get-RegistryValueSnapshot -Path $Snap.Path -Name $Snap.Name
        if ($cur.KeyExisted -and $cur.ValueExisted -and ([string]$cur.Value -eq [string]$Snap.Value)) {
            return $true
        }
        return $false
    } catch {
        try {
            $cur = Get-RegistryValueSnapshot -Path $Snap.Path -Name $Snap.Name
            if (-not $Snap.KeyExisted -and -not $cur.KeyExisted) { return $true }
            if (-not $Snap.ValueExisted -and -not $cur.ValueExisted) { return $true }
            if ($Snap.ValueExisted -and $cur.ValueExisted -and ([string]$cur.Value -eq [string]$Snap.Value)) { return $true }
        } catch {}
        return $false
    }
}

function Clear-PubgFaultTolerantHeapShim {
    param([switch]$DryRun, [bool]$IsDryRun = $false)
    $isDry = $DryRun.IsPresent -or $IsDryRun
    $fthPaths = @("HKLM:\SOFTWARE\Microsoft\FTH\State", "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers", "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers")
    $removed = @()
    foreach ($rPath in $fthPaths) {
        if (-not (Test-Path -LiteralPath $rPath)) { continue }
        try {
            $rk = Get-Item -LiteralPath $rPath -ErrorAction Stop
            foreach ($vName in @($rk.GetValueNames())) {
                if ($vName -match '(?i)TslGame\.exe') {
                    $vData = [string]$rk.GetValue($vName, "")
                    if ($rPath -match 'FTH\\State$' -or $vData -match '(?i)FaultTolerantHeap' -or $vName -match '(?i)TslGame\.exe') {
                        if (-not $isDry) { Remove-ItemProperty -LiteralPath $rPath -Name $vName -Force -ErrorAction SilentlyContinue }
                        $removed += "$rPath -> $vName"
                    }
                }
            }
        } catch {}
    }
    return [PSCustomObject]@{ ClearedCount = $removed.Count; Entries = $removed }
}

function Get-RunningTelemetryServicesSnapshot {
    param([object[]]$ExistingServices = @())
    $stoppedServices = @()
    if ($null -ne $ExistingServices) { foreach ($item in $ExistingServices) { if ($null -ne $item) { $stoppedServices += $item } } }
    foreach ($svcName in $SuspendableTelemetryServices) {
        if ($ProtectedThermalServices -contains $svcName) { continue }
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -eq "Running") {
            if (-not ($stoppedServices | Where-Object { $_.Name -eq $svc.Name })) {
                $stoppedServices += [ordered]@{ Name = $svc.Name; StartType = [string]$svc.StartType; WasRunning = $true }
            }
        }
    }
    $ddmProcs = @(Get-Process -Name "ddm" -ErrorAction SilentlyContinue)
    $ddmPath = $null
    if ($ddmProcs.Count -gt 0) {
        try { $ddmPath = $ddmProcs[0].Path } catch {}
    }
    foreach ($dp in $ddmProcs) { $dp.Dispose() }
    return [PSCustomObject]@{ Services = $stoppedServices; DdmPath = $ddmPath }
}

function Suspend-TelemetryServicesSafely {
    param([object[]]$ExistingServices = @(), [bool]$IsAdmin = $false, [bool]$IsDryRun = $false)
    $stoppedServices = @()
    if ($null -ne $ExistingServices) { foreach ($item in $ExistingServices) { if ($null -ne $item) { $stoppedServices += $item } } }
    if ($IsAdmin) {
        foreach ($svcName in $SuspendableTelemetryServices) {
            if ($ProtectedThermalServices -contains $svcName) { continue }
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($null -ne $svc -and $svc.Status -eq "Running") {
                try {
                    if (-not $IsDryRun) { Stop-Service -Name $svcName -Force -NoWait -ErrorAction Stop }
                    if (-not ($stoppedServices | Where-Object { $_.Name -eq $svc.Name })) {
                        $stoppedServices += [ordered]@{ Name = $svc.Name; StartType = [string]$svc.StartType; WasRunning = $true }
                    }
                } catch {}
            }
        }
    }
    $ddmProcs = @(Get-Process -Name "ddm" -ErrorAction SilentlyContinue)
    $ddmPath = $null
    if ($ddmProcs.Count -gt 0) {
        try { $ddmPath = $ddmProcs[0].Path } catch {}
        if (-not $IsDryRun) { Stop-Process -Id $ddmProcs[0].Id -Force -ErrorAction SilentlyContinue }
    }
    foreach ($dp in $ddmProcs) { $dp.Dispose() }
    return [PSCustomObject]@{ Services = $stoppedServices; DdmPath = $ddmPath }
}

function Restore-SessionRuntimeState {
    param([string]$StateFilePath, [bool]$IsDryRun = $false)
    $saved = Read-BoostStateSafely -StateFilePath $StateFilePath
    $origScheme  = if ($saved -and $saved.Power -and $saved.Power.ActiveScheme) { [string]$saved.Power.ActiveScheme } else { $BalancedSchemeGuid }
    $origOverlay = if ($saved -and $saved.Power -and $saved.Power.OverlayGuid) { [string]$saved.Power.OverlayGuid } else { $null }
    $powerSnaps  = if ($saved -and $saved.Power -and $saved.Power.Settings) { @($saved.Power.Settings) } else { @() }
    Restore-PubgOriginalPowerScheme -OriginalSchemeGuid $origScheme -OriginalOverlayGuid $origOverlay -PowerSnapshots $powerSnaps -IsDryRun $IsDryRun
    if (-not $IsDryRun) {
        Restore-BackgroundProcessesAffinity -PinnedRecords $(if ($saved -and $saved.PinnedProcesses) { @($saved.PinnedProcesses) } else { @() }) -IsDryRun $IsDryRun
        if ($saved -and $saved.Services) {
            foreach ($svcEntry in $saved.Services) { if ($svcEntry.WasRunning) { & sc.exe start $svcEntry.Name | Out-Null } }
        }
        if ($saved -and $saved.DdmPath -and [System.IO.File]::Exists([string]$saved.DdmPath)) {
            $ddmProcs = @(Get-Process -Name "ddm" -ErrorAction SilentlyContinue)
            $ddmRunning = $ddmProcs.Count -gt 0
            foreach ($dp in $ddmProcs) { $dp.Dispose() }
            if (-not $ddmRunning) {
                try { Start-Process -FilePath ([string]$saved.DdmPath) -WindowStyle Minimized -ErrorAction SilentlyContinue } catch {}
            }
        }
    }
    return $saved
}

function Invoke-PreLaunchSharedVramPurge {
    param([bool]$IsDryRun = $false)
    $tslProcs = @([System.Diagnostics.Process]::GetProcessesByName("TslGame"))
    foreach ($tp in $tslProcs) { $tp.Dispose() }
    if ($tslProcs.Count -gt 0) {
        return [PSCustomObject]@{ Skipped = $true; Reason = "TslGame.exe is running"; BeforeFreeZeroMB = 0.0; BeforeStandbyMB = 0.0; AfterFreeZeroMB = 0.0; AfterStandbyMB = 0.0; FreedMB = 0.0 }
    }
    $before = Get-NtMemoryListSnapshot
    if ($IsDryRun) {
        $bfz = if ($before) { $before.ImmediateFreeZeroMB } else { 0.0 }; $bsb = if ($before) { $before.StandbyMB } else { 0.0 }
        return [PSCustomObject]@{ Skipped = $true; Reason = "DryRun"; BeforeFreeZeroMB = $bfz; BeforeStandbyMB = $bsb; AfterFreeZeroMB = $bfz; AfterStandbyMB = $bsb; FreedMB = 0.0 }
    }
    foreach ($name in $BackgroundPinTargets) {
        foreach ($p in [System.Diagnostics.Process]::GetProcessesByName($name)) {
            try { [void][PubgIrisXeNative]::EmptyWorkingSet($p.Handle) } catch {} finally { $p.Dispose() }
        }
    }
    $privOk = [PubgIrisXeNative]::EnablePrivilege("SeProfileSingleProcessPrivilege")
    $wsStatus = [uint32]0xC0000061L; $flStatus = [uint32]0xC0000061L; $sbStatus = [uint32]0xC0000061L
    if ($privOk) {
        $wsStatus = [PubgIrisXeNative]::CommandMemoryList(2)
        Start-Sleep -Milliseconds 100
        $flStatus = [PubgIrisXeNative]::CommandMemoryList(3)
        Start-Sleep -Milliseconds 100
        $sbStatus = [PubgIrisXeNative]::CommandMemoryList(4)
        Start-Sleep -Milliseconds 100
    }
    $after = Get-NtMemoryListSnapshot
    $beforeFZ = if ($before) { $before.ImmediateFreeZeroMB } else { 0.0 }; $afterFZ = if ($after) { $after.ImmediateFreeZeroMB } else { 0.0 }
    return [PSCustomObject]@{
        Skipped = $false; PrivilegeEnabled = $privOk; WorkingSetStatusHex = ("0x{0:X8}" -f $wsStatus); FlushModifiedStatusHex = ("0x{0:X8}" -f $flStatus); StandbyStatusHex = ("0x{0:X8}" -f $sbStatus)
        BeforeFreeZeroMB = $beforeFZ; BeforeStandbyMB = if ($before) { $before.StandbyMB } else { 0.0 }
        AfterFreeZeroMB = $afterFZ; AfterStandbyMB = if ($after) { $after.StandbyMB } else { 0.0 }
        FreedMB = [math]::Round([math]::Max(0.0, ($afterFZ - $beforeFZ)), 1)
    }
}
