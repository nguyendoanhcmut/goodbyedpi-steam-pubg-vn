$ErrorActionPreference = 'SilentlyContinue'
$baseDir = $PSScriptRoot
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$curlExe = if ([System.IO.File]::Exists("$env:SystemRoot\System32\curl.exe")) { "$env:SystemRoot\System32\curl.exe" } else { "curl.exe" }

function Get-HklmValue {
    param([string]$SubKey, [string]$ValueName)
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey, $false)
    if ($null -ne $k) { try { return $k.GetValue($ValueName, $null) } finally { $k.Dispose() } }
    return $null
}

function Get-UrlMd5Hex {
    param([string]$Url)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Url)
        return ([System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally { $md5.Dispose() }
}

function Resolve-SteamPubgInstallDir {
    try {
        $uninstKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 578080", $false)
        if ($null -ne $uninstKey) {
            try {
                $instLoc = [string]$uninstKey.GetValue("InstallLocation", "")
                if ($instLoc -and [System.IO.Directory]::Exists($instLoc)) { return $instLoc }
            } finally { $uninstKey.Dispose() }
        }
    } catch {}
    $steamRoot = $null
    foreach ($regSpec in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam|InstallPath", "HKCU:\Software\Valve\Steam|SteamPath")) {
        $parts = $regSpec -split '\|'
        try {
            $val = (Get-ItemProperty -Path $parts[0] -Name $parts[1] -ErrorAction SilentlyContinue).($parts[1])
            if ($val -and [System.IO.Directory]::Exists($val)) { $steamRoot = $val.Replace('/', '\'); break }
        } catch {}
    }
    if (-not $steamRoot) { $steamRoot = Join-Path ${env:ProgramFiles(x86)} "Steam" }
    $libDirs = New-Object System.Collections.Generic.List[string]
    if ($steamRoot) { $libDirs.Add($steamRoot) }
    $vdfPath = if ($steamRoot) { Join-Path $steamRoot "steamapps\libraryfolders.vdf" } else { "" }
    if ($vdfPath -and [System.IO.File]::Exists($vdfPath)) {
        try {
            $vdfRaw = [System.IO.File]::ReadAllText($vdfPath, [System.Text.Encoding]::UTF8)
            foreach ($m in [regex]::Matches($vdfRaw, '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value.Replace('\\', '\')
                if ($p -and -not $libDirs.Contains($p)) { $libDirs.Add($p) }
            }
        } catch {}
    }
    foreach ($lib in $libDirs) {
        $cand = Join-Path $lib "steamapps\common\PUBG"
        if ([System.IO.Directory]::Exists($cand)) { return $cand }
    }
    return (Join-Path $steamRoot "steamapps\common\PUBG")
}

function Get-SteamPubgBuildId {
    param([string]$AcfPath)
    if ($AcfPath -and [System.IO.File]::Exists($AcfPath)) {
        try {
            $raw = [System.IO.File]::ReadAllText($AcfPath, [System.Text.Encoding]::UTF8)
            if ($raw -match '"buildid"\s+"(\d+)"') { return $Matches[1] }
        } catch {}
    }
    return ""
}

function Read-AutofixState {
    param([string]$StatePath)
    $defaultMainJs = "/app/pc-2611-128/main.fd13ca214153224b.js"
    if ($StatePath -and [System.IO.File]::Exists($StatePath)) {
        try {
            $raw = [System.IO.File]::ReadAllText($StatePath, [System.Text.Encoding]::UTF8)
            $obj = $raw | ConvertFrom-Json
            if ($null -ne $obj) {
                $mJs = if ($obj.MainJsPath -and $obj.MainJsPath -match '^/app/pc-[^/]+/') { [string]$obj.MainJsPath } else { $defaultMainJs }
                $aDir = if ($obj.AppDir -and $obj.AppDir -match '^/app/pc-[^/]+$') { [string]$obj.AppDir } elseif ($mJs -match '^(/app/[^/]+)/') { $Matches[1] } else { "/app/pc-2611-128" }
                $assets = @($obj.Assets | Where-Object { $_ -and $_ -match '^/app/' } | ForEach-Object { [string]$_ })
                $warpMap = @{}
                if ($null -ne $obj.WarpRunValues) {
                    foreach ($p in $obj.WarpRunValues.PSObject.Properties) {
                        if ($p.Value) { $warpMap[$p.Name] = [string]$p.Value }
                    }
                }
                return [PSCustomObject]@{
                    BuildId = [string]$obj.BuildId; AppDir = $aDir; MainJsPath = $mJs
                    Assets = $assets; PinnedIp = [string]$obj.PinnedIp
                    LastSyncEpoch = [long]$obj.LastSyncEpoch; WarpRunValues = $warpMap
                }
            }
        } catch {}
    }
    return [PSCustomObject]@{
        BuildId = ""; AppDir = ""; MainJsPath = $defaultMainJs
        Assets = @(); PinnedIp = ""; LastSyncEpoch = 0L; WarpRunValues = @{}
    }
}

function Write-AutofixState {
    param([string]$StatePath, [string]$BuildId, [string]$AppDir, [string]$MainJsPath, [string[]]$Assets, [string]$PinnedIp, [hashtable]$WarpRunValues = @{})
    if (-not $StatePath) { return }
    $tmpPath = "$StatePath.tmp"
    try {
        $parentDir = [System.IO.Path]::GetDirectoryName($StatePath)
        if ($parentDir -and -not [System.IO.Directory]::Exists($parentDir)) { [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null }
        $payload = [ordered]@{
            BuildId = [string]$BuildId; AppDir = [string]$AppDir; MainJsPath = [string]$MainJsPath
            Assets = @($Assets | Where-Object { $_ } | Select-Object -Unique); PinnedIp = [string]$PinnedIp
            LastSyncEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            WarpRunValues = if ($null -ne $WarpRunValues) { $WarpRunValues } else { @{} }
        } | ConvertTo-Json -Depth 4
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tmpPath, $payload, $utf8NoBom)
        if ([System.IO.File]::Exists($StatePath)) { try { [System.IO.File]::SetAttributes($StatePath, [System.IO.FileAttributes]::Normal) } catch {} }
        [System.IO.File]::Copy($tmpPath, $StatePath, $true)
    } catch {} finally {
        if ([System.IO.File]::Exists($tmpPath)) { try { [System.IO.File]::Delete($tmpPath) } catch {} }
    }
}

function Disable-PubgStartupMovies {
    param([string]$MoviesDir, [string]$EngineIniPath)
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
            $needsUpdate = ($rawIni -notmatch 'bWaitForMoviesToComplete=False') -or ($rawIni -notmatch 'bMoviesAreSkippable=True') -or ($rawIni -notmatch '-StartupMovies=')
            if ($needsUpdate) {
                [System.IO.File]::SetAttributes($EngineIniPath, [System.IO.FileAttributes]::Normal)
                if ($rawIni -notmatch '\[/Script/MoviePlayer\.MoviePlayerSettings\]') {
                    $rawIni = $rawIni.TrimEnd() + "`r`n`r`n[/Script/MoviePlayer.MoviePlayerSettings]`r`nbWaitForMoviesToComplete=False`r`nbMoviesAreSkippable=True`r`n-StartupMovies=`r`n"
                } else {
                    if ($rawIni -notmatch 'bWaitForMoviesToComplete=False') { $rawIni = $rawIni -replace '(\[/Script/MoviePlayer\.MoviePlayerSettings\])', "`$1`r`nbWaitForMoviesToComplete=False" }
                    if ($rawIni -notmatch 'bMoviesAreSkippable=True') { $rawIni = $rawIni -replace '(\[/Script/MoviePlayer\.MoviePlayerSettings\])', "`$1`r`nbMoviesAreSkippable=True" }
                    if ($rawIni -notmatch '-StartupMovies=') { $rawIni = $rawIni -replace '(\[/Script/MoviePlayer\.MoviePlayerSettings\])', "`$1`r`n-StartupMovies=" }
                }
                [System.IO.File]::WriteAllText($EngineIniPath, $rawIni, (New-Object System.Text.UTF8Encoding($false)))
            }
            $attr = [System.IO.File]::GetAttributes($EngineIniPath)
            if (($attr -band [System.IO.FileAttributes]::ReadOnly) -eq 0) {
                [System.IO.File]::SetAttributes($EngineIniPath, ($attr -bor [System.IO.FileAttributes]::ReadOnly))
            }
        } catch {}
    }
}

function Sync-PubgIntegrityCheckHistory {
    param([string]$BinariesWin64Dir, [string]$HistoryCsvPath)
    if (-not $BinariesWin64Dir -or -not $HistoryCsvPath) { return 0 }
    $hashCsvPath = Join-Path $BinariesWin64Dir "TslGame_Hash.csv"
    if (-not [System.IO.File]::Exists($hashCsvPath)) { return 0 }
    $clientVersion = $null
    $existingLines = @()
    if ([System.IO.File]::Exists($HistoryCsvPath)) {
        try {
            $existingLines = [System.IO.File]::ReadAllLines($HistoryCsvPath, [System.Text.Encoding]::UTF8)
            foreach ($el in $existingLines) {
                $parts = $el -split ','
                if ($parts.Count -ge 3 -and $parts[1] -match '^\d+\.\d+\.\d+\.\d+$') {
                    try {
                        $vCandidate = $parts[1].Trim()
                        $parsedCand = [version]$vCandidate
                        if (-not $clientVersion -or ($parsedCand -gt [version]$clientVersion)) { $clientVersion = $vCandidate }
                    } catch {}
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
                if ($exeVer -match '^\d+\.\d+\.\d+\.\d+$') { [void]([version]$exeVer); $clientVersion = $exeVer }
            }
        } catch {}
    }
    if (-not $clientVersion) { return 0 }
    $existingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($el in $existingLines) { if ($el) { [void]$existingSet.Add($el.Trim()) } }
    $rawHashLines = [System.IO.File]::ReadAllLines($hashCsvPath, [System.Text.Encoding]::UTF8)
    $targetLines = New-Object System.Collections.Generic.List[string]($rawHashLines.Count)
    $needsWrite = $false
    foreach ($hl in $rawHashLines) {
        if ($hl -match '^"([^"]+)"') {
            $relPath = $Matches[1]
            try {
                $fullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($BinariesWin64Dir, $relPath))
                if ([System.IO.File]::Exists($fullPath)) {
                    $fi = [System.IO.FileInfo]::new($fullPath)
                    $stamp = $fi.LastWriteTimeUtc.ToString("yyyy.MM.dd-HH.mm.ss", $inv)
                    $entry = "$($fullPath.Replace('\', '/')),$clientVersion,$stamp"
                    $targetLines.Add($entry)
                    if (-not $existingSet.Contains($entry)) { $needsWrite = $true }
                }
            } catch {}
        }
    }
    if ($targetLines.Count -gt 0 -and ($needsWrite -or $existingLines.Count -ne $targetLines.Count)) {
        $tmpHist = "$HistoryCsvPath.tmp"
        try {
            $histDir = [System.IO.Path]::GetDirectoryName($HistoryCsvPath)
            if ($histDir -and -not [System.IO.Directory]::Exists($histDir)) { [System.IO.Directory]::CreateDirectory($histDir) | Out-Null }
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllLines($tmpHist, $targetLines.ToArray(), $utf8NoBom)
            if ([System.IO.File]::Exists($HistoryCsvPath)) {
                try {
                    $curAttr = [System.IO.File]::GetAttributes($HistoryCsvPath)
                    if (($curAttr -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        [System.IO.File]::SetAttributes($HistoryCsvPath, ($curAttr -band (-bnot [System.IO.FileAttributes]::ReadOnly)))
                    }
                } catch {}
            }
            [System.IO.File]::Copy($tmpHist, $HistoryCsvPath, $true)
            return $targetLines.Count
        } catch {} finally {
            if ([System.IO.File]::Exists($tmpHist)) { try { [System.IO.File]::Delete($tmpHist) } catch {} }
        }
    }
    return 0
}

function Invoke-PubgBinaryPageCacheWarmup {
    param([string]$BinariesWin64Dir)
    if (-not $BinariesWin64Dir -or -not [System.IO.Directory]::Exists($BinariesWin64Dir)) { return }
    $buf = New-Object byte[] 4194304
    $pf86 = ${env:ProgramFiles(x86)}
    $warmTargets = @(
        (Join-Path $BinariesWin64Dir "TslGame.exe"), (Join-Path $BinariesWin64Dir "TslGame_ZK.exe"),
        (Join-Path $BinariesWin64Dir "ExecPubg.exe"), (Join-Path $BinariesWin64Dir "TslGame_BE.exe"),
        (Join-Path $pf86 "Common Files\BattlEye\BEService.exe")
    )
    foreach ($fp in $warmTargets) {
        if ([System.IO.File]::Exists($fp)) {
            try {
                $fs = New-Object System.IO.FileStream($fp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 4194304, [System.IO.FileOptions]::SequentialScan)
                try { while ($fs.Read($buf, 0, $buf.Length) -gt 0) {} } finally { $fs.Dispose() }
            } catch {}
        }
    }
    foreach ($sigTarget in @((Join-Path $BinariesWin64Dir "TslGame_ZK.exe"), (Join-Path $pf86 "Common Files\BattlEye\BEService.exe"))) {
        if ([System.IO.File]::Exists($sigTarget)) {
            try { [void](Get-AuthenticodeSignature -LiteralPath $sigTarget -ErrorAction SilentlyContinue) } catch {}
        }
    }
}

function Remove-PubgReplayDirectorySafely {
    param([System.IO.DirectoryInfo]$SubDir)
    if ($null -eq $SubDir -or -not [System.IO.Directory]::Exists($SubDir.FullName)) { return $false }
    try {
        foreach ($if in $SubDir.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) {
            try {
                if (($if.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) { [System.IO.File]::SetAttributes($if.FullName, [System.IO.FileAttributes]::Normal) }
                $probeStream = [System.IO.File]::Open($if.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $probeStream.Close(); $probeStream.Dispose()
            } catch { return $false }
        }
        foreach ($id in $SubDir.GetDirectories("*", [System.IO.SearchOption]::AllDirectories)) {
            try { [System.IO.File]::SetAttributes($id.FullName, [System.IO.FileAttributes]::Normal) } catch {}
        }
        [System.IO.File]::SetAttributes($SubDir.FullName, [System.IO.FileAttributes]::Normal)
        $SubDir.Delete($true)
        return (-not [System.IO.Directory]::Exists($SubDir.FullName))
    } catch { return $false }
}

function Clear-StalePubgDemos {
    param([string]$DemosDir)
    if (-not $DemosDir -or -not [System.IO.Directory]::Exists($DemosDir)) { return 0 }
    $cutoffUtc = [DateTime]::UtcNow.AddDays(-14)
    $removed = 0
    $recentUnpinned = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    try {
        $dirInfo = [System.IO.DirectoryInfo]::new($DemosDir)
        foreach ($subDir in $dirInfo.GetDirectories()) {
            $keep = $false
            $riPath = Join-Path $subDir.FullName "PUBG.replayinfo"
            if ([System.IO.File]::Exists($riPath)) {
                $keep = $true
                try {
                    $rawRi = [System.IO.File]::ReadAllText($riPath, [System.Text.Encoding]::UTF8)
                    if ($rawRi -notmatch '"bShouldKeep"\s*:\s*true') { $keep = $false }
                } catch { $keep = $true }
            }
            if (-not $keep) {
                if ($subDir.LastWriteTimeUtc -lt $cutoffUtc) {
                    if (Remove-PubgReplayDirectorySafely -SubDir $subDir) { $removed++ }
                } else { $recentUnpinned.Add($subDir) }
            }
        }
        if ($recentUnpinned.Count -gt 20) {
            foreach ($od in @($recentUnpinned | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 20)) {
                if (Remove-PubgReplayDirectorySafely -SubDir $od) { $removed++ }
            }
        }
    } catch {}
    return $removed
}

function Start-CurlProbe {
    param([string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curlExe; $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $false
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Start-SteamParallelProbe {
    $steamArgs = "-Z -4 -s --connect-timeout 2 --max-time 3.5 -o NUL -w `"0|%{http_code}|%{remote_ip}|%{time_total}`n`" `"https://store.steampowered.com/`" --next -4 -s --connect-timeout 2 --max-time 3.5 -o NUL -w `"1|%{http_code}|%{remote_ip}|%{time_total}`n`" `"https://steamcommunity.com/`" --next -4 -s --connect-timeout 2 --max-time 3.5 -o NUL -w `"2|%{http_code}|%{remote_ip}|%{time_total}`n`" `"https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/`""
    return (Start-CurlProbe -Arguments $steamArgs)
}

function Resolve-LivePubgBundle {
    param([string[]]$ProbeIps, [string]$FallbackMainJsPath, [string]$SavedAppDir, [string[]]$SavedAssets)
    $discoveredMainJs = $null; $discoveredAppDir = $null; $discoveredAssets = @(); $aliveIp = $null
    $topIps = @($ProbeIps | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 4)
    $idxProbes = @()
    foreach ($ip in $topIps) {
        $idxProbes += [PSCustomObject]@{
            IP = $ip; Done = $false
            Process = Start-CurlProbe -Arguments "-4 -s -k -L --max-redirs 2 --connect-timeout 1 --max-time 2.0 --resolve `"prod-live-front.playbattlegrounds.com:443:$ip`" `"https://prod-live-front.playbattlegrounds.com/?provider=steam`" `"https://prod-live-front.playbattlegrounds.com/index.html`""
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
                        $appIndexPath = $Matches[1]; $aliveIp = $p.IP; break
                    }
                } else { $allDone = $false }
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
        $stateMatchesLiveDir = ($SavedAppDir -eq $discoveredAppDir) -and ($SavedAssets.Count -ge 2) -and $FallbackMainJsPath.StartsWith("$discoveredAppDir/")
        if ($stateMatchesLiveDir) {
            $discoveredMainJs = $FallbackMainJsPath
            $discoveredAssets = @($SavedAssets)
        } else {
            $appHtmlProc = Start-CurlProbe -Arguments "-4 -s -k --connect-timeout 1 --max-time 2.0 --resolve `"prod-live-front.playbattlegrounds.com:443:$aliveIp`" `"https://prod-live-front.playbattlegrounds.com$appIndexPath`""
            if ($appHtmlProc) {
                try {
                    $appHtml = $appHtmlProc.StandardOutput.ReadToEnd()
                    $appHtmlProc.WaitForExit(2100) | Out-Null
                    if ($appHtml -match '(/app/[^"'']+/js/main\.[^"'']+\.js)') { $discoveredMainJs = $Matches[1] }
                    elseif ($appHtml -match '((?:js/)?main\.[a-f0-9]+\.js)') { $discoveredMainJs = "$discoveredAppDir/$($Matches[1])" }
                    foreach ($assetMatch in [regex]::Matches($appHtml, '(?:href|src)="([^"]+)"')) {
                        $rel = $assetMatch.Groups[1].Value -replace '^\./', ''
                        if ($rel -and $rel -notmatch '^https?://' -and $rel -match '\.(js|css)$') {
                            $fullAssetPath = if ($rel.StartsWith('/')) { $rel } else { "$discoveredAppDir/$rel" }
                            if ($discoveredAssets -notcontains $fullAssetPath) { $discoveredAssets += $fullAssetPath }
                        }
                    }
                } catch {}
                try { $appHtmlProc.Dispose() } catch {}
            }
        }
    }
    if (-not $discoveredMainJs) { $discoveredMainJs = $FallbackMainJsPath }
    if (-not $discoveredAppDir -and $discoveredMainJs -match '^(/app/[^/]+)/') { $discoveredAppDir = $Matches[1] }
    if ($discoveredMainJs -and ($discoveredAssets -notcontains $discoveredMainJs)) { $discoveredAssets += $discoveredMainJs }
    return [PSCustomObject]@{ MainJsPath = $discoveredMainJs; AppDir = $discoveredAppDir; Assets = $discoveredAssets; AliveIp = $aliveIp }
}

function Start-CdnRaceProbes {
    param([string[]]$CandidateIps, [string]$MainJsPath)
    foreach ($ip in $CandidateIps) {
        [PSCustomObject]@{
            IP = $ip; Done = $false
            Process = Start-CurlProbe -Arguments "-4 -s -k -o NUL -r 0-2097151 -w `"%{http_code}|%{size_download}|%{time_total}`" --connect-timeout 1.5 --max-time 5 --resolve `"prod-live-front.playbattlegrounds.com:443:$ip`" `"https://prod-live-front.playbattlegrounds.com$MainJsPath`""
        }
    }
}

function Wait-CdnRaceProbes {
    param([object[]]$Probes, [string]$PinnedIp)
    $bestIp = $null; $bestTime = 999.0; $bestHttp = "000"; $pinnedIpTime = 999.0; $pinnedIpHttp = "000"; $aliveIp = $null
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
                        if (-not $aliveIp -and $parts[0] -match '^(200|206|301|302|403|404)$') { $aliveIp = $p.IP }
                        if ($parts[0] -eq "206" -or $parts[0] -eq "200") {
                            $dlSize = 0L
                            [long]::TryParse($parts[1], [ref]$dlSize) | Out-Null
                            $t = 999.0
                            $tOk = [double]::TryParse(($parts[2] -replace ',', '.'), [System.Globalization.NumberStyles]::Float, $inv, [ref]$t)
                            $validPayload = ($parts[0] -eq "206" -and $dlSize -ge 1500000) -or ($parts[0] -eq "200" -and $dlSize -ge 1500000)
                            if ($tOk -and $validPayload -and $t -gt 0.0) {
                                if ($PinnedIp -and $p.IP -eq $PinnedIp) { $pinnedIpTime = $t; $pinnedIpHttp = $parts[0] }
                                if ($t -lt $bestTime) {
                                    $bestTime = $t; $bestIp = $p.IP; $bestHttp = $parts[0]
                                    if ($winnerFoundAt -eq 0L) { $winnerFoundAt = $raceSw.ElapsedMilliseconds }
                                }
                            }
                        }
                    }
                } else { $allDone = $false }
            }
        }
        if ($allDone -or ($winnerFoundAt -gt 0L -and ($raceSw.ElapsedMilliseconds - $winnerFoundAt) -ge 250)) { break }
        Start-Sleep -Milliseconds 15
    }
    foreach ($p in $Probes) {
        if ($p.Process) {
            if (-not $p.Process.HasExited) { try { $p.Process.Kill() } catch {} }
            try { $p.Process.Dispose() } catch {}
        }
    }
    return [PSCustomObject]@{ BestIp = $bestIp; BestTime = $bestTime; BestHttp = $bestHttp; PinnedIpTime = $pinnedIpTime; PinnedIpHttp = $pinnedIpHttp; AliveIp = $aliveIp }
}

function Save-CohCacheAssetFromCdn {
    param([string]$AssetPath, [string]$CdnIp, [string]$CohCacheDir)
    if (-not $AssetPath -or -not $CdnIp -or -not $CohCacheDir) { return $false }
    if (-not [System.IO.Directory]::Exists($CohCacheDir)) {
        try { [System.IO.Directory]::CreateDirectory($CohCacheDir) | Out-Null } catch { return $false }
    }
    $url = "https://prod-live-front.playbattlegrounds.com$AssetPath"
    $hash = Get-UrlMd5Hex -Url $url
    $hdrPath = Join-Path $CohCacheDir "$hash.hdr"
    $ctxPath = Join-Path $CohCacheDir "$hash.ctx"
    if ([System.IO.File]::Exists($hdrPath) -and [System.IO.File]::Exists($ctxPath) -and ([System.IO.FileInfo]::new($hdrPath).Length -gt 0) -and ([System.IO.FileInfo]::new($ctxPath).Length -gt 0)) {
        return $true
    }
    $tmpCtx = Join-Path $CohCacheDir "$hash.ctx.tmp"
    $tmpHdr = Join-Path $CohCacheDir "$hash.hdr.tmp"
    try {
        & $curlExe -4 -s -k --connect-timeout 2 --max-time 12 -D $tmpHdr -o $tmpCtx --resolve "prod-live-front.playbattlegrounds.com:443:$CdnIp" $url | Out-Null
        if (-not [System.IO.File]::Exists($tmpCtx) -or -not [System.IO.File]::Exists($tmpHdr)) { return $false }
        $ctxLen = [System.IO.FileInfo]::new($tmpCtx).Length
        if ($ctxLen -le 0) { return $false }
        $rawHdrLines = [System.IO.File]::ReadAllLines($tmpHdr)
        $statusOk = $false; $declaredLen = -1L; $contentType = ""
        $headerLines = New-Object System.Collections.Generic.List[string]
        foreach ($hl in $rawHdrLines) {
            $trimmed = $hl.Trim()
            if ($trimmed -match '^HTTP/\d(?:\.\d)?\s+(\d{3})') {
                $statusOk = ($Matches[1] -eq '200'); $declaredLen = -1L; $contentType = ""; $headerLines.Clear()
            } elseif ($trimmed.Length -gt 0) {
                if ($trimmed -match '(?i)(Server:\s*Lego Server|X-NWS-LOG-UUID:|playbattlegrounds\.com\.cn)') { return $false }
                if ($trimmed -match '(?i)^Content-Length:\s*(\d+)') { [void][long]::TryParse($Matches[1], [ref]$declaredLen) }
                if ($trimmed -match '(?i)^Content-Type:\s*(.+)$') { $contentType = $Matches[1].Trim() }
                $headerLines.Add($trimmed)
            }
        }
        if (-not $statusOk) { return $false }
        if ($declaredLen -ge 0 -and $ctxLen -ne $declaredLen) { return $false }
        if ($AssetPath -match '\.(js|css)$') {
            if ($ctxLen -lt 64 -or $contentType -match '(?i)text/html') { return $false }
            $sampleText = [System.IO.File]::ReadAllText($tmpCtx, [System.Text.Encoding]::UTF8)
            if ($sampleText -match '(?i)^\s*<(!DOCTYPE|html)|<html\b') { return $false }
        }
        $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $expEpoch = $nowEpoch + 86400
        $outLines = New-Object System.Collections.Generic.List[string]
        $outLines.Add("200"); $outLines.Add("$ctxLen"); $outLines.Add("$expEpoch"); $outLines.Add("$nowEpoch")
        foreach ($hLine in $headerLines) { $outLines.Add($hLine) }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        if ([System.IO.File]::Exists($ctxPath)) { try { [System.IO.File]::SetAttributes($ctxPath, [System.IO.FileAttributes]::Normal); [System.IO.File]::Delete($ctxPath) } catch {} }
        if ([System.IO.File]::Exists($hdrPath)) { try { [System.IO.File]::SetAttributes($hdrPath, [System.IO.FileAttributes]::Normal) } catch {} }
        [System.IO.File]::Move($tmpCtx, $ctxPath)
        [System.IO.File]::WriteAllText($hdrPath, (($outLines -join "`n") + "`n"), $utf8NoBom)
        return $true
    } catch { return $false } finally {
        if ([System.IO.File]::Exists($tmpCtx)) { try { [System.IO.File]::Delete($tmpCtx) } catch {} }
        if ([System.IO.File]::Exists($tmpHdr)) { try { [System.IO.File]::Delete($tmpHdr) } catch {} }
    }
}

function Test-CohCacheBundleComplete {
    param([string]$CohCacheDir, [string]$AppDir, [string]$MainJsPath, [string[]]$Assets)
    if (-not $CohCacheDir -or -not [System.IO.Directory]::Exists($CohCacheDir)) { return $false }
    $checkList = New-Object System.Collections.Generic.List[string]
    if ($MainJsPath) { $checkList.Add($MainJsPath) }
    if ($Assets) { foreach ($a in $Assets) { if ($a -and -not $checkList.Contains($a)) { $checkList.Add($a) } } }
    if ($checkList.Count -eq 0) { return $false }
    foreach ($assetPath in $checkList) {
        $url = "https://prod-live-front.playbattlegrounds.com$assetPath"
        $hash = Get-UrlMd5Hex -Url $url
        $hdrPath = Join-Path $CohCacheDir "$hash.hdr"
        $ctxPath = Join-Path $CohCacheDir "$hash.ctx"
        if (-not [System.IO.File]::Exists($hdrPath) -or -not [System.IO.File]::Exists($ctxPath)) { return $false }
        $hdrLen = [System.IO.FileInfo]::new($hdrPath).Length
        $ctxLen = [System.IO.FileInfo]::new($ctxPath).Length
        if ($hdrLen -le 0 -or $ctxLen -le 0) { return $false }
        try {
            $headLines = [System.IO.File]::ReadAllLines($hdrPath)
            if ($headLines.Count -lt 4 -or $headLines[0].Trim() -ne "200") { return $false }
            $expectedLen = 0L
            if (-not [long]::TryParse($headLines[1].Trim(), [ref]$expectedLen) -or $expectedLen -ne $ctxLen) { return $false }
            foreach ($hl in $headLines) {
                if ($hl -match '(?i)(Server:\s*Lego Server|X-NWS-LOG-UUID:|playbattlegrounds\.com\.cn)') { return $false }
                if ($hl -match '(?i)^Content-Length:\s*(\d+)') {
                    $cl = 0L
                    if ([long]::TryParse($Matches[1], [ref]$cl) -and $cl -ne $ctxLen) { return $false }
                }
            }
            if ($assetPath -match '\.(js|css)$') {
                if ($ctxLen -lt 64) { return $false }
                $sample = [System.IO.File]::ReadAllText($ctxPath, [System.Text.Encoding]::UTF8)
                if ($sample -match '(?i)^\s*<(!DOCTYPE|html)|<html\b') { return $false }
            }
        } catch { return $false }
    }
    return $true
}

function Read-HostsSafely {
    param([string]$Path)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
            return [PSCustomObject]@{ Success = $true; Lines = [string[]]@($lines) }
        } catch { Start-Sleep -Milliseconds 40 }
    }
    return [PSCustomObject]@{ Success = $false; Lines = [string[]]@() }
}

function Write-HostsSafely {
    param([string]$Path, [string[]]$Lines)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [System.IO.File]::WriteAllLines($Path, [string[]]@($Lines), $utf8NoBom)
            return $true
        } catch [System.UnauthorizedAccessException] { return $false } catch { Start-Sleep -Milliseconds 40 }
    }
    return $false
}

$mutex = New-Object System.Threading.Mutex($false, "Global\GoodbyeDPI_Toolkit_Mutex")
$hasMutex = $false
try {
    try { $hasMutex = $mutex.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }
    $pubgInstallDir = Resolve-SteamPubgInstallDir
    $steamAppsDir = Split-Path (Split-Path $pubgInstallDir -Parent) -Parent
    $pubgAcfPath = Join-Path $steamAppsDir "appmanifest_578080.acf"
    $pubgBinariesWin64Dir = Join-Path $pubgInstallDir "TslGame\Binaries\Win64"
    $pubgMoviesDir = Join-Path $pubgInstallDir "TslGame\Content\Movies"
    $engineIniPath = Join-Path $env:LOCALAPPDATA "TslGame\Saved\Config\WindowsNoEditor\Engine.ini"
    $cohCacheDir = Join-Path $env:LOCALAPPDATA "TslGame\Saved\CohCache"
    $integrityCsvPath = Join-Path $env:LOCALAPPDATA "TslGame\Saved\IntegrityCheck\IntegrityCheckHistory.csv"
    $demosDir = Join-Path $env:LOCALAPPDATA "TslGame\Saved\Demos"
    $stateFilePath = Join-Path $env:LOCALAPPDATA "TslGame\Saved\pubg_autofix_state.json"

    Disable-PubgStartupMovies -MoviesDir $pubgMoviesDir -EngineIniPath $engineIniPath

    $allPhysicalNics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
        $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' -and
        $_.Description -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback'
    }
    $nics = @($allPhysicalNics | Where-Object { $_.OperationalStatus -eq 'Up' })
    $downNics = @($allPhysicalNics | Where-Object { $_.OperationalStatus -ne 'Up' })
    $dnsChanged = $false; $dohServerConfigured = $false

    try {
        $tcpip6ParamSub = "SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
        if ((Get-HklmValue -SubKey $tcpip6ParamSub -ValueName "DisabledComponents") -ne 32) {
            $k6 = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($tcpip6ParamSub, $true)
            if ($null -ne $k6) {
                try { $k6.SetValue("DisabledComponents", 32, [Microsoft.Win32.RegistryValueKind]::DWord); $dnsChanged = $true } finally { $k6.Dispose() }
            }
        }
    } catch {}

    foreach ($dNic in $downNics) {
        $dGuid = $dNic.Id; $dName = $dNic.Name
        if ($dGuid) {
            $dV4Sub = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$dGuid"
            $dV6Sub = "SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$dGuid"
            $dV4 = Get-HklmValue -SubKey $dV4Sub -ValueName "NameServer"
            $dDhcpV4 = Get-HklmValue -SubKey $dV4Sub -ValueName "DhcpNameServer"
            $dV6 = Get-HklmValue -SubKey $dV6Sub -ValueName "NameServer"
            $dActDns = @(Get-DnsClientServerAddress -InterfaceAlias $dName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            if ($dV4 -or $dDhcpV4) {
                $k4 = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($dV4Sub, $true)
                if ($null -ne $k4) {
                    try {
                        $k4.SetValue("NameServer", "", [Microsoft.Win32.RegistryValueKind]::String)
                        $k4.SetValue("DhcpNameServer", "", [Microsoft.Win32.RegistryValueKind]::String)
                    } finally { $k4.Dispose() }
                }
                & netsh.exe interface ipv4 delete dnsservers name="$dName" all | Out-Null
                $dnsChanged = $true
            }
            if ($dV6 -or ($dActDns.Count -gt 0)) {
                $k6i = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($dV6Sub, $true)
                if ($null -ne $k6i) { try { $k6i.SetValue("NameServer", "", [Microsoft.Win32.RegistryValueKind]::String) } finally { $k6i.Dispose() } }
                & netsh.exe interface ipv6 delete dnsservers name="$dName" all | Out-Null
                & netsh.exe interface ipv6 set dnsservers name="$dName" source=static address=none validate=no | Out-Null
                $dnsChanged = $true
            }
        }
    }

    foreach ($nic in $nics) {
        $name = $nic.Name; $guid = $nic.Id
        $v4SubKey = "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        $v6SubKey = "SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guid"
        $v4Servers = Get-HklmValue -SubKey $v4SubKey -ValueName "NameServer"
        $v6Servers = Get-HklmValue -SubKey $v6SubKey -ValueName "NameServer"
        $hasGlobalV6 = $false
        try {
            foreach ($ua in $nic.GetIPProperties().UnicastAddresses) {
                if ($ua.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                    if (($ua.Address.GetAddressBytes()[0] -band 0xE0) -eq 0x20) { $hasGlobalV6 = $true; break }
                }
            }
        } catch {}
        $v6ActiveDns = @(Get-DnsClientServerAddress -InterfaceAlias $name -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
        $dohSubBase = "SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$guid\DohInterfaceSettings\Doh"
        $doh8888 = Get-HklmValue -SubKey "$dohSubBase\8.8.8.8" -ValueName "DohFlags"
        $doh8844 = Get-HklmValue -SubKey "$dohSubBase\8.8.4.4" -ValueName "DohFlags"
        if ($v4Servers -ne '8.8.8.8,8.8.4.4' -or $v6Servers -or ($v6ActiveDns.Count -gt 0) -or $doh8888 -ne 1 -or $doh8844 -ne 1) {
            if (-not $dohServerConfigured) {
                $wkSubBase = "SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers"
                if ((Get-HklmValue -SubKey "$wkSubBase\8.8.8.8" -ValueName "Flags") -ne 12 -or (Get-HklmValue -SubKey "$wkSubBase\8.8.4.4" -ValueName "Flags") -ne 12) {
                    foreach ($dohServer in @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844')) {
                        Set-DnsClientDohServerAddress -ServerAddress $dohServer -AutoUpgrade $true -AllowFallbackToUdp $true | Out-Null
                    }
                }
                $dohServerConfigured = $true
            }
            & netsh.exe interface ipv4 set dnsservers name="$name" static 8.8.8.8 primary validate=no | Out-Null
            & netsh.exe interface ipv4 add dnsservers name="$name" 8.8.4.4 index=2 validate=no | Out-Null
            & netsh.exe interface ipv6 delete dnsservers name="$name" all | Out-Null
            & netsh.exe interface ipv6 set dnsservers name="$name" source=static address=none validate=no | Out-Null
            if (-not $hasGlobalV6) { & netsh.exe interface ipv6 set interface "$name" routerdiscovery=disabled | Out-Null }
            if ($guid) {
                $dohBase = "HKLM:\$dohSubBase"
                foreach ($staleIp in @('1.1.1.1', '1.0.0.1', '::1')) {
                    if (Test-Path "$dohBase\$staleIp") { Remove-Item -Path "$dohBase\$staleIp" -Recurse -Force -ErrorAction SilentlyContinue }
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

    if ($dnsChanged) { & ipconfig.exe /flushdns | Out-Null }

    $currentBuildId = Get-SteamPubgBuildId -AcfPath $pubgAcfPath
    $savedState = Read-AutofixState -StatePath $stateFilePath
    $fallbackMainJsPath = $savedState.MainJsPath
    $warpRunBackup = @{}
    if ($savedState.WarpRunValues) { foreach ($k in $savedState.WarpRunValues.Keys) { $warpRunBackup[$k] = $savedState.WarpRunValues[$k] } }

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsData = Read-HostsSafely -Path $hostsPath
    $currentPinnedIp = $null; $pinnedLineCount = 0
    if ($hostsData.Success) {
        foreach ($line in $hostsData.Lines) {
            if ($line -match '^\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s+prod-live-front\.playbattlegrounds\.com\b') {
                if (-not $currentPinnedIp) { $currentPinnedIp = $Matches[1] }
                $pinnedLineCount++
            } elseif ($line -match 'prod-live-front\.playbattlegrounds\.com') { $pinnedLineCount++ }
        }
    }

    $dynamicDnsIps = @(
        Resolve-DnsName -Name "prod-live-front.playbattlegrounds.com" -Type A -ErrorAction SilentlyContinue
        Resolve-DnsName -Name "prod-live-front.playbattlegrounds.com" -Type A -NoHostsFile -ErrorAction SilentlyContinue
        Resolve-DnsName -Name "prod-live-cfentry.playbattlegrounds.com" -Type A -ErrorAction SilentlyContinue
    ) | Where-Object { $_.IPAddress -and $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -notmatch '^43\.' } | Select-Object -ExpandProperty IPAddress -Unique

    $curatedPool = @("3.162.66.12", "3.162.66.99", "108.157.32.117", "108.157.32.60", "108.157.254.53", "23.66.150.216", "104.69.151.226")
    $candidateIps = @(
        if ($currentPinnedIp -and $currentPinnedIp -notmatch '^43\.') { $currentPinnedIp }
        $dynamicDnsIps
        $curatedPool
    ) | Where-Object { $_ -and $_ -notmatch '^43\.' } | Select-Object -Unique | Select-Object -First 8

    $steamProbe = Start-SteamParallelProbe
    $bundleInfo = Resolve-LivePubgBundle -ProbeIps $candidateIps -FallbackMainJsPath $fallbackMainJsPath -SavedAppDir $savedState.AppDir -SavedAssets $savedState.Assets
    $mainJsPath = $bundleInfo.MainJsPath
    $cdnProbes = @(Start-CdnRaceProbes -CandidateIps $candidateIps -MainJsPath $mainJsPath)

    $integritySyncedCount = Sync-PubgIntegrityCheckHistory -BinariesWin64Dir $pubgBinariesWin64Dir -HistoryCsvPath $integrityCsvPath
    $prunedDemosCount = Clear-StalePubgDemos -DemosDir $demosDir
    Invoke-PubgBinaryPageCacheWarmup -BinariesWin64Dir $pubgBinariesWin64Dir

    try {
        $cmdProcs = @(([wmisearcher]"SELECT ProcessId, ParentProcessId, CommandLine FROM Win32_Process WHERE Name='cmd.exe' OR ProcessId=$PID").Get())
        $myParentPid = ($cmdProcs | Where-Object { $_.ProcessId -eq $PID } | Select-Object -First 1).ParentProcessId
        foreach ($cp in $cmdProcs) {
            if ($cp.ProcessId -ne $PID -and $cp.ProcessId -ne $myParentPid -and $cp.CommandLine -match 'goodbyedpi_(on|off)\.cmd' -and $cp.CommandLine -notmatch '(-NoWait|--nowait|--nopause)') {
                Stop-Process -Id $cp.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    try {
        $runKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Run", $true)
        if ($null -ne $runKey) {
            try {
                foreach ($warpVal in @("Cloudflare WARP", "CloudflareWARP")) {
                    $existingWarp = $runKey.GetValue($warpVal, $null)
                    if ($null -ne $existingWarp) {
                        $warpRunBackup[$warpVal] = [string]$existingWarp
                        $runKey.DeleteValue($warpVal, $false)
                    }
                }
            } finally { $runKey.Dispose() }
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
        $ifeoPrioMap = @{ "TslGame.exe" = 3; "ExecPubg.exe" = 3; "TslGame_BE.exe" = 2; "TslGame_ZK.exe" = 2 }
        foreach ($exeName in $ifeoPrioMap.Keys) {
            $targetPrio = $ifeoPrioMap[$exeName]
            $ifeoSub = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exeName\PerfOptions"
            if ((Get-HklmValue -SubKey $ifeoSub -ValueName "CpuPriorityClass") -ne $targetPrio) {
                $pk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($ifeoSub, $true)
                if ($null -ne $pk) { try { $pk.SetValue("CpuPriorityClass", $targetPrio, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $pk.Dispose() } }
            }
        }
        $tslIfeoSub = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\TslGame.exe\PerfOptions"
        if ((Get-HklmValue -SubKey $tslIfeoSub -ValueName "DefenderExclusionsV2") -ne 3) {
            $pf86 = ${env:ProgramFiles(x86)}
            Add-MpPreference -ExclusionPath @(
                $pubgInstallDir, "$env:LOCALAPPDATA\TslGame",
                (Join-Path $pf86 "Common Files\BattlEye"), (Join-Path $pf86 "Common Files\BattlEye\BEDaisy.sys"),
                "C:\Program Files\Common Files\PUBG", "C:\Program Files\Common Files\PUBG\navagio.sys"
            ) -ExclusionProcess @(
                "TslGame.exe", "TslGame_ZK.exe", "TslGame_BE.exe", "ExecPubg.exe",
                "BEService.exe", "BEService_pubg.exe", "BEService_x64.exe", "BEDaisy.sys",
                "zksvc.exe", "navagio.sys", "CoherentUI_Host.exe"
            ) -ErrorAction SilentlyContinue
            $pk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($tslIfeoSub, $true)
            if ($null -ne $pk) { try { $pk.SetValue("DefenderExclusionsV2", 3, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $pk.Dispose() } }
        }
    } catch {}

    $tasksDir = "$env:SystemRoot\System32\Tasks"
    $guardScriptPath = Join-Path $baseDir "pubg_wireless_and_hz_guard.ps1"
    if ([System.IO.File]::Exists($guardScriptPath)) {
        try {
            Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "PUBGWirelessAndHzGuard" -ErrorAction SilentlyContinue
            if (-not [System.IO.File]::Exists("$tasksDir\PUBGWirelessAndHzGuard")) {
                & schtasks.exe /create /tn "PUBGWirelessAndHzGuard" /tr "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$guardScriptPath`"" /sc onlogon /rl highest /it /f | Out-Null
            }
            $explorerPids = @(foreach ($ep in [System.Diagnostics.Process]::GetProcessesByName("explorer")) { $id = $ep.Id; $ep.Dispose(); $id })
            if ($explorerPids.Count -gt 0) {
                $guardProcs = @(([wmisearcher]"SELECT ProcessId, ParentProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe'").Get())
                foreach ($gp in $guardProcs) {
                    if ($gp.CommandLine -match 'pubg_wireless_and_hz_guard\.ps1' -and $explorerPids -contains [int]$gp.ParentProcessId) {
                        Stop-Process -Id ([int]$gp.ProcessId) -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 250
                    }
                }
            }
            $gCreated = $false
            $gProbe = New-Object System.Threading.Mutex($false, "Local\PUBGWirelessAndHzGuard_Mutex", [ref]$gCreated)
            $gProbe.Dispose()
            if ($gCreated) {
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$guardScriptPath`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    if ([System.IO.File]::Exists("$tasksDir\GoodbyeDPI-Toggle")) { Unregister-ScheduledTask -TaskName 'GoodbyeDPI-Toggle' -Confirm:$false | Out-Null }
    foreach ($taskName in @('GoodbyeDPI-On', 'GoodbyeDPI-Off', 'PUBGWirelessAndHzGuard')) {
        $taskXmlPath = "$tasksDir\$taskName"
        if ([System.IO.File]::Exists($taskXmlPath)) {
            $taskXml = [System.IO.File]::ReadAllText($taskXmlPath)
            if ($taskXml -notmatch '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' -or $taskXml -notmatch '<MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>' -or $taskXml -notmatch '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' -or $taskXml -notmatch '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>') {
                $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel
                Set-ScheduledTask -TaskName $taskName -Settings $s | Out-Null
            }
        }
    }

    $raceResult = Wait-CdnRaceProbes -Probes $cdnProbes -PinnedIp $currentPinnedIp
    $bestIp = $raceResult.BestIp; $bestTime = $raceResult.BestTime; $bestHttp = $raceResult.BestHttp
    if ($bestIp -and $currentPinnedIp -and $currentPinnedIp -notmatch '^43\.' -and $pinnedLineCount -eq 1 -and $raceResult.PinnedIpTime -lt 999.0) {
        if (($raceResult.PinnedIpTime - $bestTime) -le 0.040) {
            $bestIp = $currentPinnedIp; $bestTime = $raceResult.PinnedIpTime; $bestHttp = $raceResult.PinnedIpHttp
        }
    }

    if ($hostsData.Success) {
        if ($bestIp) {
            if ($bestIp -ne $currentPinnedIp -or $pinnedLineCount -ne 1) {
                $cleanLines = @($hostsData.Lines | Where-Object { $_ -notmatch "prod-live-front\.playbattlegrounds\.com" })
                $cleanLines += "$bestIp prod-live-front.playbattlegrounds.com"
                if (Write-HostsSafely -Path $hostsPath -Lines $cleanLines) { & ipconfig.exe /flushdns | Out-Null }
            }
        } elseif ($pinnedLineCount -gt 0) {
            $cleanLines = @($hostsData.Lines | Where-Object { $_ -notmatch "prod-live-front\.playbattlegrounds\.com" })
            if (Write-HostsSafely -Path $hostsPath -Lines $cleanLines) { & ipconfig.exe /flushdns | Out-Null }
        }
    }


































































































    $mutableEntryUrls = @(
        "https://prod-live-front.playbattlegrounds.com?provider=steam",
        "https://prod-live-front.playbattlegrounds.com/?provider=steam",
        "https://prod-live-front.playbattlegrounds.com/index.html",
        "https://prod-live-front.playbattlegrounds.com/index.html?provider=steam",
        "https://prod-live-front.playbattlegrounds.com/index.html?provider=steam&hl=en"
    )
    if ($bundleInfo.AppDir) {
        $mutableEntryUrls += "https://prod-live-front.playbattlegrounds.com$($bundleInfo.AppDir)/index.html"
        $mutableEntryUrls += "https://prod-live-front.playbattlegrounds.com$($bundleInfo.AppDir)/index.html?provider=steam"
        $mutableEntryUrls += "https://prod-live-front.playbattlegrounds.com$($bundleInfo.AppDir)/index.html?provider=steam&hl=en"
    }
    if ($savedState.AppDir -and $savedState.AppDir -ne $bundleInfo.AppDir) {
        $mutableEntryUrls += "https://prod-live-front.playbattlegrounds.com$($savedState.AppDir)/index.html"
        $mutableEntryUrls += "https://prod-live-front.playbattlegrounds.com$($savedState.AppDir)/index.html?provider=steam"
        $mutableEntryUrls += "https://prod-live-front.playbattlegrounds.com$($savedState.AppDir)/index.html?provider=steam&hl=en"
    }
    $mutableEntryHdrSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($mUrl in $mutableEntryUrls) { [void]$mutableEntryHdrSet.Add("$(Get-UrlMd5Hex -Url $mUrl).hdr") }
    $immutableAssetHdrSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($iPath in @($bundleInfo.MainJsPath, $savedState.MainJsPath) + @($bundleInfo.Assets) + @($savedState.Assets)) {
        if ($iPath) { [void]$immutableAssetHdrSet.Add("$(Get-UrlMd5Hex -Url "https://prod-live-front.playbattlegrounds.com$iPath").hdr") }
    }
    $patchChanged = (-not $savedState.AppDir) -or ($bundleInfo.AppDir -and $savedState.AppDir -ne $bundleInfo.AppDir) -or ($currentBuildId -and $savedState.BuildId -ne $currentBuildId)
    if (-not [System.IO.Directory]::Exists($cohCacheDir)) { try { [System.IO.Directory]::CreateDirectory($cohCacheDir) | Out-Null } catch {} }
    if ([System.IO.Directory]::Exists($cohCacheDir)) {
        $repairedCount = 0; $refreshedCount = 0; $warmedCount = 0
        $staleCutoffUtc = [DateTime]::UtcNow.AddDays(-14)
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
                $isMutableEntry = $mutableEntryHdrSet.Contains($f.Name)
                $headLines = $null
                if ($f.Length -eq 0 -or $null -eq $ctxFile -or $ctxFile.Length -eq 0) {
                    $corrupt = $true
                } elseif ($ctxFile.LastWriteTimeUtc -lt $staleCutoffUtc) {
                    $corrupt = $true
                } elseif ($patchChanged -and $isMutableEntry) {
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
                            } else {
                                foreach ($hLine in $headLines) {
                                    if ($hLine -match '(?i)(Server:\s*Lego Server|X-NWS-LOG-UUID:|playbattlegrounds\.com\.cn)') { $corrupt = $true; break }
                                    if ($hLine -match '(?i)^Content-Length:\s*(\d+)') {
                                        $cl = 0L
                                        if ([long]::TryParse($Matches[1], [ref]$cl) -and $cl -ne $ctxFile.Length) { $corrupt = $true; break }
                                    }
                                    if ($hLine -match '(?i)(/index\.html|/\?provider=)' -or ($hLine -match '(?i)^Content-Type:\s*text/html' -and -not $immutableAssetHdrSet.Contains($f.Name))) {
                                        $isMutableEntry = $true
                                    }
                                }
                            }
                        }
                    } catch { $corrupt = $true }
                }
                if ($corrupt) {
                    $hdrRemoved = $false
                    try {
                        [System.IO.File]::SetAttributes($f.FullName, [System.IO.FileAttributes]::Normal)
                        $f.Delete()
                        $hdrRemoved = (-not [System.IO.File]::Exists($f.FullName))
                    } catch {}
                    if ($hdrRemoved) {
                        if ($null -ne $ctxFile -and [System.IO.File]::Exists($ctxFile.FullName)) {
                            try { [System.IO.File]::SetAttributes($ctxFile.FullName, [System.IO.FileAttributes]::Normal); $ctxFile.Delete() } catch {}
                        }
                        $repairedCount++
                    }
                } elseif (-not $isMutableEntry) {
                    $validHdrList.Add([PSCustomObject]@{ File = $f; Lines = $headLines })
                }
            } elseif ($f.Extension -eq '.ctx') {
                $hdrName = [System.IO.Path]::ChangeExtension($f.Name, '.hdr')
                if ((-not $byName.ContainsKey($hdrName)) -or ($f.LastWriteTimeUtc -lt $staleCutoffUtc)) {
                    try {
                        [System.IO.File]::SetAttributes($f.FullName, [System.IO.FileAttributes]::Normal)
                        $f.Delete()
                        if (-not [System.IO.File]::Exists($f.FullName)) { $repairedCount++ }
                    } catch {}
                }
            }
        }
        $cdnIpForWarm = if ($bestIp) { $bestIp } elseif ($bundleInfo.AliveIp) { $bundleInfo.AliveIp } else { $currentPinnedIp }
        if ($cdnIpForWarm -and $bundleInfo.Assets.Count -gt 0) {
            foreach ($assetPath in $bundleInfo.Assets) {
                $assetHash = Get-UrlMd5Hex -Url "https://prod-live-front.playbattlegrounds.com$assetPath"
                $assetHdr = Join-Path $cohCacheDir "$assetHash.hdr"
                $assetCtx = Join-Path $cohCacheDir "$assetHash.ctx"
                if (-not [System.IO.File]::Exists($assetHdr) -or -not [System.IO.File]::Exists($assetCtx)) {
                    if (Save-CohCacheAssetFromCdn -AssetPath $assetPath -CdnIp $cdnIpForWarm -CohCacheDir $cohCacheDir) { $warmedCount++ }
                }
            }
        }
        if ($validHdrList.Count -gt 0) {
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
                        [System.IO.File]::SetAttributes($item.File.FullName, [System.IO.FileAttributes]::Normal)
                        [System.IO.File]::WriteAllText($item.File.FullName, (($hl -join "`n") + "`n"), $utf8NoBom)
                        $refreshedCount++
                    } catch {}
                }
            }
        }
        if ($repairedCount -gt 0) { Write-Host "  [+] Da don dep $repairedCount file cache Coherent GT bi loi/cu (>14 ngay)." }
        if ($warmedCount -gt 0) { Write-Host "  [+] Da nap truoc $warmedCount file Lobby bundle moi ($($bundleInfo.AppDir)) vao CohCache." }
        if ($refreshedCount -gt 0) { Write-Host "  [+] Da gia han 24h TTL cho $refreshedCount file cache Coherent GT ($($bundleInfo.AppDir))." }






    }


    if ($integritySyncedCount -gt 0) {
        Write-Host "  [+] Da dong bo $integritySyncedCount/559 file IntegrityCheckHistory.csv (tiet kiem 22.48 GB SHA-1)."
    }
    if ($prunedDemosCount -gt 0) {
        Write-Host "  [+] Da don dep $prunedDemosCount ban ghi Replay cu (>14 ngay, khong khoa)."
    }

    $statePinnedIp = if ($bestIp) { $bestIp } elseif ($currentPinnedIp) { $currentPinnedIp } else { "" }
    Write-AutofixState -StatePath $stateFilePath -BuildId $currentBuildId -AppDir $bundleInfo.AppDir -MainJsPath $mainJsPath -Assets $bundleInfo.Assets -PinnedIp $statePinnedIp -WarpRunValues $warpRunBackup

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
$gdpiSvc = Get-Service -Name "GoodbyeDPI" -ErrorAction SilentlyContinue
$gdpiStatus = if ($null -ne $gdpiSvc) { [string]$gdpiSvc.Status } else { "NotInstalled" }
$gdpiPid = (Get-Process -Name "goodbyedpi" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id)
$winDivertSvc = Get-Service -Name "WinDivert*" -ErrorAction SilentlyContinue | Select-Object -First 1
$winDivertStatus = if ($null -ne $winDivertSvc) { "$($winDivertSvc.Name): $($winDivertSvc.Status)" } else { "Active via Service" }

if ($env:SVC_OK -eq "0" -or ($env:SVC_OK -eq "1" -and $gdpiStatus -ne "Running")) {
    Write-Host "LOI: GoodbyeDPI khong bat duoc (Service=$gdpiStatus). Chay CAI_DAT_1_CLICK.cmd de sua."
} else {
    Write-Host "========================================================================="
    Write-Host (" TRANG THAI DICH VU : GoodbyeDPI = {0} (PID: {1}) | {2}" -f $gdpiStatus, $(if ($gdpiPid) { $gdpiPid } else { "N/A" }), $winDivertStatus)
    Write-Host (" CDN & COHCACHE     : IP = {0} | Bundle = {1} ({2} files)" -f $(if ($statePinnedIp) { $statePinnedIp } else { "Google DNS" }), $bundleInfo.AppDir, $bundleInfo.Assets.Count)
    Write-Host " Luu y: GoodbyeDPI chay ngam trong Windows Services, KHONG tat khi"
    Write-Host " ban dong cua so nay. Muon tat han hay dung nut `"GoodbyeDPI TAT`"."
    Write-Host "========================================================================="
}
Write-Host ""
$noWait = $false
foreach ($a in $args) {
    if ($a -match '^(-NoWait|--nowait|--nopause)$') {
        $noWait = $true
    }
}
if (-not $noWait) {
    [void](Read-Host "Nhan Enter hoac dong cua so nay...")
}
exit 0
