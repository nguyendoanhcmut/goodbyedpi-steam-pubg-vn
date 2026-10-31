# Auto-configure active network adapters DNS (ECS-preserving Google DNS 8.8.8.8/8.8.4.4 + Win11 DoH),
# validate Coherent GT cache, race multi-region PUBG CDN IPs in parallel using 512 KB chunks,
# and verify Steam + PUBG endpoints in parallel.
$ErrorActionPreference = 'SilentlyContinue'
$baseDir = $PSScriptRoot
$blacklistPath = Join-Path $baseDir "steam-blacklist.txt"

function Start-CurlProbe {
    param([string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "curl.exe"
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
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
    param([object[]]$Probes)
    $bestIp = $null
    $bestTime = 999.0
    $bestHttp = "000"
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
                    if ($parts.Count -eq 3 -and ($parts[0] -eq "206" -or $parts[0] -eq "200")) {
                        $dlSize = 0L
                        [long]::TryParse($parts[1], [ref]$dlSize) | Out-Null
                        $t = [double]::Parse($parts[2], [System.Globalization.CultureInfo]::InvariantCulture)
                        if ($dlSize -ge 500000 -and $t -lt $bestTime) {
                            $bestTime = $t
                            $bestIp = $p.IP
                            $bestHttp = $parts[0]
                            if ($winnerFoundAt -eq 0L) {
                                $winnerFoundAt = $raceSw.ElapsedMilliseconds
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
        if (-not $p.Process.HasExited) {
            try { $p.Process.Kill() } catch {}
        }
    }

    return [PSCustomObject]@{
        BestIp = $bestIp
        BestTime = $bestTime
        BestHttp = $bestHttp
    }
}

# 1. Fast-path DNS + Native Windows 11 DoH on active physical network adapters (8.8.8.8 / 8.8.4.4, no dead ::1)
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
    $v4RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
    $v6RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid"
    $v4Servers = (Get-ItemProperty -Path $v4RegPath -Name NameServer -ErrorAction SilentlyContinue).NameServer
    $v6Servers = (Get-ItemProperty -Path $v6RegPath -Name NameServer -ErrorAction SilentlyContinue).NameServer

    $dohBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$guid\DohInterfaceSettings\Doh"
    $doh8888 = (Get-ItemProperty -Path "$dohBase\8.8.8.8" -Name DohFlags -ErrorAction SilentlyContinue).DohFlags
    $doh8844 = (Get-ItemProperty -Path "$dohBase\8.8.4.4" -Name DohFlags -ErrorAction SilentlyContinue).DohFlags

    if ($v4Servers -ne '8.8.8.8,8.8.4.4' -or $v6Servers -match '::1' -or $doh8888 -ne 1 -or $doh8844 -ne 1) {
        if (-not $dohServerConfigured) {
            foreach ($dohServer in @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844')) {
                Set-DnsClientDohServerAddress -ServerAddress $dohServer -AutoUpgrade $true -AllowFallbackToUdp $true | Out-Null
            }
            $dohServerConfigured = $true
        }

        & netsh.exe interface ipv4 set dnsservers name="$name" static 8.8.8.8 primary validate=no | Out-Null
        & netsh.exe interface ipv4 add dnsservers name="$name" 8.8.4.4 index=2 validate=no | Out-Null
        & netsh.exe interface ipv6 set dnsservers name="$name" dhcp | Out-Null

        if ($guid) {
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
}

# 2. Build diverse 6-7 IP Asia/SEA CDN candidate pool and launch ALL network probes concurrently
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsLines = @([System.IO.File]::ReadAllLines($hostsPath))
$currentPinnedIp = $null
foreach ($line in $hostsLines) {
    if ($line -match '^\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s+prod-live-front\.playbattlegrounds\.com\b') {
        $currentPinnedIp = $Matches[1]
        break
    }
}

$curatedPool = @(
    "43.175.115.189", # Hong Kong
    "43.174.32.194",  # Singapore
    "43.168.152.146", # Singapore
    "43.133.176.62",  # Singapore
    "43.152.72.189",  # Tokyo
    "104.69.151.226"  # Akamai SEA
)
$candidateIps = @(
    $curatedPool
    if ($currentPinnedIp) { $currentPinnedIp }
) | Select-Object -Unique | Select-Object -First 7

$mainJsPath = "/app/pc-2610-202/main.cb4691e73a746a46.js"
$seedIp = $candidateIps[0]

# Launch 6-IP CDN 512 KB race, index.html discovery check, and Steam verification probes all at once
$cdnProbes = @(Start-CdnRaceProbes -CandidateIps $candidateIps -MainJsPath $mainJsPath)
$indexProbe = Start-CurlProbe -Arguments "-s -k --connect-timeout 1 --max-time 2 --resolve `"prod-live-front.playbattlegrounds.com:443:$seedIp`" `"https://prod-live-front.playbattlegrounds.com/index.html`""

$verifyTargets = @(
    [PSCustomObject]@{ Label = "Steam Store      (store.steampowered)"; Url = "https://store.steampowered.com/" },
    [PSCustomObject]@{ Label = "Steam Community  (steamcommunity.com)"; Url = "https://steamcommunity.com/" },
    [PSCustomObject]@{ Label = "Steam Web API    (api.steampowered)  "; Url = "https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/" }
)
$verifyProbes = foreach ($vt in $verifyTargets) {
    [PSCustomObject]@{
        Label = $vt.Label
        Process = Start-CurlProbe -Arguments "-s -o NUL -w `"%{http_code}|%{remote_ip}|%{time_total}`" --connect-timeout 2 --max-time 3.5 `"$($vt.Url)`""
    }
}

# 3. Run local disk/registry checks while network probes are in flight
# 3a. Surgical Coherent GT Cache (CohCache) Integrity Validator & Auto-Repair (.NET fast path)
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
            }
            if ($corrupt) {
                try { $f.Delete() } catch {}
                if ($null -ne $ctxFile) { try { $ctxFile.Delete() } catch {} }
                $repairedCount++
            }
        } elseif ($f.Extension -eq '.ctx') {
            $hdrName = [System.IO.Path]::ChangeExtension($f.Name, '.hdr')
            if ($f.Length -eq 0 -or -not $byName.ContainsKey($hdrName)) {
                try { $f.Delete() } catch {}
                $repairedCount++
            }
        }
    }
    if ($repairedCount -gt 0) {
        Write-Host "  [+] Da don dep $repairedCount file cache Coherent GT bi loi/dut quang."
    }
}

# 3b. Fast-path Scheduled Task maintenance (only invoke Set-ScheduledTask when needed)
$tasksDir = "$env:SystemRoot\System32\Tasks"
if ([System.IO.File]::Exists("$tasksDir\GoodbyeDPI-Toggle")) {
    Unregister-ScheduledTask -TaskName 'GoodbyeDPI-Toggle' -Confirm:$false | Out-Null
}
foreach ($taskName in @('GoodbyeDPI-On', 'GoodbyeDPI-Off')) {
    $taskXmlPath = "$tasksDir\$taskName"
    if ([System.IO.File]::Exists($taskXmlPath)) {
        $taskXml = [System.IO.File]::ReadAllText($taskXmlPath)
        if ($taskXml -notmatch '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' -or $taskXml -notmatch '<MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>') {
            $tObj = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($tObj -and $tObj.Actions[0].Arguments -notmatch '--nopause') {
                $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel
                Set-ScheduledTask -TaskName $taskName -Settings $s | Out-Null
            }
        }
    }
}

# 4. Collect parallel 512 KB CDN benchmark results (with dynamic main.<hash>.js fallback on game update)
$raceResult = Wait-CdnRaceProbes -Probes $cdnProbes

$rootHtml = ($indexProbe.StandardOutput.ReadToEnd()) -join "`n"
$indexProbe.WaitForExit()
if (($rootHtml -join "`n") -match '(/app/[^"'']+/index\.html)') {
    $appIndexPath = $Matches[1]
    $appDir = $appIndexPath -replace '/index\.html$', ''
    if (-not $mainJsPath.StartsWith("$appDir/") -or -not $raceResult.BestIp) {
        $appHtml = (& curl.exe -s -k --connect-timeout 1 --max-time 2 --resolve "prod-live-front.playbattlegrounds.com:443:$seedIp" "https://prod-live-front.playbattlegrounds.com$appIndexPath") -join "`n"
        if (($appHtml -join "`n") -match '(/app/[^"'']+/js/main\.[^"'']+\.js)') {
            $mainJsPath = $Matches[1]
        } elseif (($appHtml -join "`n") -match '((?:js/)?main\.[a-f0-9]+\.js)') {
            $mainJsPath = "$appDir/$($Matches[1])"
        }
        $retryProbes = @(Start-CdnRaceProbes -CandidateIps $candidateIps -MainJsPath $mainJsPath)
        $raceResult = Wait-CdnRaceProbes -Probes $retryProbes
    }
}

$bestIp = $raceResult.BestIp
$bestTime = $raceResult.BestTime
$bestHttp = $raceResult.BestHttp

# 5. Atomically update C:\Windows\System32\drivers\etc\hosts only when $bestIp is verified and changed
if ($bestIp -and $bestIp -ne $currentPinnedIp) {
    $cleanLines = @($hostsLines | Where-Object { $_ -notmatch "prod-live-front\.playbattlegrounds\.com" })
    $cleanLines += "$bestIp prod-live-front.playbattlegrounds.com"
    [System.IO.File]::WriteAllLines($hostsPath, $cleanLines, [System.Text.Encoding]::ASCII)
    & ipconfig.exe /flushdns | Out-Null
}

# 6. Collect and display parallel endpoint verification results
Write-Host ""
Write-Host "[3/3] Ket qua verify ket noi song song den Steam va PUBG:"
foreach ($vp in $verifyProbes) {
    $vOut = $vp.Process.StandardOutput.ReadToEnd().Trim()
    $vp.Process.WaitForExit()
    $vParts = $vOut -split '\|'
    if ($vParts.Count -eq 3) {
        Write-Host ("  - {0} : HTTP {1} | IP: {2,-15} | Time: {3}s" -f $vp.Label, $vParts[0], $vParts[1], $vParts[2])
    }
}
if ($bestIp) {
    Write-Host ("  - PUBG Lobby 512KB (prod-live-front)   : HTTP {0} | IP: {1,-15} | Time: {2:F3}s" -f $bestHttp, $bestIp, $bestTime)
} else {
    Write-Host "  - PUBG Lobby 512KB (prod-live-front)   : KHONG TIM THAY IP CDN PHU HOP"
}
