$ErrorActionPreference = 'SilentlyContinue'
$baseDir = $PSScriptRoot
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$curlExe = if ([System.IO.File]::Exists("$env:SystemRoot\System32\curl.exe")) { "$env:SystemRoot\System32\curl.exe" } else { "curl.exe" }

function Get-HklmValue {
    param(
        [string]$SubKey,
        [string]$ValueName
    )
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey, $false)
    if ($null -ne $k) {
        try { return $k.GetValue($ValueName, $null) } finally { $k.Dispose() }
    }
    return $null
}

function Get-UrlMd5Hex {
    param([string]$Url)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Url)
        return ([System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally {
        $md5.Dispose()
    }
}

function Start-CurlProbe {
    param([string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curlExe
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $false
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Start-SteamParallelProbe {
    $steamArgs = "-Z -s --connect-timeout 2 --max-time 3.5 -o NUL -w `"0|%{http_code}|%{remote_ip}|%{time_total}`n`" `"https://store.steampowered.com/`" --next -s --connect-timeout 2 --max-time 3.5 -o NUL -w `"1|%{http_code}|%{remote_ip}|%{time_total}`n`" `"https://steamcommunity.com/`" --next -s --connect-timeout 2 --max-time 3.5 -o NUL -w `"2|%{http_code}|%{remote_ip}|%{time_total}`n`" `"https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/`""
    return (Start-CurlProbe -Arguments $steamArgs)
}

function Resolve-LivePubgBundle {
    param(
        [string[]]$ProbeIps,
        [string]$CohCacheDir,
        [string]$FallbackMainJsPath
    )
    $discoveredMainJs = $null
    $discoveredAppDir = $null
    $discoveredAssets = @()
    $aliveIp = $null

    $topIps = @($ProbeIps | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 4)
    $idxProbes = @()
    foreach ($ip in $topIps) {
        $idxProbes += [PSCustomObject]@{
            IP      = $ip
            Process = Start-CurlProbe -Arguments "-s -k --connect-timeout 1 --max-time 2.0 --resolve `"prod-live-front.playbattlegrounds.com:443:$ip`" `"https://prod-live-front.playbattlegrounds.com/index.html`""
            Done    = $false
        }
    }

    $appIndexPath = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 2100 -and -not $appIndexPath) {
        $allDone = $true
        foreach ($p in $idxProbes) {
            if (-not $p.Done) {
                if ($p.Process.HasExited) {
                    $p.Done = $true
                    $html = $p.Process.StandardOutput.ReadToEnd()
                    if ($html -notmatch 'playbattlegrounds\.com\.cn' -and $html -match '(/app/pc-[^"''?\s]+/index\.html)') {
                        $appIndexPath = $Matches[1]
                        $aliveIp = $p.IP
                        break
                    }
                } else {
                    $allDone = $false
                }
            }
        }
        if ($allDone -or $appIndexPath) { break }
        Start-Sleep -Milliseconds 15
    }
    foreach ($p in $idxProbes) {
        if ($p.Process) {
            if (-not $p.Process.HasExited) { try { $p.Process.Kill() } catch {} }
            try { $p.Process.Dispose() } catch {}
        }
    }

    if ($appIndexPath -and $aliveIp) {
        $discoveredAppDir = $appIndexPath -replace '/index\.html$', ''
        $fbMatchesDir = $FallbackMainJsPath.StartsWith("$discoveredAppDir/")
        $fbHash = Get-UrlMd5Hex -Url "https://prod-live-front.playbattlegrounds.com$FallbackMainJsPath"
        $fbCached = $CohCacheDir -and [System.IO.File]::Exists((Join-Path $CohCacheDir "$fbHash.hdr"))
        if ($fbMatchesDir -and $fbCached) {
            $discoveredMainJs = $FallbackMainJsPath
            $discoveredAssets = @($FallbackMainJsPath)
        } else {
            $appHtmlProc = Start-CurlProbe -Arguments "-s -k --connect-timeout 1 --max-time 2.0 --resolve `"prod-live-front.playbattlegrounds.com:443:$aliveIp`" `"https://prod-live-front.playbattlegrounds.com$appIndexPath`""
            if ($appHtmlProc) {
                try {
                    $appHtml = $appHtmlProc.StandardOutput.ReadToEnd()
                    $appHtmlProc.WaitForExit(2100) | Out-Null
                    if ($appHtml -match '(/app/[^"'']+/js/main\.[^"'']+\.js)') {
                        $discoveredMainJs = $Matches[1]
                    } elseif ($appHtml -match '((?:js/)?main\.[a-f0-9]+\.js)') {
                        $discoveredMainJs = "$discoveredAppDir/$($Matches[1])"
                    }
                    foreach ($assetMatch in [regex]::Matches($appHtml, '(?:href|src)="([^"]+)"')) {
                        $rel = $assetMatch.Groups[1].Value -replace '^\./', ''
                        if ($rel -and $rel -notmatch '^https?://' -and $rel -match '\.(js|css)$') {
                            $fullAssetPath = if ($rel.StartsWith('/')) { $rel } else { "$discoveredAppDir/$rel" }
                            if ($discoveredAssets -notcontains $fullAssetPath) {
                                $discoveredAssets += $fullAssetPath
                            }
                        }
                    }
                } catch {}
                try { $appHtmlProc.Dispose() } catch {}
            }
        }
    }

    if (-not $discoveredMainJs) {
        $discoveredMainJs = $FallbackMainJsPath
    }
    if (-not $discoveredAppDir -and $discoveredMainJs -match '^(/app/[^/]+)/') {
        $discoveredAppDir = $Matches[1]
    }
    if ($discoveredAssets.Count -eq 0 -and $discoveredMainJs) {
        $discoveredAssets = @($discoveredMainJs)
    }

    return [PSCustomObject]@{
        MainJsPath = $discoveredMainJs
        AppDir     = $discoveredAppDir
        Assets     = $discoveredAssets
        AliveIp    = $aliveIp
    }
}

function Start-CdnRaceProbes {
    param(
        [string[]]$CandidateIps,
        [string]$MainJsPath
    )
    foreach ($ip in $CandidateIps) {
        [PSCustomObject]@{
            IP      = $ip
            Process = Start-CurlProbe -Arguments "-s -k -o NUL -r 0-2097151 -w `"%{http_code}|%{size_download}|%{time_total}`" --connect-timeout 1.5 --max-time 5 --resolve `"prod-live-front.playbattlegrounds.com:443:$ip`" `"https://prod-live-front.playbattlegrounds.com$MainJsPath`""
            Done    = $false
        }
    }
}

function Wait-CdnRaceProbes {
    param(
        [object[]]$Probes,
        [string]$PinnedIp
    )
    $bestIp = $null
    $bestTime = 999.0
    $bestHttp = "000"
    $pinnedIpTime = 999.0
    $pinnedIpHttp = "000"
    $aliveIp = $null
    $raceSw = [System.Diagnostics.Stopwatch]::StartNew()
    $winnerFoundAt = 0L

    while ($raceSw.ElapsedMilliseconds -lt 5100) {
        $allDone = $true
        foreach ($p in $Probes) {
            if (-not $p.Done) {
                if ($p.Process.HasExited) {
                    $p.Done = $true
                    $out = $p.Process.StandardOutput.ReadToEnd().Trim()
                    $parts = $out -split '\|'
                    if ($parts.Count -eq 3) {
                        if (-not $aliveIp -and $parts[0] -match '^(200|206|301|302|403|404)$') {
                            $aliveIp = $p.IP
                        }
                        if ($parts[0] -eq "206" -or $parts[0] -eq "200") {
                            $dlSize = 0L
                            [long]::TryParse($parts[1], [ref]$dlSize) | Out-Null
                            $t = 999.0
                            $tOk = [double]::TryParse(($parts[2] -replace ',', '.'), [System.Globalization.NumberStyles]::Float, $inv, [ref]$t)
                            $validPayload = ($parts[0] -eq "206" -and $dlSize -ge 1500000) -or ($parts[0] -eq "200" -and $dlSize -ge 1500000)
                            if ($tOk -and $validPayload -and $t -gt 0.0) {
                                if ($PinnedIp -and $p.IP -eq $PinnedIp) {
                                    $pinnedIpTime = $t
                                    $pinnedIpHttp = $parts[0]
                                }
                                if ($t -lt $bestTime) {
                                    $bestTime = $t
                                    $bestIp = $p.IP
                                    $bestHttp = $parts[0]
                                    if ($winnerFoundAt -eq 0L) {
                                        $winnerFoundAt = $raceSw.ElapsedMilliseconds
                                    }
                                }
                            }
                        }
                    }
                } else {
                    $allDone = $false
                }
            }
        }
        if ($allDone -or ($winnerFoundAt -gt 0L -and ($raceSw.ElapsedMilliseconds - $winnerFoundAt) -ge 250)) {
            break
        }
        Start-Sleep -Milliseconds 15
    }

    foreach ($p in $Probes) {
        if ($p.Process) {
            if (-not $p.Process.HasExited) {
                try { $p.Process.Kill() } catch {}
            }
            try { $p.Process.Dispose() } catch {}
        }
    }

    return [PSCustomObject]@{
        BestIp       = $bestIp
        BestTime     = $bestTime
        BestHttp     = $bestHttp
        PinnedIpTime = $pinnedIpTime
        PinnedIpHttp = $pinnedIpHttp
        AliveIp      = $aliveIp
    }
}

function Save-CohCacheAssetFromCdn {
    param(
        [string]$AssetPath,
        [string]$CdnIp,
        [string]$CohCacheDir
    )
    if (-not $AssetPath -or -not $CdnIp -or -not $CohCacheDir) { return $false }
    if (-not [System.IO.Directory]::Exists($CohCacheDir)) {
        try { [System.IO.Directory]::CreateDirectory($CohCacheDir) | Out-Null } catch { return $false }
    }
    $url = "https://prod-live-front.playbattlegrounds.com$AssetPath"
    $hash = Get-UrlMd5Hex -Url $url
    $hdrPath = Join-Path $CohCacheDir "$hash.hdr"
    $ctxPath = Join-Path $CohCacheDir "$hash.ctx"
    if ([System.IO.File]::Exists($hdrPath) -and [System.IO.File]::Exists($ctxPath) -and ([System.IO.FileInfo]::new($ctxPath).Length -gt 0)) {
        return $true
    }

    $tmpCtx = Join-Path $CohCacheDir "$hash.ctx.tmp"
    $tmpHdr = Join-Path $CohCacheDir "$hash.hdr.tmp"
    try {
        & $curlExe -s -k --connect-timeout 2 --max-time 12 -D $tmpHdr -o $tmpCtx --resolve "prod-live-front.playbattlegrounds.com:443:$CdnIp" $url | Out-Null
        if (-not [System.IO.File]::Exists($tmpCtx) -or -not [System.IO.File]::Exists($tmpHdr)) { return $false }
        $ctxLen = [System.IO.FileInfo]::new($tmpCtx).Length
        if ($ctxLen -le 0) { return $false }
        $rawHdrLines = [System.IO.File]::ReadAllLines($tmpHdr)
        $statusOk = $false
        $headerLines = New-Object System.Collections.Generic.List[string]
        foreach ($hl in $rawHdrLines) {
            $trimmed = $hl.Trim()
            if ($trimmed -match '^HTTP/\d(?:\.\d)?\s+(\d{3})') {
                $statusOk = ($Matches[1] -eq '200')
                $headerLines.Clear()
            } elseif ($trimmed.Length -gt 0) {
                $headerLines.Add($trimmed)
            }
        }
        if (-not $statusOk) { return $false }
        $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $expEpoch = $nowEpoch + 86400
        $outLines = New-Object System.Collections.Generic.List[string]
        $outLines.Add("200")
        $outLines.Add("$ctxLen")
        $outLines.Add("$expEpoch")
        $outLines.Add("$nowEpoch")
        foreach ($hLine in $headerLines) { $outLines.Add($hLine) }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::Move($tmpCtx, $ctxPath)
        [System.IO.File]::WriteAllText($hdrPath, (($outLines -join "`n") + "`n"), $utf8NoBom)
        return $true
    } catch {
        return $false
    } finally {
        if ([System.IO.File]::Exists($tmpCtx)) { try { [System.IO.File]::Delete($tmpCtx) } catch {} }
        if ([System.IO.File]::Exists($tmpHdr)) { try { [System.IO.File]::Delete($tmpHdr) } catch {} }
    }
}

function Read-HostsSafely {
    param([string]$Path)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
            return [PSCustomObject]@{ Success = $true; Lines = [string[]]@($lines) }
        } catch {
            Start-Sleep -Milliseconds 40
        }
    }
    return [PSCustomObject]@{ Success = $false; Lines = [string[]]@() }
}

function Write-HostsSafely {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [System.IO.File]::WriteAllLines($Path, [string[]]@($Lines), $utf8NoBom)
            return $true
        } catch [System.UnauthorizedAccessException] {
            return $false
        } catch {
            Start-Sleep -Milliseconds 40
        }
    }
    return $false
}

$mutex = New-Object System.Threading.Mutex($false, "Global\GoodbyeDPI_Toolkit_Mutex")
$hasMutex = $false
try {
    try {
        $hasMutex = $mutex.WaitOne(10000)
    } catch [System.Threading.AbandonedMutexException] {
        $hasMutex = $true
    }

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsData = Read-HostsSafely -Path $hostsPath
    $currentPinnedIp = $null
    $pinnedLineCount = 0
    if ($hostsData.Success) {
        foreach ($line in $hostsData.Lines) {
            if ($line -match '^\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s+prod-live-front\.playbattlegrounds\.com\b') {
                if (-not $currentPinnedIp) { $currentPinnedIp = $Matches[1] }
                $pinnedLineCount++
            } elseif ($line -match 'prod-live-front\.playbattlegrounds\.com') {
                $pinnedLineCount++
            }
        }
    }

    # Tencent COS 43.* IPs redirect GET /?provider=steam to playbattlegrounds.com.cn and poison Global/SEA CohCache hashes.
    $curatedPool = @(
        "3.162.66.12",
        "3.162.66.99",
        "108.157.32.117",
        "108.157.32.60",
        "108.157.254.53",
        "23.66.150.216",
        "104.69.151.226"
    )
    $candidateIps = @(
        if ($currentPinnedIp -and $currentPinnedIp -notmatch '^43\.') { $currentPinnedIp }
        $curatedPool
    ) | Select-Object -Unique | Select-Object -First 7

    $cohCacheDir = Join-Path $env:LOCALAPPDATA "TslGame\Saved\CohCache"
    $fallbackMainJsPath = "/app/pc-2611-128/main.fd13ca214153224b.js"

    $steamProbe = Start-SteamParallelProbe
    $bundleInfo = Resolve-LivePubgBundle -ProbeIps $candidateIps -CohCacheDir $cohCacheDir -FallbackMainJsPath $fallbackMainJsPath
    $mainJsPath = $bundleInfo.MainJsPath

    if ($mainJsPath -and $mainJsPath -ne $fallbackMainJsPath) {
        try {
            $selfText = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
            $updatedSelf = $selfText -replace '\$fallbackMainJsPath\s*=\s*"/app/[^"]+"', "`$fallbackMainJsPath = `"$mainJsPath`""
            if ($updatedSelf -ne $selfText) {
                [System.IO.File]::WriteAllText($PSCommandPath, $updatedSelf, (New-Object System.Text.UTF8Encoding($false)))
            }
        } catch {}
    }

    $cdnProbes = @(Start-CdnRaceProbes -CandidateIps $candidateIps -MainJsPath $mainJsPath)

    $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
        $_.OperationalStatus -eq 'Up' -and
        $_.NetworkInterfaceType -ne 'Loopback' -and
        $_.NetworkInterfaceType -ne 'Tunnel' -and
        $_.Description -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback'
    }

    $dnsChanged = $false
    $dohServerConfigured = $false

    foreach ($nic in $nics) {
        $name = $nic.Name
        $guid = $nic.Id
        $v4SubKey = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        $v6SubKey = "SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid"
        $v4Servers = Get-HklmValue -SubKey $v4SubKey -ValueName "NameServer"
        $v6Servers = Get-HklmValue -SubKey $v6SubKey -ValueName "NameServer"

        $dohSubBase = "SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$guid\DohInterfaceSettings\Doh"
        $doh8888 = Get-HklmValue -SubKey "$dohSubBase\8.8.8.8" -ValueName "DohFlags"
        $doh8844 = Get-HklmValue -SubKey "$dohSubBase\8.8.4.4" -ValueName "DohFlags"

        if ($v4Servers -ne '8.8.8.8,8.8.4.4' -or $v6Servers -match '::1' -or $doh8888 -ne 1 -or $doh8844 -ne 1) {
            if (-not $dohServerConfigured) {
                $wkSubBase = "SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers"
                $wk8888 = Get-HklmValue -SubKey "$wkSubBase\8.8.8.8" -ValueName "Flags"
                $wk8844 = Get-HklmValue -SubKey "$wkSubBase\8.8.4.4" -ValueName "Flags"
                if ($wk8888 -ne 12 -or $wk8844 -ne 12) {
                    foreach ($dohServer in @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844')) {
                        Set-DnsClientDohServerAddress -ServerAddress $dohServer -AutoUpgrade $true -AllowFallbackToUdp $true | Out-Null
                    }
                }
                $dohServerConfigured = $true
            }

            & netsh.exe interface ipv4 set dnsservers name="$name" static 8.8.8.8 primary validate=no | Out-Null
            & netsh.exe interface ipv4 add dnsservers name="$name" 8.8.4.4 index=2 validate=no | Out-Null
            & netsh.exe interface ipv6 set dnsservers name="$name" dhcp | Out-Null

            if ($guid) {
                $dohBase = "HKLM:\$dohSubBase"
                foreach ($staleIp in @('1.1.1.1', '1.0.0.1', '::1')) {
                    if (Test-Path "$dohBase\$staleIp") {
                        Remove-Item -Path "$dohBase\$staleIp" -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                foreach ($dnsIp in @('8.8.8.8', '8.8.4.4')) {
                    $regPath = "$dohBase\$dnsIp"
                    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                    New-ItemProperty -Path $regPath -Name "DohFlags" -Value 1 -PropertyType QWord -Force | Out-Null
                }
            }
            $dnsChanged = $true
        }
    }

    if ($dnsChanged) {
        & ipconfig.exe /flushdns | Out-Null
        if ($steamProbe) {
            if (-not $steamProbe.HasExited) { try { $steamProbe.Kill() } catch {} }
            try { $steamProbe.Dispose() } catch {}
        }
        $steamProbe = Start-SteamParallelProbe
    }

    try {
        $cmdProcs = @(([wmisearcher]"SELECT ProcessId, ParentProcessId, CommandLine FROM Win32_Process WHERE Name='cmd.exe' OR ProcessId=$PID").Get())
        $myParentPid = ($cmdProcs | Where-Object { $_.ProcessId -eq $PID } | Select-Object -First 1).ParentProcessId
        foreach ($cp in $cmdProcs) {
            if ($cp.ProcessId -ne $PID -and $cp.ProcessId -ne $myParentPid -and $cp.CommandLine -match 'goodbyedpi_(on|off)\.cmd') {
                Stop-Process -Id $cp.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    try {
        $runKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Run", $true)
        if ($null -ne $runKey) {
            try {
                foreach ($warpVal in @("Cloudflare WARP", "CloudflareWARP")) {
                    if ($null -ne $runKey.GetValue($warpVal, $null)) {
                        $runKey.DeleteValue($warpVal, $false)
                    }
                }
            } finally {
                $runKey.Dispose()
            }
        }
        $warpSvc = Get-Service -Name "CloudflareWARP" -ErrorAction SilentlyContinue
        if ($null -eq $warpSvc -or $warpSvc.Status -ne "Running") {
            $warpUpd = Get-Service -Name "CloudflareWARPUpdater" -ErrorAction SilentlyContinue
            if ($null -ne $warpUpd) {
                if ($warpUpd.StartType -ne "Manual") { Set-Service -Name "CloudflareWARPUpdater" -StartupType Manual -ErrorAction SilentlyContinue }
                if ($warpUpd.Status -eq "Running") { Stop-Service -Name "CloudflareWARPUpdater" -Force -ErrorAction SilentlyContinue }
            }
            Stop-Process -Name "warp-updater-armed" -Force -ErrorAction SilentlyContinue
            Stop-Process -Name "Cloudflare WARP" -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    try {
        foreach ($exeName in @("TslGame.exe", "TslGame_ZK.exe", "TslGame_BE.exe", "ExecPubg.exe")) {
            $ifeoSub = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exeName\PerfOptions"
            $curPrio = Get-HklmValue -SubKey $ifeoSub -ValueName "CpuPriorityClass"
            if ($curPrio -ne 3) {
                $pk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($ifeoSub, $true)
                if ($null -ne $pk) {
                    try { $pk.SetValue("CpuPriorityClass", 3, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $pk.Dispose() }
                }
            }
        }

        $tslIfeoSub = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\TslGame.exe\PerfOptions"
        $defVer = Get-HklmValue -SubKey $tslIfeoSub -ValueName "DefenderExclusionsV2"
        if ($defVer -ne 2) {
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
            $pk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($tslIfeoSub, $true)
            if ($null -ne $pk) {
                try { $pk.SetValue("DefenderExclusionsV2", 2, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $pk.Dispose() }
            }
        }
    } catch {}

    $liveMainJsHash = Get-UrlMd5Hex -Url "https://prod-live-front.playbattlegrounds.com$mainJsPath"
    $liveBundleCached = $false
    if ([System.IO.Directory]::Exists($cohCacheDir)) {
        $repairedCount = 0
        $refreshedCount = 0
        $dirInfo = [System.IO.DirectoryInfo]::new($cohCacheDir)
        $allFiles = $dirInfo.GetFiles()
        $byName = @{}
        foreach ($f in $allFiles) { $byName[$f.Name] = $f }

        $validHdrList = New-Object System.Collections.Generic.List[object]

        foreach ($f in $allFiles) {
            if ($f.Extension -eq '.hdr') {
                $ctxName = [System.IO.Path]::ChangeExtension($f.Name, '.ctx')
                $ctxFile = $byName[$ctxName]
                $corrupt = $false
                $headLines = $null
                if ($f.Length -eq 0 -or $null -eq $ctxFile -or $ctxFile.Length -eq 0) {
                    $corrupt = $true
                } else {
                    try {
                        $headLines = [System.IO.File]::ReadAllLines($f.FullName)
                        if ($headLines.Count -lt 4) {
                            $corrupt = $true
                        } else {
                            $status = $headLines[0].Trim()
                            $expectedLen = 0L
                            [long]::TryParse($headLines[1].Trim(), [ref]$expectedLen) | Out-Null
                            if ($status -ne "200" -or $expectedLen -le 0 -or $ctxFile.Length -ne $expectedLen) {
                                $corrupt = $true
                            }
                        }
                    } catch {
                        $corrupt = $true
                    }
                }
                if ($corrupt) {
                    try { $f.Delete() } catch {}
                    if ($null -ne $ctxFile) {
                        try { $ctxFile.Delete() } catch {}
                    }
                    $repairedCount++
                } else {
                    if ($f.Name -eq "$liveMainJsHash.hdr") {
                        $liveBundleCached = $true
                    }
                    $validHdrList.Add([PSCustomObject]@{ File = $f; Lines = $headLines })
                }
            } elseif ($f.Extension -eq '.ctx') {
                $hdrName = [System.IO.Path]::ChangeExtension($f.Name, '.hdr')
                if (-not $byName.ContainsKey($hdrName)) {
                    try { $f.Delete() } catch {}
                    $repairedCount++
                }
            }
        }

        # CoherentUI_Host.exe requires .hdr line 2 to be fetch_epoch + 86400 in UTF-8 LF without BOM.
        if ($liveBundleCached -and $validHdrList.Count -gt 0) {
            $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $newExpiry = $nowEpoch + 86400
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            foreach ($item in $validHdrList) {
                $hl = $item.Lines
                $curExp = 0L
                [long]::TryParse($hl[2].Trim(), [ref]$curExp) | Out-Null
                if ($curExp -gt 0 -and $curExp -lt ($nowEpoch + 82800)) {
                    $hl[2] = "$newExpiry"
                    $hl[3] = "$nowEpoch"
                    try {
                        [System.IO.File]::WriteAllText($item.File.FullName, (($hl -join "`n") + "`n"), $utf8NoBom)
                        $refreshedCount++
                    } catch {}
                }
            }
        }

        if ($repairedCount -gt 0) {
            Write-Host "  [+] Da don dep $repairedCount file cache Coherent GT bi loi/dut quang."
        }
        if ($refreshedCount -gt 0) {
            Write-Host "  [+] Da gia han 24h TTL cho $refreshedCount file cache Coherent GT ($($bundleInfo.AppDir))."
        }
    }

    $tasksDir = "$env:SystemRoot\System32\Tasks"
    if ([System.IO.File]::Exists("$tasksDir\GoodbyeDPI-Toggle")) {
        Unregister-ScheduledTask -TaskName 'GoodbyeDPI-Toggle' -Confirm:$false | Out-Null
    }
    foreach ($taskName in @('GoodbyeDPI-On', 'GoodbyeDPI-Off')) {
        $taskXmlPath = "$tasksDir\$taskName"
        if ([System.IO.File]::Exists($taskXmlPath)) {
            $taskXml = [System.IO.File]::ReadAllText($taskXmlPath)
            if ($taskXml -notmatch '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' -or
                $taskXml -notmatch '<MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>' -or
                $taskXml -notmatch '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' -or
                $taskXml -notmatch '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>') {
                $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel
                Set-ScheduledTask -TaskName $taskName -Settings $s | Out-Null
            }
        }
    }

    $raceResult = Wait-CdnRaceProbes -Probes $cdnProbes -PinnedIp $currentPinnedIp

    $bestIp = $raceResult.BestIp
    $bestTime = $raceResult.BestTime
    $bestHttp = $raceResult.BestHttp

    if ($bestIp -and $currentPinnedIp -and $currentPinnedIp -notmatch '^43\.' -and $pinnedLineCount -eq 1 -and $raceResult.PinnedIpTime -lt 999.0) {
        if (($raceResult.PinnedIpTime - $bestTime) -le 0.040) {
            $bestIp = $currentPinnedIp
            $bestTime = $raceResult.PinnedIpTime
            $bestHttp = $raceResult.PinnedIpHttp
        }
    }

    if ($hostsData.Success) {
        if ($bestIp) {
            if ($bestIp -ne $currentPinnedIp -or $pinnedLineCount -ne 1) {
                $cleanLines = @($hostsData.Lines | Where-Object { $_ -notmatch "prod-live-front\.playbattlegrounds\.com" })
                $cleanLines += "$bestIp prod-live-front.playbattlegrounds.com"
                if (Write-HostsSafely -Path $hostsPath -Lines $cleanLines) {
                    & ipconfig.exe /flushdns | Out-Null
                }
            }
        } elseif ($pinnedLineCount -gt 0) {
            $cleanLines = @($hostsData.Lines | Where-Object { $_ -notmatch "prod-live-front\.playbattlegrounds\.com" })
            if (Write-HostsSafely -Path $hostsPath -Lines $cleanLines) {
                & ipconfig.exe /flushdns | Out-Null
            }
        }
    }

    if (-not $liveBundleCached -and $bestIp -and $bundleInfo.Assets.Count -gt 0) {
        $warmedCount = 0
        foreach ($assetPath in $bundleInfo.Assets) {
            if (Save-CohCacheAssetFromCdn -AssetPath $assetPath -CdnIp $bestIp -CohCacheDir $cohCacheDir) {
                $warmedCount++
            }
        }
        if ($warmedCount -gt 0) {
            Write-Host "  [+] Da nap truoc $warmedCount file Lobby bundle moi ($($bundleInfo.AppDir)) vao CohCache."
        }
    }

    Write-Host ""
    Write-Host "[3/3] Ket qua verify ket noi song song den Steam va PUBG:"
    $steamLabels = @(
        "Steam Store      (store.steampowered)",
        "Steam Community  (steamcommunity.com)",
        "Steam Web API    (api.steampowered)  "
    )
    $steamResults = @{}
    if ($steamProbe) {
        $sOut = ""
        try {
            $sOut = $steamProbe.StandardOutput.ReadToEnd().Trim()
            $steamProbe.WaitForExit()
        } catch {}
        try { $steamProbe.Dispose() } catch {}
        foreach ($sLine in ($sOut -split "`r?`n")) {
            $sParts = $sLine.Trim() -split '\|'
            if ($sParts.Count -eq 4 -and $sParts[0] -match '^[012]$') {
                $steamResults[[int]$sParts[0]] = $sParts
            }
        }
    }
    for ($idx = 0; $idx -lt 3; $idx++) {
        if ($steamResults.ContainsKey($idx)) {
            $sp = $steamResults[$idx]
            $vtSec = 0.0
            [void][double]::TryParse(($sp[3] -replace ',', '.'), [System.Globalization.NumberStyles]::Float, $inv, [ref]$vtSec)
            $vtStr = $vtSec.ToString("F3", $inv)
            Write-Host ("  - {0} : HTTP {1} | IP: {2,-15} | Time: {3}s" -f $steamLabels[$idx], $sp[1], $sp[2], $vtStr)
        }
    }
    if ($bestIp) {
        $btStr = $bestTime.ToString("F3", $inv)
        Write-Host ("  - PUBG Lobby 2MB (prod-live-front)     : HTTP {0} | IP: {1,-15} | Time: {2}s" -f $bestHttp, $bestIp, $btStr)
    } else {
        Write-Host "  - PUBG Lobby 2MB (prod-live-front)     : KHONG TIM THAY IP CDN PHU HOP (Da chuyen ve Google DNS)"
    }
} finally {
    if ($hasMutex) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    try { $mutex.Dispose() } catch {}
}

Write-Host ""
if ($env:SVC_OK -eq "0") {
    Write-Host "LOI: GoodbyeDPI khong bat duoc. Chay CAI_DAT_1_CLICK.cmd de sua."
} else {
    Write-Host "========================================================================="
    Write-Host " TRANG THAI: GoodbyeDPI DANG CHAY NGAM ON DINH (Windows Service)"
    Write-Host " Luu y: GoodbyeDPI chay ngam trong Windows Services, KHONG tat khi"
    Write-Host " ban dong cua so nay. Muon tat han hay dung nut `"GoodbyeDPI TAT`"."
    Write-Host "========================================================================="
}
Write-Host ""
exit 0
