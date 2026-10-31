# Auto-configure active network adapters DNS (ECS-preserving Google DNS 8.8.8.8/8.8.4.4 + Win11 DoH),
# validate Coherent GT cache, race multi-region PUBG CDN IPs in parallel using 512 KB chunks,
# and verify Steam + PUBG endpoints in parallel.
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

function Start-CdnRaceProbes {
    param(
        [string[]]$CandidateIps,
        [string]$MainJsPath
    )
    foreach ($ip in $CandidateIps) {
        [PSCustomObject]@{
            IP = $ip
            Process = Start-CurlProbe -Arguments "-s -k -o NUL -r 0-524287 -w `"%{http_code}|%{size_download}|%{time_total}`" --connect-timeout 1 --max-time 2 --resolve `"prod-live-front.playbattlegrounds.com:443:$ip`" `"https://prod-live-front.playbattlegrounds.com$MainJsPath`""
            Done = $false
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

    while ($raceSw.ElapsedMilliseconds -lt 2100) {
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
                            $validPayload = ($parts[0] -eq "206" -and $dlSize -ge 500000) -or ($parts[0] -eq "200" -and $dlSize -ge 50000)
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
        if ($allDone -or ($winnerFoundAt -gt 0L -and ($raceSw.ElapsedMilliseconds - $winnerFoundAt) -ge 80)) {
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

    # 1. Read hosts file safely and launch batched Steam -Z probe + 7 CDN race probes immediately
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

    $curatedPool = @(
        "43.174.32.224",  # Singapore (Tencent Edge)
        "43.152.143.98",  # Singapore/HK (Tencent Edge)
        "43.168.152.146", # Singapore
        "43.175.115.189", # Hong Kong
        "43.174.32.194",  # Singapore
        "23.66.150.216",  # Akamai SEA
        "104.69.151.226"  # Akamai SEA
    )
    $candidateIps = @(
        if ($currentPinnedIp) { $currentPinnedIp }
        $curatedPool
    ) | Select-Object -Unique | Select-Object -First 7

    $mainJsPath = "/app/pc-2610-202/main.cb4691e73a746a46.js"

    $steamProbe = Start-SteamParallelProbe
    $cdnProbes = @(Start-CdnRaceProbes -CandidateIps $candidateIps -MainJsPath $mainJsPath)

    # 2. Fast-path DNS + Native Windows 11 DoH on active physical network adapters (.NET Registry fast path)
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

    # 3. Run local maintenance while network probes are in flight
    # 3a. Close any previous orphaned elevated cmd.exe status windows
    try {
        $cmdProcs = @(([wmisearcher]"SELECT ProcessId, ParentProcessId, CommandLine FROM Win32_Process WHERE Name='cmd.exe' OR ProcessId=$PID").Get())
        $myParentPid = ($cmdProcs | Where-Object { $_.ProcessId -eq $PID } | Select-Object -First 1).ParentProcessId
        foreach ($cp in $cmdProcs) {
            if ($cp.ProcessId -ne $PID -and $cp.ProcessId -ne $myParentPid -and $cp.CommandLine -match 'goodbyedpi_(on|off)\.cmd') {
                Stop-Process -Id $cp.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    # 3b. Surgical Coherent GT Cache (CohCache) Integrity Validator & Auto-Repair (.NET fast path)
    $cohCacheDir = Join-Path $env:LOCALAPPDATA "TslGame\Saved\CohCache"
    if ([System.IO.Directory]::Exists($cohCacheDir)) {
        $repairedCount = 0
        $dirInfo = [System.IO.DirectoryInfo]::new($cohCacheDir)
        $allFiles = $dirInfo.GetFiles()
        $byName = @{}
        foreach ($f in $allFiles) { $byName[$f.Name] = $f }

        foreach ($f in $allFiles) {
            if ($f.Extension -eq '.hdr') {
                $ctxName = [System.IO.Path]::ChangeExtension($f.Name, '.ctx')
                $ctxFile = $byName[$ctxName]
                $corrupt = $false
                if ($f.Length -eq 0 -or $null -eq $ctxFile -or $ctxFile.Length -eq 0) {
                    $corrupt = $true
                } else {
                    try {
                        $headLines = [System.IO.File]::ReadAllLines($f.FullName)
                        if ($headLines.Count -lt 2) {
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
                }
            } elseif ($f.Extension -eq '.ctx') {
                $hdrName = [System.IO.Path]::ChangeExtension($f.Name, '.hdr')
                if (-not $byName.ContainsKey($hdrName)) {
                    try { $f.Delete() } catch {}
                    $repairedCount++
                }
            }
        }
        if ($repairedCount -gt 0) {
            Write-Host "  [+] Da don dep $repairedCount file cache Coherent GT bi loi/dut quang."
        }
    }

    # 3c. Fast-path Scheduled Task maintenance (only invoke Set-ScheduledTask when needed)
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

    # 4. Collect parallel 512 KB CDN benchmark results (with Wave 2 fallback only when Wave 1 fails)
    $raceResult = Wait-CdnRaceProbes -Probes $cdnProbes -PinnedIp $currentPinnedIp

    if (-not $raceResult.BestIp) {
        $discoveryIps = @(
            if ($raceResult.AliveIp) { $raceResult.AliveIp }
            $candidateIps
        ) | Where-Object { $_ } | Select-Object -Unique

        $discoveredPath = $null
        foreach ($dIp in $discoveryIps) {
            $htmlToCheck = (& $curlExe -s -k --connect-timeout 1 --max-time 2 --resolve "prod-live-front.playbattlegrounds.com:443:$dIp" "https://prod-live-front.playbattlegrounds.com/index.html") -join "`n"
            if (($htmlToCheck -join "`n") -match '(/app/[^"'']+/index\.html)') {
                $appIndexPath = $Matches[1]
                $appDir = $appIndexPath -replace '/index\.html$', ''
                $appHtml = (& $curlExe -s -k --connect-timeout 1 --max-time 2 --resolve "prod-live-front.playbattlegrounds.com:443:$dIp" "https://prod-live-front.playbattlegrounds.com$appIndexPath") -join "`n"
                if (($appHtml -join "`n") -match '(/app/[^"'']+/js/main\.[^"'']+\.js)') {
                    $discoveredPath = $Matches[1]
                    break
                } elseif (($appHtml -join "`n") -match '((?:js/)?main\.[a-f0-9]+\.js)') {
                    $discoveredPath = "$appDir/$($Matches[1])"
                    break
                }
            }
        }

        if ($discoveredPath -and $discoveredPath -ne $mainJsPath) {
            $mainJsPath = $discoveredPath
            try {
                $selfText = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
                $updatedSelf = $selfText -replace '\$mainJsPath\s*=\s*"/app/[^"]+"', "`$mainJsPath = `"$mainJsPath`""
                if ($updatedSelf -ne $selfText) {
                    [System.IO.File]::WriteAllText($PSCommandPath, $updatedSelf, (New-Object System.Text.UTF8Encoding($false)))
                }
            } catch {}
            $retryProbes = @(Start-CdnRaceProbes -CandidateIps $candidateIps -MainJsPath $mainJsPath)
            $raceResult = Wait-CdnRaceProbes -Probes $retryProbes -PinnedIp $currentPinnedIp
        }
    }

    $bestIp = $raceResult.BestIp
    $bestTime = $raceResult.BestTime
    $bestHttp = $raceResult.BestHttp

    # Apply 40 ms hysteresis band so currentPinnedIp is kept when within 40 ms of the winner
    if ($bestIp -and $currentPinnedIp -and $pinnedLineCount -eq 1 -and $raceResult.PinnedIpTime -lt 999.0) {
        if (($raceResult.PinnedIpTime - $bestTime) -le 0.040) {
            $bestIp = $currentPinnedIp
            $bestTime = $raceResult.PinnedIpTime
            $bestHttp = $raceResult.PinnedIpHttp
        }
    }

    # 5. Atomically update C:\Windows\System32\drivers\etc\hosts (or unpin dead IPs if all probes failed)
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

    # 6. Collect and display batched parallel endpoint verification results
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
        Write-Host ("  - PUBG Lobby 512KB (prod-live-front)   : HTTP {0} | IP: {1,-15} | Time: {2}s" -f $bestHttp, $bestIp, $btStr)
    } else {
        Write-Host "  - PUBG Lobby 512KB (prod-live-front)   : KHONG TIM THAY IP CDN PHU HOP (Da chuyen ve Google DNS)"
    }
} finally {
    if ($hasMutex) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    try { $mutex.Dispose() } catch {}
}
