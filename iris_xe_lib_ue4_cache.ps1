function Set-IniKeyValueInSection {
    param([AllowEmptyString()][string]$Content, [string]$SectionHeader, [string]$Key, [AllowEmptyString()][string]$Value)
    $escapedHeader  = [regex]::Escape($SectionHeader)
    $escapedKey     = [regex]::Escape($Key)
    $nextSecLookahead = "(?=^\[(?:/[^\]\r\n]+|ScalabilityGroups|SystemSettings|PacketSimulationSettings|Voice|Audio|Internationalization|[A-Za-z0-9_]+\.[A-Za-z0-9_.]+|[A-Za-z0-9_]+@[0-9]+)\][ \t]*(?:\r?\n|\z)|\z)"
    $sectionPattern = "(?ms)(^\[$escapedHeader\][ \t]*\r?\n)(.*?)$nextSecLookahead"
    if ($Content -match $sectionPattern) {
        return ([regex]::new($sectionPattern)).Replace($Content, {
            param($m)
            $hdr        = "[$SectionHeader]`r`n"
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
    $trimmedContent = if ($null -ne $Content) { $Content.TrimEnd() } else { "" }
    if ([string]::IsNullOrEmpty($trimmedContent)) {
        return "[$SectionHeader]`r`n$Key=$Value`r`n"
    }
    return ($trimmedContent + "`r`n`r`n[$SectionHeader]`r`n$Key=$Value`r`n")
}

function Remove-IniSection {
    param([AllowEmptyString()][string]$Content, [string]$SectionHeader)
    if ([string]::IsNullOrWhiteSpace($Content)) { return "" }
    $escapedHeader    = [regex]::Escape($SectionHeader)
    $nextSecLookahead = "(?=^\[(?:/[^\]\r\n]+|ScalabilityGroups|SystemSettings|PacketSimulationSettings|Voice|Audio|Internationalization|[A-Za-z0-9_]+\.[A-Za-z0-9_.]+|[A-Za-z0-9_]+@[0-9]+)\][ \t]*(?:\r?\n|\z)|\z)"
    $sectionPattern   = "(?ms)^\[$escapedHeader\][ \t]*\r?\n.*?$nextSecLookahead"
    $cleaned          = [regex]::Replace($Content, $sectionPattern, "")
    $trimmed          = ([regex]::Replace($cleaned, "(\r?\n){3,}", "`r`n`r`n")).Trim()
    if ([string]::IsNullOrEmpty($trimmed)) { return "" }
    return ($trimmed + "`r`n")
}

function Resolve-PubgQualityPreset {
    param(
        [string]$Preset = "NativeCrisp",
        [int]$DeskW = 1920,
        [int]$DeskH = 1080,
        [int]$RequestedResX = 0,
        [int]$RequestedResY = 0,
        [int]$RequestedScale = 0,
        [int]$RequestedTextureQuality = -1,
        [int]$RequestedAntiAliasingQuality = -1,
        [double]$PeakBandwidthGBs = 83.2,
        [bool]$CanCheckRes = $false
    )
    $is16By10 = ($DeskW -gt 0 -and $DeskH -gt 0 -and (($DeskW * 10) -eq ($DeskH * 16)))
    $nativeCapW = if ($DeskW -gt 0 -and $DeskW -le 1920) { $DeskW } else { 1920 }
    $nativeCapH = if ($DeskW -gt 0 -and $DeskW -le 1920 -and $DeskH -gt 0) { $DeskH } elseif ($is16By10) { 1200 } else { 1080 }
    if ($CanCheckRes -and -not [PubgIrisXeNative]::IsDisplayResolutionSupported($nativeCapW, $nativeCapH)) {
        if ($is16By10 -and [PubgIrisXeNative]::IsDisplayResolutionSupported(1920, 1200)) { $nativeCapW = 1920; $nativeCapH = 1200 }
        elseif ($is16By10 -and [PubgIrisXeNative]::IsDisplayResolutionSupported(1680, 1050)) { $nativeCapW = 1680; $nativeCapH = 1050 }
        elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1920, 1080)) { $nativeCapW = 1920; $nativeCapH = 1080 }
        elseif ($DeskW -gt 0 -and $DeskH -gt 0) { $nativeCapW = $DeskW; $nativeCapH = $DeskH }
    }
    $lowResY = if ($is16By10 -and (-not $CanCheckRes -or [PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800))) { 800 } else { 720 }

    $effectivePreset = if ([string]::IsNullOrWhiteSpace($Preset)) { "NativeCrisp" } else { $Preset.Trim() }
    switch ($effectivePreset) {
        "1" { $effectivePreset = "NativeCrisp" }
        "2" { $effectivePreset = "HighClarity" }
        "3" { $effectivePreset = "BalancedPlus" }
        "4" { $effectivePreset = "PerfSharp" }
        "5" { $effectivePreset = "UltraPerf" }
    }
    if ($RequestedResX -gt 0 -and $RequestedResY -gt 0 -and $effectivePreset -eq "NativeCrisp") {
        # Caller explicitly provided TargetResX/TargetResY without changing Preset; treat as Custom override for backward compatibility.
        $effectivePreset = "Custom"
    }

    $resX = $nativeCapW; $resY = $nativeCapH; $scale = 70; $texQ = 1; $aaQ = 0
    switch ($effectivePreset) {
        "NativeCrisp" {
            if ($PeakBandwidthGBs -gt 0 -and $PeakBandwidthGBs -lt 45.0) {
                $resX = 1280; $resY = $lowResY; $scale = 100; $texQ = 1; $aaQ = 0
            } else {
                $resX = $nativeCapW; $resY = $nativeCapH; $scale = 70; $texQ = 1; $aaQ = 0
            }
        }
        "PerfSharp" {
            $resX = 1280; $resY = $lowResY; $scale = 100; $texQ = 1; $aaQ = 0
        }
        "BalancedPlus" {
            if ($is16By10) {
                $resX = 1680; $resY = 1050; $scale = 80; $texQ = 1; $aaQ = 0
            } else {
                $resX = 1600; $resY = 900; $scale = 85; $texQ = 1; $aaQ = 0
            }
        }
        "HighClarity" {
            if ($is16By10) {
                $resX = $nativeCapW; $resY = $nativeCapH; $scale = 75; $texQ = 1; $aaQ = 0
            } else {
                $resX = $nativeCapW; $resY = $nativeCapH; $scale = 80; $texQ = 1; $aaQ = 0
            }
        }
        "UltraPerf" {
            $resX = 1280; $resY = $lowResY; $scale = 80; $texQ = 0; $aaQ = 0
        }
        default {
            $resX = if ($RequestedResX -gt 0) { $RequestedResX } else { 1280 }
            $resY = if ($RequestedResY -gt 0) { $RequestedResY } else { $lowResY }
            $scale = if ($RequestedScale -gt 0) { $RequestedScale } else { 80 }
            $texQ = 1; $aaQ = 0
        }
    }

    if ($RequestedResX -gt 0 -and $RequestedResY -gt 0) { $resX = $RequestedResX; $resY = $RequestedResY }
    if ($RequestedScale -gt 0) { $scale = $RequestedScale }
    if ($RequestedTextureQuality -ge 0) { $texQ = [math]::Min(4, $RequestedTextureQuality) }
    if ($RequestedAntiAliasingQuality -ge 0) { $aaQ = [math]::Min(4, $RequestedAntiAliasingQuality) }

    $desired3dW = ($resX * $scale) / 100.0
    if ($CanCheckRes -and -not [PubgIrisXeNative]::IsDisplayResolutionSupported($resX, $resY)) {
        if ($resX -ge 1366) {
            if ([PubgIrisXeNative]::IsDisplayResolutionSupported($nativeCapW, $nativeCapH)) {
                $resX = $nativeCapW; $resY = $nativeCapH
                if ($RequestedScale -le 0) {
                    $scale = [int][math]::Round(($desired3dW / [double]$resX) * 100.0)
                }
            } elseif ($is16By10 -and [PubgIrisXeNative]::IsDisplayResolutionSupported(1680, 1050)) {
                $resX = 1680; $resY = 1050
                if ($RequestedScale -le 0) {
                    $scale = [int][math]::Round(($desired3dW / [double]$resX) * 100.0)
                }
            } elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1366, 768)) {
                $resX = 1366; $resY = 768
                if ($RequestedScale -le 0) {
                    $scale = [int][math]::Round(($desired3dW / [double]$resX) * 100.0)
                }
            } elseif ($is16By10 -and [PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800)) {
                $resX = 1280; $resY = 800
                if ($RequestedScale -le 0) { $scale = 100 }
            } elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 720)) {
                $resX = 1280; $resY = 720
                if ($RequestedScale -le 0) { $scale = 100 }
            }
        } else {
            if ($is16By10 -and [PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800)) { $resX = 1280; $resY = 800 }
            elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 720)) { $resX = 1280; $resY = 720 }
            elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1280, 800)) { $resX = 1280; $resY = 800 }
            elseif ([PubgIrisXeNative]::IsDisplayResolutionSupported(1366, 768)) { $resX = 1366; $resY = 768 }
            else { $resX = $DeskW; $resY = $DeskH }
        }
    }

    $clampedScale = [math]::Max(70, [math]::Min(100, $scale))
    $internalX = [int][math]::Round(($resX * $clampedScale) / 100.0)
    $internalY = [int][math]::Round(($resY * $clampedScale) / 100.0)
    $scalingMode = if ($resX -eq $DeskW -and $resY -eq $DeskH -and $clampedScale -eq 100) {
        "Zero-Scale Native (1:1 3D + 1:1 UI)"
    } elseif ($resX -eq $DeskW -and $resY -eq $DeskH) {
        "Single-Pass UE4 Upscale (1:1 Native UI/Scopes, 0 Display Stretch)"
    } elseif ($DeskW -gt 1920 -and $resX -eq $nativeCapW -and $resY -eq $nativeCapH -and $clampedScale -eq 100) {
        "FHD/WUXGA Cap 1:1 (${resX}x${resY} 1:1 3D+UI on ${DeskW}x${DeskH} Panel)"
    } elseif ($DeskW -gt 1920 -and $resX -eq $nativeCapW -and $resY -eq $nativeCapH) {
        "Single-Pass UE4 Upscale @ FHD/WUXGA Cap (${resX}x${resY} 1:1 UI/Scopes on ${DeskW}x${DeskH} Panel)"
    } elseif ($clampedScale -eq 100) {
        "Single-Pass Display Stretch (1:1 3D-to-HUD, 0 UE4 Upscale)"
    } else {
        "Double-Pass Scaling (UE4 Upscale + Display Stretch)"
    }

    return [PSCustomObject]@{
        AppliedPreset              = $effectivePreset
        AppliedResolutionX         = $resX
        AppliedResolutionY         = $resY
        AppliedScreenScale         = $clampedScale
        InternalRenderX            = $internalX
        InternalRenderY            = $internalY
        AppliedTextureQuality      = $texQ
        AppliedAntiAliasingQuality = $aaQ
        ScalingMode                = $scalingMode
        TargetResX                 = $resX
        TargetResY                 = $resY
        TargetScale                = $clampedScale
        Render3DX                  = $internalX
        Render3DY                  = $internalY
        TextureQuality             = $texQ
        AntiAliasingQuality        = $aaQ
    }
}
Set-Alias -Name Resolve-IrisXeQualityPreset -Value Resolve-PubgQualityPreset -Scope Global -ErrorAction SilentlyContinue

function Optimize-PubgIniFiles {
    param(
        [Alias("IniDir", "ConfigDir")][string]$TargetConfigDir = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor", [string]$TargetGraphicsAPI = "DX11",
        [int]$TargetResX = 0, [int]$TargetResY = 0, [Alias("RenderScale", "ScreenScale")][int]$TargetScale = 0, [int]$TargetFpsCap = 60, [bool]$TurnOffHrtf = $false,
        [string]$QualityPreset = "NativeCrisp", [int]$TargetTextureQuality = -1, [int]$TargetAntiAliasingQuality = -1,
        [double]$PeakBandwidthGBs = 83.2,
        [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue))
    )
    $inv          = [System.Globalization.CultureInfo]::InvariantCulture
    $utf8NoBom    = New-Object System.Text.UTF8Encoding($false)
    $fpsCapVal    = if ($TargetFpsCap -gt 0) { $TargetFpsCap } else { 60 }
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

    $resolved = Resolve-PubgQualityPreset -Preset $QualityPreset -DeskW $deskW -DeskH $deskH `
        -RequestedResX $TargetResX -RequestedResY $TargetResY -RequestedScale $TargetScale `
        -RequestedTextureQuality $TargetTextureQuality -RequestedAntiAliasingQuality $TargetAntiAliasingQuality `
        -PeakBandwidthGBs $PeakBandwidthGBs -CanCheckRes $canCheckRes

    $effectiveResX = $resolved.AppliedResolutionX
    $effectiveResY = $resolved.AppliedResolutionY
    $clampedScale  = $resolved.AppliedScreenScale
    $texQualityVal = $resolved.AppliedTextureQuality
    $aaQualityVal  = $resolved.AppliedAntiAliasingQuality
    $scaleStr      = $clampedScale.ToString("F6", $inv)

    $engineIni = Join-Path $TargetConfigDir "Engine.ini"
    $gusIni    = Join-Path $TargetConfigDir "GameUserSettings.ini"
    $engineBak = "$engineIni.irisxe.bak"; $gusBak = "$gusIni.irisxe.bak"
    $attrFile  = Join-Path $TargetConfigDir "irisxe_ini_attrs.json"
    $engineUpdated = $false; $gusUpdated = $false

    $mtx = $null; $acquired = $false
    try {
        try {
            $mtx = New-Object System.Threading.Mutex($false, "Global\PubgIrisXeIni_Mutex")
        } catch {
            $mtx = New-Object System.Threading.Mutex($false, "Local\PubgIrisXeIni_Mutex")
        }
        try { $acquired = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }

        $engExists = [System.IO.File]::Exists($engineIni)
        $gusExists = [System.IO.File]::Exists($gusIni)

        if (-not $IsDryRun) {
            $curEngAttr = if ($engExists) { [System.IO.File]::GetAttributes($engineIni) } else { [System.IO.FileAttributes]::Normal }
            $curGusAttr = if ($gusExists) { [System.IO.File]::GetAttributes($gusIni) } else { [System.IO.FileAttributes]::Normal }

            # Pre-verify that neither Engine.ini nor GameUserSettings.ini is locked by another process before creating backups or mutating files.
            $rawEnginePre = $null
            $rawGusPre    = $null
            try {
                if ($engExists) {
                    if (($curEngAttr -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
                    }
                    $fsE = [System.IO.File]::Open($engineIni, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                    $fsE.Close(); $fsE.Dispose()
                    $rawEnginePre = [System.IO.File]::ReadAllText($engineIni, [System.Text.Encoding]::UTF8)
                }
                if ($gusExists) {
                    if (($curGusAttr -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
                    }
                    $fsG = [System.IO.File]::Open($gusIni, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                    $fsG.Close(); $fsG.Dispose()
                    $rawGusPre = [System.IO.File]::ReadAllText($gusIni, [System.Text.Encoding]::UTF8)
                }
            } catch {
                if ($engExists) { try { [System.IO.File]::SetAttributes($engineIni, $curEngAttr) } catch {} }
                if ($gusExists) { try { [System.IO.File]::SetAttributes($gusIni, $curGusAttr) } catch {} }
                return [PSCustomObject]@{
                    EngineUpdated = $false; GusUpdated = $false; AppliedPreset = $resolved.AppliedPreset; AppliedResolutionX = $effectiveResX; AppliedResolutionY = $effectiveResY
                    AppliedScreenScale = $clampedScale; InternalRenderX = [int][math]::Round(($effectiveResX * $clampedScale) / 100.0); InternalRenderY = [int][math]::Round(($effectiveResY * $clampedScale) / 100.0)
                    AppliedTextureQuality = $texQualityVal; AppliedAntiAliasingQuality = $aaQualityVal; ScalingMode = $resolved.ScalingMode
                    TargetResX = $effectiveResX; TargetResY = $effectiveResY; TargetScale = $clampedScale
                    Render3DX = [int][math]::Round(($effectiveResX * $clampedScale) / 100.0); Render3DY = [int][math]::Round(($effectiveResY * $clampedScale) / 100.0)
                    TextureQuality = $texQualityVal; AntiAliasingQuality = $aaQualityVal
                }
            }

            $savedAttrs = $null
            if ([System.IO.File]::Exists($attrFile)) {
                try { $savedAttrs = [System.IO.File]::ReadAllText($attrFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $savedAttrs = $null }
            }
            if ($null -eq $savedAttrs) {
                $engRo = (($curEngAttr -band [System.IO.FileAttributes]::ReadOnly) -ne 0)
                $gusRo = (($curGusAttr -band [System.IO.FileAttributes]::ReadOnly) -ne 0)
                $attrPayload = [ordered]@{
                    EngineReadOnly   = $engRo
                    EngineAttributes = [int]$curEngAttr
                    GusReadOnly      = $gusRo
                    GusAttributes    = [int]$curGusAttr
                } | ConvertTo-Json -Compress
                [System.IO.File]::WriteAllText($attrFile, $attrPayload, $utf8NoBom)
                $savedAttrs = $attrPayload | ConvertFrom-Json
            }

            if ($engExists) {
                [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
                if (-not [System.IO.File]::Exists($engineBak)) {
                    [System.IO.File]::Copy($engineIni, $engineBak, $true)
                    [System.IO.File]::SetAttributes($engineBak, [System.IO.FileAttributes]::Normal)
                }
                $rawEngine = $rawEnginePre
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
                if ($savedAttrs -and $savedAttrs.EngineReadOnly) {
                    [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]([int]$savedAttrs.EngineAttributes))
                } else {
                    [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
                }
                $engineUpdated = $true
            }

            if ($gusExists) {
                # Clear ReadOnly during gameplay so PUBG can save user keybinds, mouse sensitivity, and reticle changes on exit.
                [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
                if (-not [System.IO.File]::Exists($gusBak)) {
                    [System.IO.File]::Copy($gusIni, $gusBak, $true)
                    [System.IO.File]::SetAttributes($gusBak, [System.IO.FileAttributes]::Normal)
                }
                $rawGus = $rawGusPre

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

                # TslPersistantData duplicates bUseKillCam, bUseLiveStreaming, bIsEnabledHrtfRemoteWeaponSound, and bUseTAA and overrides top-level keys on load.
                $taaToken = if ($aaQualityVal -ge 2) { "True" } else { "False" }
                $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbUseKillCam=)(True|False)', '${1}False')
                $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbUseLiveStreaming=)(True|False)', '${1}False')
                $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbIsEnabledHrtfRemoteWeaponSound=)(True|False)', "`${1}$hrtfToken")
                $rawGus = [regex]::Replace($rawGus, '(?mi)(^TslPersistantData=[^\r\n]*?\bbUseTAA=)(True|False)', "`${1}$taaToken")

                $scalabilityTable = [ordered]@{
                    "sg.ResolutionQuality" = $scaleStr; "sg.ViewDistanceQuality" = "0"; "sg.AntiAliasingQuality" = "$aaQualityVal"; "sg.ShadowQuality" = "0"
                    "sg.PostProcessQuality" = "0"; "sg.TextureQuality" = "$texQualityVal"; "sg.EffectsQuality" = "0"; "sg.FoliageQuality" = "0"; "sg.ShadingQuality" = "0"; "sg.VSyncQuality" = "0"
                }
                foreach ($kv in $scalabilityTable.GetEnumerator()) {
                    $rawGus = Set-IniKeyValueInSection -Content $rawGus -SectionHeader "ScalabilityGroups" -Key $kv.Key -Value $kv.Value
                }

                [System.IO.File]::WriteAllText($gusIni, $rawGus, $utf8NoBom)
                [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
                $gusUpdated = $true
            }
        } else {
            if ($engExists) { $engineUpdated = $true }
            if ($gusExists) { $gusUpdated = $true }
        }
    } finally {
        if ($null -ne $mtx) {
            try { if ($acquired) { $mtx.ReleaseMutex() } } catch {}
            try { $mtx.Dispose() } catch {}
        }
    }

    return [PSCustomObject]@{
        EngineUpdated = $engineUpdated; GusUpdated = $gusUpdated; AppliedPreset = $resolved.AppliedPreset; AppliedResolutionX = $effectiveResX; AppliedResolutionY = $effectiveResY
        AppliedScreenScale = $clampedScale; InternalRenderX = [int][math]::Round(($effectiveResX * $clampedScale) / 100.0); InternalRenderY = [int][math]::Round(($effectiveResY * $clampedScale) / 100.0)
        AppliedTextureQuality = $texQualityVal; AppliedAntiAliasingQuality = $aaQualityVal; ScalingMode = $resolved.ScalingMode
        TargetResX = $effectiveResX; TargetResY = $effectiveResY; TargetScale = $clampedScale
        Render3DX = [int][math]::Round(($effectiveResX * $clampedScale) / 100.0); Render3DY = [int][math]::Round(($effectiveResY * $clampedScale) / 100.0)
        TextureQuality = $texQualityVal; AntiAliasingQuality = $aaQualityVal
    }
}

function Restore-PubgIniFiles {
    param([Alias("IniDir", "ConfigDir")][string]$TargetConfigDir = "$env:LOCALAPPDATA\TslGame\Saved\Config\WindowsNoEditor", [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue)))
    $engineIni = Join-Path $TargetConfigDir "Engine.ini"
    $gusIni    = Join-Path $TargetConfigDir "GameUserSettings.ini"
    $engineBak = "$engineIni.irisxe.bak"
    $gusBak    = "$gusIni.irisxe.bak"
    $attrFile  = Join-Path $TargetConfigDir "irisxe_ini_attrs.json"
    $engineRestored = $false
    $gusRestored    = $false

    $mtx = $null; $acquired = $false
    try {
        try {
            $mtx = New-Object System.Threading.Mutex($false, "Global\PubgIrisXeIni_Mutex")
        } catch {
            $mtx = New-Object System.Threading.Mutex($false, "Local\PubgIrisXeIni_Mutex")
        }
        try { $acquired = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }

        $savedAttrs = $null
        if ([System.IO.File]::Exists($attrFile)) {
            try { $savedAttrs = [System.IO.File]::ReadAllText($attrFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $savedAttrs = $null }
        }

        if ([System.IO.File]::Exists($engineBak)) {
            if (-not $IsDryRun) {
                [System.IO.File]::SetAttributes($engineBak, [System.IO.FileAttributes]::Normal)
                if ([System.IO.File]::Exists($engineIni)) { [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal) }
                [System.IO.File]::Copy($engineBak, $engineIni, $true)
                [System.IO.File]::Delete($engineBak)
                if ($savedAttrs -and $savedAttrs.EngineReadOnly) {
                    [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]([int]$savedAttrs.EngineAttributes))
                } else {
                    [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
                }
            }
            $engineRestored = $true
        } elseif ([System.IO.File]::Exists($engineIni) -and -not $IsDryRun) {
            if ($savedAttrs -and $savedAttrs.EngineReadOnly) {
                [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]([int]$savedAttrs.EngineAttributes))
            } else {
                [System.IO.File]::SetAttributes($engineIni, [System.IO.FileAttributes]::Normal)
            }
        }

        if ([System.IO.File]::Exists($gusBak)) {
            if (-not $IsDryRun) {
                [System.IO.File]::SetAttributes($gusBak, [System.IO.FileAttributes]::Normal)
                if ([System.IO.File]::Exists($gusIni)) { [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal) }
                $liveGus = if ([System.IO.File]::Exists($gusIni)) { [System.IO.File]::ReadAllText($gusIni, [System.Text.Encoding]::UTF8) } else { "" }
                $bakGus  = [System.IO.File]::ReadAllText($gusBak, [System.Text.Encoding]::UTF8)
                [System.IO.File]::Copy($gusBak, $gusIni, $true)
                [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
                if (-not [string]::IsNullOrEmpty($liveGus)) {
                    $changed  = $false
                    $prefKeys = @(
                        "CustomInputSettins", "DefaultReticleBrightnessMap", "RifleCrosshairSettings",
                        "ShotgunCrosshairSettings", "PistolCrosshairSettings", "ThrowableCrosshairSettings",
                        "FpsCameraFov", "CrosshairColorString", "CustomReticleColor", "MouseSensitiveList"
                    )
                    foreach ($pk in $prefKeys) {
                        if ($liveGus -match "(?m)^(?<ln>$pk=[^\r\n]*)") {
                            $liveLine = $Matches['ln'].TrimEnd("`r")
                            if ($bakGus -match "(?m)^(?<bln>$pk=[^\r\n]*)") {
                                $bakLine = $Matches['bln'].TrimEnd("`r")
                                if ($bakLine -cne $liveLine) {
                                    $bakGus  = [regex]::Replace($bakGus, "(?m)^$pk=[^\r\n]*", $liveLine.Replace('$', '$$'))
                                    $changed = $true
                                }
                            } else {
                                $valPart = $liveLine.Substring($pk.Length + 1)
                                $bakGus  = Set-IniKeyValueInSection -Content $bakGus -SectionHeader "/Script/TslGame.TslGameUserSettings" -Key $pk -Value $valPart
                                $changed = $true
                            }
                        }
                    }
                    foreach ($multiKey in @("ActionMappings", "AxisMappings")) {
                        $liveMulti = @([regex]::Matches($liveGus, "(?m)^$multiKey=[^\r\n]*") | ForEach-Object { $_.Value.TrimEnd("`r") })
                        $bakMulti  = @([regex]::Matches($bakGus, "(?m)^$multiKey=[^\r\n]*") | ForEach-Object { $_.Value.TrimEnd("`r") })
                        if (($liveMulti -join "`n") -cne ($bakMulti -join "`n")) {
                            $bakGus = [regex]::Replace($bakGus, "(?m)^$multiKey=[^\r\n]*\r?\n?", "")
                            if ($liveMulti.Count -gt 0) {
                                $multiBlock = ($liveMulti -join "`r`n")
                                if ($bakGus -match "(?m)^\[ScalabilityGroups\]") {
                                    $safeBlock = ($multiBlock + "`r`n`r`n[ScalabilityGroups]").Replace('$', '$$')
                                    $bakGus = [regex]::Replace($bakGus, "(?m)^\[ScalabilityGroups\]", $safeBlock, 1)
                                } else {
                                    $bakGus = $bakGus.TrimEnd() + "`r`n" + $multiBlock + "`r`n"
                                }
                            }
                            $changed = $true
                        }
                    }
                    if ($liveGus -match "(?m)^(?<ltp>TslPersistantData=[^\r\n]*)") {
                        $liveTp = $Matches['ltp'].TrimEnd("`r")
                        if ($bakGus -match "(?m)^(?<btp>TslPersistantData=[^\r\n]*)") {
                            $bakTp = $Matches['btp'].TrimEnd("`r")
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
                [System.IO.File]::Delete($gusBak)
                if ($savedAttrs -and $savedAttrs.GusReadOnly) {
                    [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]([int]$savedAttrs.GusAttributes))
                } else {
                    [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
                }
            }
            $gusRestored = $true
        } elseif ([System.IO.File]::Exists($gusIni) -and -not $IsDryRun) {
            if ($savedAttrs -and $savedAttrs.GusReadOnly) {
                [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]([int]$savedAttrs.GusAttributes))
            } else {
                [System.IO.File]::SetAttributes($gusIni, [System.IO.FileAttributes]::Normal)
            }
        }

        if (-not $IsDryRun -and [System.IO.File]::Exists($attrFile)) {
            try {
                [System.IO.File]::SetAttributes($attrFile, [System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($attrFile)
            } catch {}
        }
    } finally {
        if ($null -ne $mtx) {
            try { if ($acquired) { $mtx.ReleaseMutex() } } catch {}
            try { $mtx.Dispose() } catch {}
        }
    }

    return [PSCustomObject]@{ EngineRestored = $engineRestored; GusRestored = $gusRestored }
}

function Measure-PubgDemosFolder {
    param(
        [Alias("CleanOldDemos")][bool]$RemoveOldDemos = $false,
        [int]$MaxToKeep = 20,
        [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue)),
        [string]$DemosDir = (Join-Path $env:LOCALAPPDATA "TslGame\Saved\Demos")
    )
    if (-not (Test-Path -LiteralPath $DemosDir)) {
        return [PSCustomObject]@{ MatchCount = 0; FileCount = 0; SizeMB = 0.0; Cleaned = $false; RemovedCount = 0 }
    }
    $matchDirs    = @(Get-ChildItem -LiteralPath $DemosDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    $allFiles     = @(Get-ChildItem -LiteralPath $DemosDir -Recurse -File -ErrorAction SilentlyContinue)
    $bytes        = ($allFiles | Measure-Object Length -Sum).Sum
    $sizeMB       = if ($bytes -gt 0) { [math]::Round($bytes / 1MB, 2) } else { 0.0 }
    $cleaned      = $false
    $removedCount = 0
    if ($RemoveOldDemos -and -not $IsDryRun -and $matchDirs.Count -gt 0) {
        $cutoffUtc = [DateTime]::UtcNow.AddDays(-14)
        $unpinnedRecentCount = 0
        foreach ($md in $matchDirs) {
            $riFiles = @(Get-ChildItem -LiteralPath $md.FullName -Filter "*.replayinfo" -File -Force -ErrorAction SilentlyContinue)
            $isPinned = $false
            $riLocked = $false
            foreach ($riFile in $riFiles) {
                try {
                    $fsRi = [System.IO.File]::Open($riFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $srRi = New-Object System.IO.StreamReader($fsRi, [System.Text.Encoding]::UTF8)
                    $riRaw = $srRi.ReadToEnd()
                    $srRi.Close(); $fsRi.Close()
                    if ($riRaw -match '"bShouldKeep"\s*:\s*true') { $isPinned = $true }
                } catch {
                    $riLocked = $true
                }
            }
            if ($isPinned -or $riLocked) { continue }
            if ($md.LastWriteTimeUtc -ge $cutoffUtc -and $riFiles.Count -gt 0) {
                $unpinnedRecentCount++
                if ($unpinnedRecentCount -le $MaxToKeep) { continue }
            }
            $innerFiles = @(Get-ChildItem -LiteralPath $md.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
            $anyLocked = $false
            foreach ($inf in $innerFiles) {
                try {
                    if (($inf.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        [System.IO.File]::SetAttributes($inf.FullName, [System.IO.FileAttributes]::Normal)
                    }
                    $fs = [System.IO.File]::Open($inf.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                    $fs.Close(); $fs.Dispose()
                } catch {
                    $anyLocked = $true
                    break
                }
            }
            if (-not $anyLocked) {
                try {
                    Remove-Item -LiteralPath $md.FullName -Recurse -Force -ErrorAction Stop
                    $cleaned = $true
                    $removedCount++
                } catch {}
            }
        }
    }
    return [PSCustomObject]@{ MatchCount = $matchDirs.Count; FileCount = $allFiles.Count; SizeMB = $sizeMB; Cleaned = $cleaned; RemovedCount = $removedCount }
}

function Clear-StaleDxShaderCacheSafely {
    param([bool]$ForceRebuild = $false, [bool]$IsDryRun = ([bool](Get-Variable -Name DryRun -ValueOnly -ErrorAction SilentlyContinue)))
    $tslProcs = @([System.Diagnostics.Process]::GetProcessesByName("TslGame"))
    foreach ($tp in $tslProcs) { $tp.Dispose() }
    if ($tslProcs.Count -gt 0) {
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
