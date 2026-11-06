@echo off
setlocal DisableDelayedExpansion
:: Tu dong xin quyen Administrator va chuyen tiep tham so an toan
net session >nul 2>&1
if %ERRORLEVEL% neq 0 goto :Elevate

title TOI UU HOA PUBG PC - DELL LATITUDE 3450 (i7-1355U + INTEL IRIS XE)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pubg_iris_xe_boost.ps1" %*
exit /b %ERRORLEVEL%

:Elevate
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -Wait"
)
exit /b %ERRORLEVEL%
