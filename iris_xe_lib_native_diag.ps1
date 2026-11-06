$NativeInteropSource = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class PubgIrisXeNative {
    private const int SystemMemoryListInformation = 80;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint TOKEN_QUERY = 0x0008;
    private const uint SE_PRIVILEGE_ENABLED = 0x00000002;
    private const int RelationProcessorCore = 0;
    private const int ENUM_CURRENT_SETTINGS = -1;
    public const int ProcessPowerThrottling = 4;
    public const uint PROCESS_POWER_THROTTLING_CURRENT_VERSION = 1;
    public const uint PROCESS_POWER_THROTTLING_EXECUTION_SPEED = 0x1;
    public const uint PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION = 0x4;

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct TokPriv1Luid { public int Count; public long Luid; public uint Attr; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_POWER_THROTTLING_STATE { public uint Version; public uint ControlMask; public uint StateMask; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_MEMORY_LIST_INFORMATION {
        public UIntPtr ZeroPageCount, FreePageCount, ModifiedPageCount, ModifiedNoWritePageCount, BadPageCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)] public UIntPtr[] PageCountByPriority;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)] public UIntPtr[] RepurposedPagesByPriority;
        public UIntPtr ModifiedPageCountPageFile;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODEA {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    public sealed class CpuTopologyInfo {
        public int PhysicalCoreCount { get; set; }
        public int LogicalProcessorCount { get; set; }
        public int PCoreCount { get; set; }
        public int ECoreCount { get; set; }
        public bool IsHybrid { get; set; }
        public ulong PCoreMask { get; set; }
        public ulong ECoreMask { get; set; }
        public ulong BackgroundPinMask { get; set; }
        public ulong AllProcessorsMask { get; set; }
    }

    [DllImport("advapi32.dll", SetLastError = true)] private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool LookupPrivilegeValueW(string lpSystemName, string lpName, out long lpLuid);
    [DllImport("advapi32.dll", SetLastError = true)] private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TokPriv1Luid NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CloseHandle(IntPtr hObject);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetProcessInformation(IntPtr hProcess, int ProcessInformationClass, ref PROCESS_POWER_THROTTLING_STATE ProcessInformation, uint ProcessInformationSize);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetProcessInformation(IntPtr hProcess, int ProcessInformationClass, out PROCESS_POWER_THROTTLING_STATE ProcessInformation, uint ProcessInformationSize);
    [DllImport("psapi.dll", SetLastError = true)] public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("ntdll.dll")] public static extern uint NtQuerySystemInformation(int SystemInformationClass, IntPtr SystemInfo, int SystemInfoLength, out int ReturnLength);
    [DllImport("ntdll.dll")] public static extern uint NtSetSystemInformation(int SystemInformationClass, ref int SystemInfo, int SystemInfoLength);
    [DllImport("ntdll.dll", SetLastError = true)] public static extern int NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint CurrentResolution);
    [DllImport("ntdll.dll", SetLastError = true)] public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);
    [DllImport("powrprof.dll", EntryPoint = "PowerGetActualOverlayScheme")] public static extern uint PowerGetActualOverlayScheme(out Guid ActualOverlayGuid);
    [DllImport("powrprof.dll", EntryPoint = "PowerSetActiveOverlayScheme")] public static extern uint PowerSetActiveOverlayScheme(ref Guid OverlaySchemeGuid);
    [DllImport("powrprof.dll", EntryPoint = "PowerSetActiveScheme")] public static extern uint PowerSetActiveScheme(IntPtr UserRootPowerKey, ref Guid SchemeGuid);
    [DllImport("powrprof.dll")] public static extern uint PowerReadACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, out uint AcValueIndex);
    [DllImport("powrprof.dll")] public static extern uint PowerReadDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, out uint DcValueIndex);
    [DllImport("powrprof.dll")] public static extern uint PowerWriteACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, uint AcValueIndex);
    [DllImport("powrprof.dll")] public static extern uint PowerWriteDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, uint DcValueIndex);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetLogicalProcessorInformationEx(int RelationshipType, IntPtr Buffer, ref uint ReturnedLength);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] private static extern bool EnumDisplaySettingsA(string lpszDeviceName, int iModeNum, ref DEVMODEA lpDevMode);

    public static bool SetEcoQoSAndTimerThrottle(IntPtr hProcess, uint controlMask, uint stateMask) {
        PROCESS_POWER_THROTTLING_STATE state = new PROCESS_POWER_THROTTLING_STATE { Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION, ControlMask = controlMask, StateMask = stateMask };
        return SetProcessInformation(hProcess, ProcessPowerThrottling, ref state, (uint)Marshal.SizeOf(typeof(PROCESS_POWER_THROTTLING_STATE)));
    }

    public static bool GetEcoQoSState(IntPtr hProcess, out uint controlMask, out uint stateMask) {
        PROCESS_POWER_THROTTLING_STATE state = new PROCESS_POWER_THROTTLING_STATE { Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION, ControlMask = 0, StateMask = 0 };
        if (GetProcessInformation(hProcess, ProcessPowerThrottling, out state, (uint)Marshal.SizeOf(typeof(PROCESS_POWER_THROTTLING_STATE)))) {
            controlMask = state.ControlMask;
            stateMask = state.StateMask;
            return true;
        }
        controlMask = 0;
        stateMask = 0;
        return false;
    }

    public static bool SetActivePowerSchemeNative(Guid schemeGuid) {
        return PowerSetActiveScheme(IntPtr.Zero, ref schemeGuid) == 0;
    }

    public static bool EnablePrivilege(string privilegeName) {
        IntPtr hToken = IntPtr.Zero;
        using (Process curProc = Process.GetCurrentProcess()) {
            if (!OpenProcessToken(curProc.Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hToken)) return false;
        }
        try {
            long luid = 0;
            if (!LookupPrivilegeValueW(null, privilegeName, out luid)) return false;
            TokPriv1Luid tp = new TokPriv1Luid { Count = 1, Luid = luid, Attr = SE_PRIVILEGE_ENABLED };
            bool ok = AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            return ok && (Marshal.GetLastWin32Error() == 0);
        } finally {
            CloseHandle(hToken);
        }
    }

    public static uint InvokeMemoryListCommand(int command) {
        int cmd = command;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, sizeof(int));
    }
    public static uint CommandMemoryList(int command) { return InvokeMemoryListCommand(command); }

    public static bool IsDisplayResolutionSupported(int width, int height) {
        DEVMODEA dm = new DEVMODEA();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODEA));
        for (int modeIndex = 0; EnumDisplaySettingsA(null, modeIndex, ref dm); modeIndex++) {
            if (dm.dmPelsWidth == width && dm.dmPelsHeight == height) return true;
        }
        return false;
    }

    public static bool GetCurrentDesktopResolution(out int width, out int height) {
        DEVMODEA dm = new DEVMODEA();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODEA));
        if (EnumDisplaySettingsA(null, ENUM_CURRENT_SETTINGS, ref dm) && dm.dmPelsWidth > 0 && dm.dmPelsHeight > 0) {
            width = dm.dmPelsWidth; height = dm.dmPelsHeight;
            return true;
        }
        width = 1920; height = 1080;
        return false;
    }

    public static int[] GetCurrentDesktopResolution() {
        int w, h; GetCurrentDesktopResolution(out w, out h);
        return new int[] { w, h };
    }

    public static bool GetRecommendedFullscreenResolution(int requestedX, int requestedY, out int outX, out int outY) {
        if (requestedX > 0 && requestedY > 0 && IsDisplayResolutionSupported(requestedX, requestedY)) {
            outX = requestedX; outY = requestedY; return true;
        }
        int deskW, deskH;
        GetCurrentDesktopResolution(out deskW, out deskH);
        bool is16By10 = (deskW > 0 && deskH > 0 && (deskW * 10 == deskH * 16));
        if (is16By10 && IsDisplayResolutionSupported(1280, 800)) { outX = 1280; outY = 800; return true; }
        if (IsDisplayResolutionSupported(1280, 720)) { outX = 1280; outY = 720; return true; }
        if (IsDisplayResolutionSupported(1280, 800)) { outX = 1280; outY = 800; return true; }
        if (IsDisplayResolutionSupported(1366, 768)) { outX = 1366; outY = 768; return true; }
        outX = deskW > 0 ? deskW : 1280; outY = deskH > 0 ? deskH : 720;
        return false;
    }

    public static int[] GetRecommendedFullscreenResolution(int requestedX, int requestedY) {
        int rx, ry; GetRecommendedFullscreenResolution(requestedX, requestedY, out rx, out ry);
        return new int[] { rx, ry };
    }

    private static int CountBits(ulong mask) { int count = 0; for (; mask != 0; count++) mask &= (mask - 1); return count; }

    public static CpuTopologyInfo DetectTopology() {
        uint returnLength = 0;
        GetLogicalProcessorInformationEx(RelationProcessorCore, IntPtr.Zero, ref returnLength);
        if (returnLength == 0) return FallbackTopology();
        IntPtr buffer = Marshal.AllocHGlobal((int)returnLength);
        try {
            if (!GetLogicalProcessorInformationEx(RelationProcessorCore, buffer, ref returnLength)) return FallbackTopology();
            var cores = new List<Tuple<byte, byte, ulong>>();
            byte maxEff = 0, minEff = 255;
            for (long offset = 0; offset + 36 <= returnLength; ) {
                IntPtr current = new IntPtr(buffer.ToInt64() + offset);
                int relationship = Marshal.ReadInt32(current, 0), size = Marshal.ReadInt32(current, 4);
                if (size <= 0 || offset + size > returnLength) break;
                if (relationship == RelationProcessorCore) {
                    byte flags = Marshal.ReadByte(current, 8), effClass = Marshal.ReadByte(current, 9);
                    ushort groupCount = (ushort)Marshal.ReadInt16(current, 30);
                    ulong mask = groupCount > 0 ? (IntPtr.Size == 8 ? (ulong)Marshal.ReadInt64(current, 32) : (ulong)(uint)Marshal.ReadInt32(current, 32)) : 0UL;
                    if (mask != 0) {
                        if (effClass > maxEff) maxEff = effClass;
                        if (effClass < minEff) minEff = effClass;
                        cores.Add(Tuple.Create(flags, effClass, mask));
                    }
                }
                offset += size;
            }
            if (cores.Count == 0) return FallbackTopology();
            bool isHybrid = (maxEff > minEff);
            ulong pMask = 0UL, eMask = 0UL, allMask = 0UL;
            int pCores = 0, eCores = 0, totalLp = 0;
            foreach (var c in cores) {
                totalLp += CountBits(c.Item3); allMask |= c.Item3;
                if (!isHybrid || c.Item2 == maxEff) { pMask |= c.Item3; pCores++; } else { eMask |= c.Item3; eCores++; }
            }
            ulong bgMask = isHybrid ? eMask : 0UL;
            if (!isHybrid && cores.Count >= 4) { for (int i = cores.Count / 2; i < cores.Count; i++) bgMask |= cores[i].Item3; }
            return new CpuTopologyInfo {
                PhysicalCoreCount = cores.Count, LogicalProcessorCount = totalLp, PCoreCount = pCores, ECoreCount = eCores,
                IsHybrid = isHybrid, PCoreMask = pMask, ECoreMask = eMask, BackgroundPinMask = bgMask, AllProcessorsMask = allMask
            };
        } finally { Marshal.FreeHGlobal(buffer); }
    }

    private static CpuTopologyInfo FallbackTopology() {
        int lp = Environment.ProcessorCount;
        ulong allMask = lp >= 64 ? ulong.MaxValue : ((1UL << lp) - 1UL);
        return new CpuTopologyInfo {
            PhysicalCoreCount = lp, LogicalProcessorCount = lp, PCoreCount = lp, ECoreCount = 0,
            IsHybrid = false, PCoreMask = allMask, ECoreMask = 0UL, BackgroundPinMask = 0UL, AllProcessorsMask = allMask
        };
    }
}
"@

if (-not ([System.Management.Automation.PSTypeName]'PubgIrisXeNative').Type) { Add-Type -TypeDefinition $NativeInteropSource }

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enter-IrisXeMutex {
    param([string]$MutexName = "Global\PubgIrisXeBoost_Mutex", [int]$TimeoutMs = 30000)
    $mtx = $null
    try {
        $mtx = New-Object System.Threading.Mutex($false, $MutexName)
    } catch {
        $fallbackName = $MutexName -replace '^Global\\', 'Local\'
        $mtx = New-Object System.Threading.Mutex($false, $fallbackName)
    }
    $acquired = $false
    try {
        $acquired = $mtx.WaitOne($TimeoutMs)
    } catch [System.Threading.AbandonedMutexException] {
        $acquired = $true
    }
    return [PSCustomObject]@{ Mutex = $mtx; Acquired = $acquired }
}

function Exit-IrisXeMutex {
    param([object]$LockHandle)
    if ($null -ne $LockHandle -and $null -ne $LockHandle.Mutex) {
        try { if ($LockHandle.Acquired) { $LockHandle.Mutex.ReleaseMutex() } } catch {}
        try { $LockHandle.Mutex.Dispose() } catch {}
    }
}

function Resolve-SteamPubgInstallDir {
    $uninstKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 578080"
    if (Test-Path -LiteralPath $uninstKey) {
        try {
            $loc = (Get-ItemProperty -LiteralPath $uninstKey -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
            if ($loc -and (Test-Path -LiteralPath $loc)) { return $loc }
        } catch {}
    }
    $pf86 = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }
    $defaultSteamRoot = Join-Path $pf86 "Steam"
    $steamRoot = $null
    foreach ($rk in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam", "HKCU:\Software\Valve\Steam")) {
        if (-not $steamRoot -and (Test-Path -LiteralPath $rk)) {
            try {
                $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
                if ($props.InstallPath -and (Test-Path -LiteralPath $props.InstallPath)) { $steamRoot = [string]$props.InstallPath }
                elseif ($props.SteamPath -and (Test-Path -LiteralPath $props.SteamPath)) { $steamRoot = ([string]$props.SteamPath).Replace('/', '\') }
            } catch {}
        }
    }
    if (-not $steamRoot) { $steamRoot = $defaultSteamRoot }
    $libRoots = New-Object System.Collections.Generic.List[string]
    if ($steamRoot) { $libRoots.Add($steamRoot) }
    foreach ($vdfRel in @("steamapps\libraryfolders.vdf", "config\libraryfolders.vdf")) {
        $vdfPath = Join-Path $steamRoot $vdfRel
        if ([System.IO.File]::Exists($vdfPath)) {
            try {
                $vdfRaw = [System.IO.File]::ReadAllText($vdfPath, [System.Text.Encoding]::UTF8)
                foreach ($m in [regex]::Matches($vdfRaw, '"path"\s+"([^"]+)"')) {
                    $p = $m.Groups[1].Value -replace '\\\\', '\'
                    if ($p -and -not $libRoots.Contains($p)) { $libRoots.Add($p) }
                }
            } catch {}
        }
    }
    foreach ($root in $libRoots) {
        $candidateDir = Join-Path $root "steamapps\common\PUBG"
        $candidateAcf = Join-Path $root "steamapps\appmanifest_578080.acf"
        if ((Test-Path -LiteralPath $candidateDir) -or [System.IO.File]::Exists($candidateAcf)) {
            return $candidateDir
        }
    }
    return (Join-Path $defaultSteamRoot "steamapps\common\PUBG")
}

function Get-SteamPubgBuildId {
    $pubgDir = Resolve-SteamPubgInstallDir
    $steamAppsDir = Split-Path (Split-Path $pubgDir -Parent) -Parent
    $acfPath = Join-Path $steamAppsDir "appmanifest_578080.acf"
    if ([System.IO.File]::Exists($acfPath)) {
        try { if (([System.IO.File]::ReadAllText($acfPath, [System.Text.Encoding]::UTF8)) -match '"buildid"\s+"(\d+)"') { return $Matches[1] } } catch {}
    }
    return "0"
}

function Get-NtMemoryListSnapshot {
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type][PubgIrisXeNative+SYSTEM_MEMORY_LIST_INFORMATION])
    $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    try {
        $retLen = 0; $status = [PubgIrisXeNative]::NtQuerySystemInformation(80, $ptr, $size, [ref]$retLen)
        if ($status -ne 0) { return $null }
        $info = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][PubgIrisXeNative+SYSTEM_MEMORY_LIST_INFORMATION])
        $zeroMB = [math]::Round(($info.ZeroPageCount.ToUInt64() * 4096) / 1MB, 1); $freeMB = [math]::Round(($info.FreePageCount.ToUInt64() * 4096) / 1MB, 1); $modMB = [math]::Round(($info.ModifiedPageCount.ToUInt64() * 4096) / 1MB, 1)
        $standbyPages = [uint64]0; for ($i = 0; $i -lt 8; $i++) { $standbyPages += $info.PageCountByPriority[$i].ToUInt64() }; $standbyMB = [math]::Round(($standbyPages * 4096) / 1MB, 1)
        return [PSCustomObject]@{ ImmediateFreeZeroMB = [math]::Round($zeroMB + $freeMB, 1); ZeroMB = $zeroMB; FreeMB = $freeMB; ModifiedMB = $modMB; StandbyMB = $standbyMB }
    } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
}

function Test-SystemHardwareAndMemory {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cs  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $dimms = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $gpus  = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $irisAdapter = $gpus | Where-Object { $_.Name -match 'Iris|Xe|UHD|Intel' } | Select-Object -First 1
    if ($null -eq $irisAdapter) { $irisAdapter = $gpus | Select-Object -First 1 }

    $dimmCount = $dimms.Count
    $totalBytes = ($dimms | Measure-Object Capacity -Sum).Sum
    $totalGB = if ($totalBytes -gt 0) { [math]::Round($totalBytes / 1GB, 1) } elseif ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 16.0 }
    $uniqueCapacities = @($dimms | Select-Object -ExpandProperty Capacity -Unique)
    $isSymmetricDual = ($dimmCount -ge 2) -and ($uniqueCapacities.Count -eq 1)
    $isFlexDual      = ($dimmCount -ge 2) -and ($uniqueCapacities.Count -gt 1)
    $clockMTs        = if ($dimmCount -gt 0 -and $dimms[0].ConfiguredClockSpeed) { [int]$dimms[0].ConfiguredClockSpeed } elseif ($dimmCount -gt 0 -and $dimms[0].Speed) { [int]$dimms[0].Speed } else { 5200 }
    $busWidthBits    = if ($dimmCount -ge 2) { 128 } else { 64 }
    $peakBandwidthGBs = [math]::Round(($clockMTs * ($busWidthBits / 8)) / 1000.0, 1)
    $channelMode = if ($isSymmetricDual) { "Symmetric Dual-Channel (128-bit)" } elseif ($isFlexDual) { "Asymmetric Flex Dual-Channel (Partial 128-bit)" } else { "Single-Channel (64-bit)" }
    $wavesProcs = @(Get-Process -Name "WavesSvc64","WavesSysSvc" -ErrorAction SilentlyContinue)
    $wavesActive = $wavesProcs.Count -gt 0
    foreach ($wp in $wavesProcs) { $wp.Dispose() }

    return [PSCustomObject]@{
        SystemModel = if ($cs) { "$($cs.Manufacturer) $($cs.Model)".Trim() } else { "Unknown" }; CpuName = if ($cpu) { $cpu.Name.Trim() } else { "Unknown" }
        GpuName = if ($irisAdapter) { $irisAdapter.Name.Trim() } else { "Unknown" }; GpuDriverVersion = if ($irisAdapter) { $irisAdapter.DriverVersion } else { "0.0.0.0" }
        DimmCount = $dimmCount; TotalCapacityGB = $totalGB; ConfiguredMTs = $clockMTs; ChannelMode = $channelMode; IsSymmetricDual = $isSymmetricDual
        PeakBandwidthGBs = $peakBandwidthGBs; IsOnBattery = ($null -ne $bat -and $bat.BatteryStatus -eq 1); BatteryStatus = if ($null -ne $bat) { [int]$bat.BatteryStatus } else { 2 }
        WavesMaxxAudioActive = $wavesActive; Topology = [PubgIrisXeNative]::DetectTopology()
    }
}

function Test-VbsHvciOverhead {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    return [PSCustomObject]@{
        VbsStatus = if ($null -ne $dg) { [int]$dg.VirtualizationBasedSecurityStatus } else { -1 }
        VbsRunning = ($null -ne $dg) -and ($dg.VirtualizationBasedSecurityStatus -eq 2); HvciRunning = ($null -ne $dg) -and ($dg.SecurityServicesRunning -contains 2)
    }
}

function Assert-MemoryAndPagefileHealth {
    param([Parameter(Position = 0)][bool]$IsAdmin = $false, [Parameter(Position = 1)][bool]$IsDryRun = $false)
    $mcProcs = @(Get-Process -Name "Memory Compression" -ErrorAction SilentlyContinue)
    $mcProc = if ($mcProcs.Count -gt 0) { $mcProcs[0] } else { $null }
    $mcWsBytes = if ($null -ne $mcProc) { $mcProc.WorkingSet64 } else { 0L }
    foreach ($mp in $mcProcs) { $mp.Dispose() }
    $mcActive = $mcWsBytes -gt 0; $mmChanged = $false
    if ($IsAdmin -and -not $IsDryRun) {
        try {
            $mm = Get-MMAgent -ErrorAction Stop
            if (-not $mm.MemoryCompression) { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue; $mcActive = $true; $mmChanged = $true }
            if ($mm.PageCombining) { Disable-MMAgent -PageCombining -ErrorAction SilentlyContinue; $mmChanged = $true }
        } catch {}
    }
    $pfUsage = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object -First 1
    $mmKey = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -ErrorAction SilentlyContinue
    $pfAllocMB = if ($null -ne $pfUsage) { [int]$pfUsage.AllocatedBaseSize } else { 0 }
    $pagefileEnabled = ($pfAllocMB -gt 0) -or ($null -ne $mmKey.ExistingPageFiles -and $mmKey.ExistingPageFiles.Count -gt 0)
    return [PSCustomObject]@{
        MemoryCompressionActive = $mcActive; CompressedWorkingSetMB = if ($mcWsBytes -gt 0) { [math]::Round($mcWsBytes / 1MB, 1) } else { 0.0 }
        PagefileEnabled = $pagefileEnabled; PagefileSufficient = ($pfAllocMB -ge 4096)
        PagefileAllocatedMB = $pfAllocMB; PagefileCurrentUsageMB = if ($null -ne $pfUsage) { [int]$pfUsage.CurrentUsage } else { 0 }; MMAgentUpdated = $mmChanged
    }
}

$BackgroundPinTargets = @(
    "steamwebhelper", "Discord", "chrome", "msedge", "msedgewebview2", "brave", "firefox",
    "SearchHost", "Widgets", "OneDrive", "EpicWebHelper", "UnrealCEFSubProcess_3071", "UnrealCEFSubProcess", "CoherentUI_Host"
)

function Set-BackgroundProcessesToECores {
    param([uint64]$PinMask = 0, [object[]]$ExistingRecords = @(), [Alias("DryRun")][bool]$IsDryRun = $false)
    $topo = [PubgIrisXeNative]::DetectTopology(); if ($PinMask -eq 0) { $PinMask = $topo.BackgroundPinMask }
    $saved = @(); if ($PinMask -eq 0) { return $saved }
    $existingByPid = @{}; if ($null -ne $ExistingRecords) { foreach ($r in $ExistingRecords) { if ($null -ne $r -and $null -ne $r.Id) { $existingByPid["$($r.Id):$($r.ProcessName)"] = $r } } }
    $qosSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][PubgIrisXeNative+PROCESS_POWER_THROTTLING_STATE])
    foreach ($name in $BackgroundPinTargets) {
        foreach ($p in [System.Diagnostics.Process]::GetProcessesByName($name)) {
            try {
                $curMask = [uint64]$p.ProcessorAffinity.ToInt64(); $curPrio = [string]$p.PriorityClass; $key = "$($p.Id):$($p.ProcessName)"
                $oldMask = if ($existingByPid.ContainsKey($key) -and [uint64]$existingByPid[$key].OriginalMask -gt 0 -and [uint64]$existingByPid[$key].OriginalMask -ne $PinMask) { [uint64]$existingByPid[$key].OriginalMask } elseif ($curMask -eq $PinMask -or $curMask -eq 0) { $topo.AllProcessorsMask } else { $curMask }
                $oldPrio = if ($existingByPid.ContainsKey($key) -and $existingByPid[$key].OriginalPrio -and $existingByPid[$key].OriginalPrio -ne "BelowNormal") { [string]$existingByPid[$key].OriginalPrio } elseif ($curPrio -eq "BelowNormal") { "Normal" } else { $curPrio }
                $qosState = New-Object PubgIrisXeNative+PROCESS_POWER_THROTTLING_STATE
                $qosState.Version = [PubgIrisXeNative]::PROCESS_POWER_THROTTLING_CURRENT_VERSION
                $gotQos = [PubgIrisXeNative]::GetProcessInformation($p.Handle, [PubgIrisXeNative]::ProcessPowerThrottling, [ref]$qosState, $qosSize)
                $oldEcoCtrl  = if ($existingByPid.ContainsKey($key) -and $null -ne $existingByPid[$key].OriginalEcoControlMask) { [uint32]$existingByPid[$key].OriginalEcoControlMask } elseif ($gotQos) { [uint32]$qosState.ControlMask } else { [uint32]0 }
                $oldEcoState = if ($existingByPid.ContainsKey($key) -and $null -ne $existingByPid[$key].OriginalEcoStateMask)   { [uint32]$existingByPid[$key].OriginalEcoStateMask }   elseif ($gotQos) { [uint32]$qosState.StateMask }   else { [uint32]0 }
                $qosMask = if ($p.ProcessName -match '^(?i)Discord$') { [uint32]0x1 } else { [uint32]0x5 }
                if (-not $IsDryRun) {
                    $p.ProcessorAffinity = [IntPtr]([int64]$PinMask)
                    if ($p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::Idle) { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal }
                    [void][PubgIrisXeNative]::SetEcoQoSAndTimerThrottle($p.Handle, $qosMask, $qosMask)
                }
                $saved += [ordered]@{ Id = $p.Id; ProcessName = $p.ProcessName; OriginalMask = $oldMask; OriginalPrio = $oldPrio; EcoQoSMask = $qosMask; OriginalEcoControlMask = $oldEcoCtrl; OriginalEcoStateMask = $oldEcoState }
            } catch {} finally { $p.Dispose() }
        }
    }
    return $saved
}

function Restore-BackgroundProcessesAffinity {
    param([object[]]$PinnedRecords = @(), [Alias("DryRun")][bool]$IsDryRun = $false)
    if ($IsDryRun) { return }
    $topo = [PubgIrisXeNative]::DetectTopology()
    $restoredIds = @{}
    if ($null -ne $PinnedRecords -and @($PinnedRecords).Count -gt 0) {
        foreach ($rec in $PinnedRecords) {
            if ($null -eq $rec -or $null -eq $rec.Id) { continue }
            $lp = $null
            try {
                $lp = Get-Process -Id ([int]$rec.Id) -ErrorAction SilentlyContinue
                if ($null -ne $lp -and $lp.ProcessName -eq $rec.ProcessName) {
                    $rMask = if ($rec.OriginalMask -gt 0 -and [uint64]$rec.OriginalMask -ne $topo.BackgroundPinMask) { [uint64]$rec.OriginalMask } else { $topo.AllProcessorsMask }
                    $rPrio = if ($rec.OriginalPrio -and ($rec.OriginalPrio -as [System.Diagnostics.ProcessPriorityClass])) { [System.Diagnostics.ProcessPriorityClass]$rec.OriginalPrio } else { [System.Diagnostics.ProcessPriorityClass]::Normal }
                    $lp.ProcessorAffinity = [IntPtr]([int64]$rMask)
                    if ($lp.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::Idle) { $lp.PriorityClass = $rPrio }
                    $origCtrl  = if ($null -ne $rec.OriginalEcoControlMask) { [uint32]$rec.OriginalEcoControlMask } else { [uint32]0 }
                    $origState = if ($null -ne $rec.OriginalEcoStateMask)   { [uint32]$rec.OriginalEcoStateMask }   else { [uint32]0 }
                    [void][PubgIrisXeNative]::SetEcoQoSAndTimerThrottle($lp.Handle, [uint32]0x5, [uint32]0)
                    [void][PubgIrisXeNative]::SetEcoQoSAndTimerThrottle($lp.Handle, $origCtrl, $origState)
                    $restoredIds[[int]$lp.Id] = $true
                }
            } catch {} finally { if ($null -ne $lp) { $lp.Dispose() } }
        }
        return
    }
    foreach ($name in $BackgroundPinTargets) {
        foreach ($p in [System.Diagnostics.Process]::GetProcessesByName($name)) {
            try {
                if ($restoredIds.ContainsKey($p.Id)) { continue }
                if ([uint64]$p.ProcessorAffinity.ToInt64() -eq $topo.BackgroundPinMask) {
                    $p.ProcessorAffinity = [IntPtr]([int64]$topo.AllProcessorsMask)
                    if ($p.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::BelowNormal) { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal }
                    [void][PubgIrisXeNative]::SetEcoQoSAndTimerThrottle($p.Handle, [uint32]0x5, [uint32]0)
                    [void][PubgIrisXeNative]::SetEcoQoSAndTimerThrottle($p.Handle, 0, 0)
                }
            } catch {} finally { $p.Dispose() }
        }
    }
}
