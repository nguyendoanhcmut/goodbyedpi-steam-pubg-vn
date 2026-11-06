function Set-IniKeyValueInSection {
    param([AllowEmptyString()][string]$Content, [string]$SectionHeader, [string]$Key, [AllowEmptyString()][string]$Value)
    $escapedHeader  = [regex]::Escape($SectionHeader)
    $escapedKey     = [regex]::Escape($Key)
    $sectionPattern = "(?ms)(^\[$escapedHeader\]\r?\n)(.*?)(?=^\[|\z)"
    if ($Content -match $sectionPattern) {
        return ([regex]::new($sectionPattern)).Replace($Content, {
            param($m)
            $hdr        = $m.Groups[1].Value
            $body       = $m.Groups[2].Value
            $keyPattern = "(?m)^(\s*$escapedKey\s*=)[^\r\n]*"
            if ($body -match $keyPattern) {
                $safeVal = $Value.Replace('$', '$$')
                $body    = [regex]::Replace($body, $keyPattern, "`${1}$safeVal")
            } else {
                $trimmed = $body.TrimEnd("`r", "`n")
                $suffix  = if ($body -match "(\r?\n){2,}\z") { "`r`n`r`n" } else { "`r`n" }
                $body    = if ($trimmed.Length -gt 0) { "$trimmed`r`n$Key=$Value$suffix" } else { "$Key=$Value$suffix" }
            }
            return ($hdr + $body)
        }, 1)
    }
    return ($Content.TrimEnd() + "`r`n`r`n[$SectionHeader]`r`n$Key=$Value`r`n")
}

function Remove-IniSection {
    param([AllowEmptyString()][string]$Content, [string]$SectionHeader)
    if ([string]::IsNullOrEmpty($Content)) { return "" }
    $escapedHeader  = [regex]::Escape($SectionHeader)
    $sectionPattern = "(?ms)^\[$escapedHeader\]\r?\n.*?(?=^\[|\z)"
    $cleaned        = [regex]::Replace($Content, $sectionPattern, "")
    return (([regex]::Replace($cleaned, "(\r?\n){3,}", "`r`n`r`n")).Trim() + "`r`n")
}

function Optimize-PubgIniFiles {
    param(
        [string]$TargetConfigDir = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor", [string]$TargetGraphicsAPI = "DX11",
        [int]$TargetResX = 0, [int]$TargetResY = 0, [int]$TargetScale = 80, [int]$TargetFpsCap = 60, [bool]$TurnOffHrtf = $false,
        [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue))
    )
    $inv          = [System.Globalization.CultureInfo]::InvariantCulture
    $utf8NoBom    = New-Object System.Text.UTF8Encoding($false)
    $clampedScale = [math]::Max(70, [math]::Min(100, $TargetScale))
    $fpsCapVal    = if ($TargetFpsCap -gt 0) { $TargetFpsCap } else { 60 }
    $scaleStr     = $clampedScale.ToString("F6", $inv)
    $fpsStr       = $fpsCapVal.ToString("F6", $inv)

    $deskW = 1920; $deskH = 1080
    $nativeType  = ([System.Management.Automation.PSTypeName]'PubgIrisXeNative').Type
    $canCheckRes = ($null -ne $nativeType -and $null -ne $nativeType.GetMethod('IsDisplayResolutionSupported'))
    if ($null -ne $nativeType) {
        if ($null -ne $nativeType.GetMethod('GetCurrentDesktopResolution', [type[]]@([int].MakeByRefType(), [int].MakeByRefType()))) {
            [void][PubgIrisXeNative]::GetCurrentDesktopResolution([ref]$deskW, [ref]$deskH)
        } else {
            $ef = $nativeType.GetMethod('EnumDisplaySettingsA', [System.Reflection.BindingFlags]'Public,NonPublic,Static')
            if ($null -ne $ef) {
                $dm = New-Object PubgIrisXeNative+DEVMODEA; $dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf($dm)
                $callArgs = [object[]]@($null, -1, $dm)
                if ($ef.Invoke($null, $callArgs) -and $callArgs[2].dmPelsWidth -gt 0) { $deskW = [int]$callArgs[2].dmPelsWidth; $deskH = [int]$callArgs[2].dmPelsHeight }
            }
        }
    }
    $is16By10 = (($deskW * 10) -eq ($deskH * 16))
    $autoResY = if ($is16By10 -and (-not $canCheckRes -or [PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800))) { 800 } else { 720 }
    if ($TargetResX -le 0 -or $TargetResY -le 0) { $effectiveResX = 1280; $effectiveResY = $autoResY } else { $effectiveResX = $TargetResX; $effectiveResY = $TargetResY }
    if ($canCheckRes -and -not [PubgIrisXeNative]::IsDisplayResolutionSupported($effectiveResX, $effectiveResY)) {
        if ($is16By10 -and [PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800)) { $effectiveResX = 1280; $effectiveResY = 800 }
        elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 720)) { $effectiveResX = 1280; $effectiveResY = 720 }
        elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800)) { $effectiveResX = 1280; $effectiveResY = 800 }
        elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1366, 768)) { $effectiveResX = 1366; $effectiveResY = 768 }
        else { $effectiveResX = $deskW; $effectiveResY = $deskH }
    }

    $engineIni = Join-Path $TargetConfigDir "Engine.ini"
    $gusIni    = Join-Path $TargetConfigDir "GameUserSettings.ini"
    $engineBak = "$engineIni.irisxe.bak"; $gusBak = "$gusIni.irisxe.bak"
    $engineUpdated = $false; $gusUpdated = $false

    if ([System.IO.File]::Exists($engineIni)) {
        if (-not $IsDryRun) {
            [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
            if (-not [System.IO.File]::Exists($engineBak)) {
                [System.IO.File]::Copy($engineIni, $engineBak, $false)
                [System.IO.File]::SetAttributes($engineBak, [System.IO.FileAttributes]::Normal)
            }
            $rawEngine = [System.IO.File]::ReadAllText($engineIni, [System.Text.Encoding]::UTF8)
            $rawEngine = Remove-IniSection -Content $rawEngine -SectionHeader "SystemSettings"
            $rawEngine = Remove-IniSection -Content $rawEngine -SectionHeader "/Script/Engine.RecastNavMesh"

            $movieTable = [ordered]@{ "bWaitForMoviesToComplete" = "False"; "bMoviesAreSkippable" = "True"; "-StartupMovies" = "" }
            foreach ($kv in $movieTable.GetEnumerator()) {
                $rawEngine = Set-IniKeyValueInSection -Content $rawEngine -SectionHeader "/Script/MoviePlayer.MoviePlayerSettings" -Key $kv.Key -Value $kv.Value
            }

            $streamingTable = [ordered]@{
                "s.AsyncLoadingThreadEnabled"                       = "True"
                "s.AsyncLoadingTimeLimit"                           = "3.000000"
                "s.PriorityAsyncLoadingExtraTime"                   = "12.000000"
                "s.AsyncLoadingUseFullTimeLimit"                    = "False"
                "s.LevelStreamingActorsUpdateTimeLimit"             = "3.000000"
                "s.LevelStreamingComponentsRegistrationGranularity" = "5"
            }
            foreach ($kv in $streamingTable.GetEnumerator()) {
                $rawEngine = Set-IniKeyValueInSection -Content $rawEngine -SectionHeader "/Script/Engine.StreamingSettings" -Key $kv.Key -Value $kv.Value
            }
            [System.IO.File]::WriteAllText($engineIni, $rawEngine, $utf8NoBom)
            [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
        }
        $engineUpdated = $true
    }

    if ([System.IO.File]::Exists($gusIni)) {
        if (-not $IsDryRun) {
            # Clear ReadOnly so PUBG can save user keybinds, mouse sensitivity, and reticle changes on exit.
            [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
            if (-not [System.IO.File]::Exists($gusBak)) {
                [System.IO.File]::Copy($gusIni, $gusBak, $false)
                [System.IO.File]::SetAttributes($gusBak, [System.IO.FileAttributes]::Normal)
            }
            $rawGus = [System.IO.File]::ReadAllText($gusIni, [System.Text.Encoding]::UTF8)

            $engineGusTable = [ordered]@{ "bUseDesiredScreenHeight" = "False"; "GraphicsAPI" = $TargetGraphicsAPI }
            foreach ($kv in $engineGusTable.GetEnumerator()) {
                $rawGus = Set-IniKeyValueInSection -Content $rawGus -SectionHeader "/Script/Engine.GameUserSettings" -Key $kv.Key -Value $kv.Value
            }

            $hrtfToken = if ($TurnOffHrtf) { "False" } else { "True" }
            # EFrameRateLimitType reflection tokens in TslGame.exe are Unlimited, Fixed_30, Fixed_60, Customizable, and DisplayBased.
            $tslGusTable = [ordered]@{
                "GraphicsAPI"                      = $TargetGraphicsAPI
                "ScreenScale"                      = $scaleStr
                "LobbyFrameRateLimitType"          = "Fixed_30"
                "InGameFrameRateLimitType"         = "Customizable"
                "InGameCustomFrameRateLimit"       = $fpsStr
                "FrameRateLimit"                   = $fpsStr
                "bUseInGameSmoothedFrameRate"      = "False"
                "bMotionBlur"                      = "False"
                "bSharpen"                         = "True"
                "bUseCharacterCapture"             = "False"
                "bUseClientReplay"                 = "False"
                "bUseKillCam"                      = "False"
                "bUseLiveStreaming"                = "False"
                "bPreloadingMap"                   = "False"
                "bUseVSync"                        = "False"
                "bUseDynamicResolution"            = "False"
                "ResolutionSizeX"                  = "$effectiveResX"
                "ResolutionSizeY"                  = "$effectiveResY"
                "LastUserConfirmedResolutionSizeX" = "$effectiveResX"
                "LastUserConfirmedResolutionSizeY" = "$effectiveResY"
                "DesiredScreenWidth"               = "$effectiveResX"
                "DesiredScreenHeight"              = "$effectiveResY"
                "FullscreenMode"                   = "0"
                "LastConfirmedFullscreenMode"      = "0"
                "PreferredFullscreenMode"          = "0"
                "UpscalingMethod"                  = "None"
                "GraphicsAPIBeforeFSR"             = "-1"
                "bIsEnabledHrtfRemoteWeaponSound"  = $hrtfToken
            }
            foreach ($kv in $tslGusTable.GetEnumerator()) {
                $rawGus = Set-IniKeyValueInSection -Content $rawGus -SectionHeader "/Script/TslGame.TslGameUserSettings" -Key $kv.Key -Value $kv.Value
            }

            # TslPersistantData duplicates bUseKillCam, bUseLiveStreaming, and bIsEnabledHrtfRemoteWeaponSound and overrides top-level keys on load.
            $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbUseKillCam=)(True|False)', '${1}False')
            $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbUseLiveStreaming=)(True|False)', '${1}False')
            $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbIsEnabledHrtfRemoteWeaponSound=)(True|False)', "`${1}$hrtfToken")

            $scalabilityTable = [ordered]@{
                "sg.ResolutionQuality" = $scaleStr; "sg.ViewDistanceQuality" = "0"; "sg.AntiAliasingQuality" = "0"; "sg.ShadowQuality" = "0"
                "sg.PostProcessQuality" = "0"; "sg.TextureQuality" = "0"; "sg.EffectsQuality" = "0"; "sg.FoliageQuality" = "0"; "sg.ShadingQuality" = "0"; "sg.VSyncQuality" = "0"
            }
            foreach ($kv in $scalabilityTable.GetEnumerator()) {
                $rawGus = Set-IniKeyValueInSection -Content $rawGus -SectionHeader "ScalabilityGroups" -Key $kv.Key -Value $kv.Value
            }

            [System.IO.File]::WriteAllText($gusIni, $rawGus, $utf8NoBom)
            [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
        }
        $gusUpdated = $true
    }

    return [PSCustomObject]@{
        EngineUpdated = $engineUpdated; GusUpdated = $gusUpdated; AppliedResolutionX = $effectiveResX; AppliedResolutionY = $effectiveResY
        AppliedScreenScale = $clampedScale; InternalRenderX = [int][math]::Round(($effectiveResX * $clampedScale) / 100.0); InternalRenderY = [int][math]::Round(($effectiveResY * $clampedScale) / 100.0)
    }
}

function Restore-PubgIniFiles {
    param([string]$TargetConfigDir = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor", [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue)))
    $engineIni = Join-Path $TargetConfigDir "Engine.ini"
    $gusIni    = Join-Path $TargetConfigDir "GameUserSettings.ini"
    $engineBak = "$engineIni.irisxe.bak"
    $gusBak    = "$gusIni.irisxe.bak"
    $engineRestored = $false
    $gusRestored    = $false

    if ([System.IO.File]::Exists($engineBak)) {
        if (-not $IsDryRun) {
            if ([System.IO.File]::Exists($engineIni)) { [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal) }
            [System.IO.File]::Copy($engineBak, $engineIni, $true)
            [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($engineBak)
        }
        $engineRestored = $true
    } elseif ([System.IO.File]::Exists($engineIni) -and -not $IsDryRun) {
        [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
    }

    if ([System.IO.File]::Exists($gusBak)) {
        if (-not $IsDryRun) {
            $liveGus = if ([System.IO.File]::Exists($gusIni)) { [System.IO.File]::ReadAllText($gusIni, [System.Text.Encoding]::UTF8) } else { "" }
            $bakGus  = [System.IO.File]::ReadAllText($gusBak, [System.Text.Encoding]::UTF8)
            if ([System.IO.File]::Exists($gusIni)) { [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal) }
            [System.IO.File]::Copy($gusBak, $gusIni, $true)
            if (-not [string]::IsNullOrEmpty($liveGus)) {
                $changed  = $false
                $prefKeys = @("CustomInputSettins", "DefaultReticleBrightnessMap", "RifleCrosshairSettings", "ShotgunCrosshairSettings", "PistolCrosshairSettings", "ThrowableCrosshairSettings")
                foreach ($pk in $prefKeys) {
                    if ($liveGus -match "(?m)^(?<ln>$pk=[^\r\n]*)") {
                        $liveLine = $Matches['ln']
                        if ($bakGus -match "(?m)^(?<bln>$pk=[^\r\n]*)" -and $Matches['bln'] -cne $liveLine) {
                            $bakGus  = [regex]::Replace($bakGus, "(?m)^$pk=[^\r\n]*", $liveLine.Replace('$', '$$'))
                            $changed = $true
                        }
                    }
                }
                if ($liveGus -match "(?m)^(?<ltp>TslPersistantData=[^\r\n]*)") {
                    $liveTp = $Matches['ltp']
                    if ($bakGus -match "(?m)^(?<btp>TslPersistantData=[^\r\n]*)") {
                        $bakTp = $Matches['btp']
                        if ($bakTp -match '(?i)\bbUseKillCam=(?<kc>True|False)') { $liveTp = [regex]::Replace($liveTp, '(?i)(\bbUseKillCam=)(True|False)', "`${1}$($Matches['kc'])") }
                        if ($bakTp -match '(?i)\bbUseLiveStreaming=(?<ls>True|False)') { $liveTp = [regex]::Replace($liveTp, '(?i)(\bbUseLiveStreaming=)(True|False)', "`${1}$($Matches['ls'])") }
                        if ($bakTp -match '(?i)\bbIsEnabledHrtfRemoteWeaponSound=(?<hr>True|False)') { $liveTp = [regex]::Replace($liveTp, '(?i)(\bbIsEnabledHrtfRemoteWeaponSound=)(True|False)', "`${1}$($Matches['hr'])") }
                        if ($liveTp -cne $bakTp) {
                            $bakGus  = [regex]::Replace($bakGus, "(?m)^TslPersistantData=[^\r\n]*", $liveTp.Replace('$', '$$'))
                            $changed = $true
                        }
                    }
                }
                if ($changed) {
                    [System.IO.File]::WriteAllText($gusIni, $bakGus, (New-Object System.Text.UTF8Encoding($false)))
                }
            }
            [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($gusBak)
        }
        $gusRestored = $true
    } elseif ([System.IO.File]::Exists($gusIni) -and -not $IsDryRun) {
        [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
    }

    return [PSCustomObject]@{ EngineRestored = $engineRestored; GusRestored = $gusRestored }
}

function Measure-PubgDemosFolder {
    param([bool]$RemoveOldDemos = $false, [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue)), [string]$DemosDir = (Join-Path $env:LOCALAPPDATA "TslGame\Saved\Demos"))
    if (-not (Test-Path -LiteralPath $DemosDir)) {
        return [PSCustomObject]@{ MatchCount = 0; FileCount = 0; SizeMB = 0.0; Cleaned = $false }
    }
    $matchDirs = @(Get-ChildItem -LiteralPath $DemosDir -Directory -ErrorAction SilentlyContinue)
    $allFiles  = @(Get-ChildItem -LiteralPath $DemosDir -Recurse -File -ErrorAction SilentlyContinue)
    $bytes     = ($allFiles | Measure-Object Length -Sum).Sum
    $sizeMB    = if ($bytes -gt 0) { [math]::Round($bytes / 1MB, 2) } else { 0.0 }
    $cleaned   = $false
    if ($RemoveOldDemos -and -not $IsDryRun -and $matchDirs.Count -gt 0) {
        foreach ($md in $matchDirs) {
            try { Remove-Item -LiteralPath $md.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
        $cleaned = $true
    }
    return [PSCustomObject]@{ MatchCount = $matchDirs.Count; FileCount = $allFiles.Count; SizeMB = $sizeMB; Cleaned = $cleaned }
}

function Clear-StaleDxShaderCacheSafely {
    param([bool]$ForceRebuild = $false, [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue)))
    if ([System.Diagnostics.Process]::GetProcessesByName("TslGame").Length -gt 0) {
        return [PSCustomObject]@{ DeletedFiles = 0; SkippedLocked = 0; BytesFreed = 0L }
    }
    $dirs = @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\Intel\ShaderCache",
        "$env:USERPROFILE\AppData\LocalLow\Intel\ShaderCache"
    )
    $deleted    = 0
    $locked     = 0
    $bytesFreed = 0L
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $files = @(Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $shouldRemove = $ForceRebuild -or ($f.Length -eq 0) -or ($f.Extension -ieq ".tmp")
            if (-not $shouldRemove) { continue }
            try {
                $len = $f.Length
                # Probe with FileShare.None first so files actively mapped by dwm.exe are skipped cleanly.
                $fs = [System.IO.File]::Open($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $fs.Close()
                $fs.Dispose()
                if (-not $IsDryRun) {
                    [System.IO.File]::Delete($f.FullName)
                }
                $deleted++
                $bytesFreed += $len
            } catch {
                $locked++
            }
        }
    }
    return [PSCustomObject]@{ DeletedFiles = $deleted; SkippedLocked = $locked; BytesFreed = $bytesFreed }
}
