@echo off
:: Stop GoodbyeDPI cleanly, set service to manual (demand) so it stays off across reboots, and clean hosts pin.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)

taskkill /F /FI "WINDOWTITLE eq GoodbyeDPI - TRANG THAI*" >nul 2>&1
title GoodbyeDPI - TRANG THAI TAT

echo Dang tat dich vu ngam GoodbyeDPI va go ghim hosts...
sc config GoodbyeDPI start= demand >nul 2>&1
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
ping 127.0.0.1 -n 2 >nul

powershell -NoProfile -Command "$h=\"$env:SystemRoot\System32\drivers\etc\hosts\"; $l=Get-Content $h | Where-Object { $_ -notmatch 'prod-live-front\.playbattlegrounds\.com' }; [System.IO.File]::WriteAllLines($h, $l, [System.Text.Encoding]::ASCII)" >nul 2>&1
ipconfig /flushdns >nul 2>&1

echo.
sc query GoodbyeDPI | find "STOPPED" >nul && (
    echo ========================================================
    echo  TRANG THAI: GoodbyeDPI DA TAT HOAN TOAN ^(Khong tu bat lai khi khoi dong may^).
    echo ========================================================
) || (
    echo GoodbyeDPI van dang chay. Thu lai sau vai giay.
)
echo.
if /I "%~1"=="--nopause" exit /b 0
echo Bam phim bat ky de dong cua so nay...
pause >nul
exit /b 0
