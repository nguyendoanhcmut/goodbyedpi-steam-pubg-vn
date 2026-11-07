@echo off
setlocal DisableDelayedExpansion
:: Tu dong xin quyen Administrator va chuyen tiep tham so an toan
net session >nul 2>&1
if %ERRORLEVEL% equ 0 goto :RunMain
echo "%*" | findstr /I "\-DryRun" >nul 2>&1 && goto :RunMain
goto :Elevate

:RunMain
title TOI UU HOA PUBG PC - DELL LATITUDE 3450 (i7-1355U + INTEL IRIS XE)
cd /d "%~dp0"
if "%~1"=="" (
    schtasks /query /tn "PUBGIrisXe-Boost" >nul 2>&1 || (
        schtasks /create /tn "PUBGIrisXe-Boost" /tr "\"%~f0\"" /sc once /st 00:00 /sd 01/01/2000 /rl highest /it /f >nul 2>&1
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel; Set-ScheduledTask -TaskName 'PUBGIrisXe-Boost' -Settings $s -ErrorAction SilentlyContinue | Out-Null" >nul 2>&1
    )
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pubg_iris_xe_boost.ps1" %*
exit /b %ERRORLEVEL%

:Elevate
if "%~1"=="" (
    schtasks /query /tn "PUBGIrisXe-Boost" >nul 2>&1 && schtasks /run /tn "PUBGIrisXe-Boost" >nul 2>&1 && exit /b 0
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -Wait"
)
exit /b %ERRORLEVEL%
