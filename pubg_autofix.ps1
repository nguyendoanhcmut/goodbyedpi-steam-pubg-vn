# Auto-configure active network adapters DNS + Win11 DoH, validate Coherent GT cache,
# race multi-region PUBG CDN IPs using 512 KB bulk chunks, and auto-detect newly DPI-blocked domains.
$ErrorActionPreference = 'SilentlyContinue'
$baseDir = $PSScriptRoot
$blacklistPath = Join-Path $baseDir "steam-blacklist.txt"

# 1. Configure DNS + Native Windows 11 DoH on active physical network adapters (excluding VPN/Virtual adapters)
$adapters = Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and
    $_.HardwareInterface -eq $true -and
    $_.InterfaceDescription -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback'
}
if (-not $adapters) {
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and
        $_.InterfaceDescription -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback'
    }
}

foreach ($dohServer in @('1.1.1.1', '1.0.0.1', '8.8.8.8', '8.8.4.4')) {
    Set-DnsClientDohServerAddress -ServerAddress $dohServer -AutoUpgrade $true -AllowFallbackToUdp $true | Out-Null
}

foreach ($a in $adapters) {
    $name = $a.Name
    $guid = $a.InterfaceGuid
    netsh interface ipv4 set dnsservers name="$name" static 1.1.1.1 primary validate=no | Out-Null
    netsh interface ipv4 add dnsservers name="$name" 8.8.8.8 index=2 validate=no | Out-Null
    netsh interface ipv6 set dnsservers name="$name" static ::1 primary validate=no | Out-Null

    if ($guid) {
        foreach ($dnsIp in @('1.1.1.1', '8.8.8.8')) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$guid\DohInterfaceSettings\Doh\$dnsIp"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            New-ItemProperty -Path $regPath -Name "DohFlags" -Value 1 -PropertyType QWord -Force | Out-Null
        }
    }
}

# 2. Surgical Coherent GT Cache (CohCache) Integrity Validator & Auto-Repair
$cohCacheDir = Join-Path $env:LOCALAPPDATA "TslGame\Saved\CohCache"
if (Test-Path $cohCacheDir) {
    $repairedCount = 0
    $hdrFiles = Get-ChildItem -Path $cohCacheDir -Filter "*.hdr"
    foreach ($hdr in $hdrFiles) {
        $ctxPath = [System.IO.Path]::ChangeExtension($hdr.FullName, ".ctx")
        $corrupt = $false
        if ($hdr.Length -eq 0 -or -not (Test-Path $ctxPath)) {
            $corrupt = $true
        } else {
            $ctxItem = Get-Item $ctxPath
            $headLines = Get-Content $hdr.FullName -TotalCount 2
            if ($ctxItem.Length -eq 0 -or $headLines.Count -lt 2) {
                $corrupt = $true
            } else {
                $status = $headLines[0].Trim()
                $expectedLen = 0L
                [long]::TryParse($headLines[1].Trim(), [ref]$expectedLen) | Out-Null
                if ($status -ne "200" -or $expectedLen -le 0 -or $ctxItem.Length -ne $expectedLen) {
                    $corrupt = $true
                }
            }
        }
        if ($corrupt) {
            Remove-Item $hdr.FullName -Force
            if (Test-Path $ctxPath) { Remove-Item $ctxPath -Force }
            $repairedCount++
        }
    }
    # Clean orphan .ctx files without matching .hdr
    Get-ChildItem -Path $cohCacheDir -Filter "*.ctx" | ForEach-Object {
        $hdrPath = [System.IO.Path]::ChangeExtension($_.FullName, ".hdr")
        if ($_.Length -eq 0 -or -not (Test-Path $hdrPath)) {
            Remove-Item $_.FullName -Force
            $repairedCount++
        }
    }
    if ($repairedCount -gt 0) {
        Write-Host "  [+] Da don dep $repairedCount file cache Coherent GT bi loi/dut quang."
    }
}

# 3. Gather Asia/SEA CDN candidate IPs and benchmark 512 KB chunk of main.<hash>.js
$candidateIps = @("43.175.115.189", "43.174.32.194", "43.168.152.146", "104.69.151.226")
$asiaPool = Resolve-DnsName "prod-live-front.playbattlegrounds.com.cdn.dnsv1.com" -Server 1.1.1.1 -Type A |
    Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress
if ($asiaPool) { $candidateIps = $asiaPool + $candidateIps }
$candidateIps = $candidateIps | Select-Object -Unique | Select-Object -First 6

# Dynamically discover current /app/<build>/main.<hash>.js path
$mainJsPath = "/app/pc-2610-202/main.cb4691e73a746a46.js"
foreach ($seedIp in $candidateIps) {
    $rootHtml = & curl.exe -s --resolve "prod-live-front.playbattlegrounds.com:443:$seedIp" --max-time 2 "https://prod-live-front.playbattlegrounds.com/index.html"
    if ($rootHtml -match '(/app/[^"'']+?/index\.html)') {
        $appIndexPath = $Matches[1]
        $appDir = $appIndexPath -replace '/index\.html$', ''
        $appHtml = & curl.exe -s --resolve "prod-live-front.playbattlegrounds.com:443:$seedIp" --max-time 2 "https://prod-live-front.playbattlegrounds.com$appIndexPath"
        if ($appHtml -match '(main\.[a-f0-9]+\.js)') {
            $mainJsPath = "$appDir/$($Matches[1])"
            break
        }
    }
}

$bestIp = $null
$bestTime = 999.0

foreach ($ip in $candidateIps) {
    $out = & curl.exe -s -o NUL --range 0-524287 -w "%{http_code}|%{size_download}|%{time_total}" --resolve "prod-live-front.playbattlegrounds.com:443:$ip" --max-time 2.5 "https://prod-live-front.playbattlegrounds.com$mainJsPath"
    $parts = $out -split '\|'
    if ($parts.Count -eq 3 -and ($parts[0] -eq "206" -or $parts[0] -eq "200")) {
        $dlSize = 0L
        [long]::TryParse($parts[1], [ref]$dlSize) | Out-Null
        $t = [double]::Parse($parts[2], [System.Globalization.CultureInfo]::InvariantCulture)
        if ($dlSize -ge 500000 -and $t -lt $bestTime) {
            $bestTime = $t
            $bestIp = $ip
        }
    }
}

# 4. Atomically update C:\Windows\System32\drivers\etc\hosts only when $bestIp is verified
if ($bestIp) {
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $lines = Get-Content $hostsPath | Where-Object { $_ -notmatch "prod-live-front\.playbattlegrounds\.com" }
    $lines += "$bestIp prod-live-front.playbattlegrounds.com"
    [System.IO.File]::WriteAllLines($hostsPath, $lines, [System.Text.Encoding]::ASCII)
}

# 5. Auto-fallback from -8 --frag-by-sni to -5 --frag-by-sni if router/ONT drops fake checksum packets
$testBypass = & curl.exe -s -o NUL -w "%{http_code}|%{exitcode}" --connect-timeout 2 --max-time 3 "https://bridge-release.pubg.io/"
$bpParts = $testBypass -split '\|'
if ($bpParts[0] -eq "000" -and ($bpParts[1] -eq "35" -or $bpParts[1] -eq "56")) {
    Write-Host "  [!] Router/ONT chan fake checksum (-8), dang chuyen sang che do Auto-TTL (-5 --frag-by-sni)..."
    $exePath = Join-Path $baseDir "x86_64\goodbyedpi.exe"
    sc.exe stop GoodbyeDPI | Out-Null
    Start-Sleep -Seconds 1
    sc.exe config GoodbyeDPI binPath= "`"$exePath`" -5 --frag-by-sni --blacklist `"$blacklistPath`" --dns-addr 208.67.222.222 --dns-port 5353 --dnsv6-addr 2620:119:35::35 --dnsv6-port 5353" start= auto | Out-Null
    sc.exe start GoodbyeDPI | Out-Null
    Start-Sleep -Seconds 1
}

# 6. Enable DNS log and auto-scan recent game/Steam domains for true DPI resets (curl exitcode 35 or 56)
wevtutil sl Microsoft-Windows-DNS-Client/Operational /e:true 2>$null
if (Test-Path $blacklistPath) {
    $existing = Get-Content $blacklistPath | Where-Object { $_.Trim() -ne "" }
    $recentDomains = Get-WinEvent -LogName "Microsoft-Windows-DNS-Client/Operational" -MaxEvents 250 -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Properties[0].Value } |
        Where-Object {
            $_ -match '(pubg|krafton|battlegrounds|steampowered|steamcontent|steamcommunity|battleye|vivox)' -and
            $_ -notmatch '\.(dnsv1\.com|akamaiedge\.net|edgekey\.net|akadns\.net|cloudfront\.net|amazonaws\.com)$'
        } |
        Select-Object -Unique

    $addedNew = $false
    foreach ($d in $recentDomains) {
        $alreadyCovered = $false
        foreach ($rule in $existing) {
            if ($d -eq $rule -or $d.EndsWith("." + $rule)) {
                $alreadyCovered = $true
                break
            }
        }
        if (-not $alreadyCovered) {
            $probe = & curl.exe -k -s -o NUL -w "%{http_code}|%{exitcode}" --connect-timeout 1.5 --max-time 2.5 "https://$d/"
            $pParts = $probe -split '\|'
            if ($pParts.Count -eq 2 -and $pParts[0] -eq "000" -and ($pParts[1] -eq "35" -or $pParts[1] -eq "56")) {
                $parts = $d -split '\.'
                if ($d -match '\.(com|co|net|org)\.[a-z]{2}$' -and $parts.Count -ge 3) {
                    $rootDomain = "$($parts[-3]).$($parts[-2]).$($parts[-1])"
                } elseif ($parts.Count -ge 2) {
                    $rootDomain = "$($parts[-2]).$($parts[-1])"
                } else {
                    $rootDomain = $d
                }
                Add-Content -Path $blacklistPath -Value $rootDomain
                $existing += $rootDomain
                $addedNew = $true
                Write-Host "  [+] Phat hien ten mien moi bi chan DPI, da tu dong them vao blacklist: $rootDomain"
            }
        }
    }
    if ($addedNew) {
        sc.exe stop GoodbyeDPI | Out-Null
        Start-Sleep -Seconds 1
        sc.exe start GoodbyeDPI | Out-Null
    }
}

# 7. Flush DNS cache and maintain Scheduled Tasks
ipconfig /flushdns | Out-Null
Unregister-ScheduledTask -TaskName 'GoodbyeDPI-Toggle' -Confirm:$false | Out-Null
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel
Set-ScheduledTask -TaskName 'GoodbyeDPI-On' -Settings $s | Out-Null
Set-ScheduledTask -TaskName 'GoodbyeDPI-Off' -Settings $s | Out-Null
