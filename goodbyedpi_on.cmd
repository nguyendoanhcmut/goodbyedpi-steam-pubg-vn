@echo off
setlocal EnableDelayedExpansion
:: Start/Restart GoodbyeDPI cleanly with 2-byte forward native fragmentation (--native-frag --allow-no-sni --max-payload 1200) + OpenDNS:5353,
:: run pubg_autofix.ps1 (ECS-preserving Google DNS + parallel 7-IP CDN race + parallel endpoint verification).
net session >nul 2>&1 || (powershell -NoProfile -Command "if ('%~1') { Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs } else { Start-Process -FilePath '%~f0' -Verb RunAs }" & exit /b)

taskkill /F /T /FI "WINDOWTITLE eq GoodbyeDPI - TRANG THAI*" >nul 2>&1
title GoodbyeDPI - TRANG THAI HOAT DONG

set "BASEDIR=%~dp0"
if "!BASEDIR:~-1!"=="\" set "BASEDIR=!BASEDIR:~0,-1!"
set "BLACKLIST=!BASEDIR!\steam-blacklist.txt"

echo [1/3] Dang kiem tra/khoi dong dich vu ngam GoodbyeDPI (2-byte native-frag + allow-no-sni + max-payload 1200 + OpenDNS:5353)...
set "NEED_RESTART=1"
sc query GoodbyeDPI | find "RUNNING" >nul 2>&1 && (
    sc qc GoodbyeDPI | find "--max-payload 1200" >nul 2>&1 && (
        sc qc GoodbyeDPI | find "AUTO_START" >nul 2>&1 && (
            set "NEED_RESTART=0"
        )
    )
)

if "!NEED_RESTART!"=="1" (
    sc stop GoodbyeDPI >nul 2>&1
    taskkill /F /IM goodbyedpi.exe >nul 2>&1
    for /L %%i in (1,1,10) do (
        sc query GoodbyeDPI | find "STOP_PENDING" >nul 2>&1 && ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
    )

    sc config GoodbyeDPI binPath= "\"!BASEDIR!\x86_64\goodbyedpi.exe\" -p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200 --blacklist \"!BLACKLIST!\" --dns-addr 208.67.222.222 --dns-port 5353 --dnsv6-addr 2620:119:35::35 --dnsv6-port 5353" start= auto >nul 2>&1
    sc create GoodbyeDPI binPath= "\"!BASEDIR!\x86_64\goodbyedpi.exe\" -p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200 --blacklist \"!BLACKLIST!\" --dns-addr 208.67.222.222 --dns-port 5353 --dnsv6-addr 2620:119:35::35 --dnsv6-port 5353" start= auto >nul 2>&1
    sc start GoodbyeDPI >nul 2>&1
    for /L %%i in (1,1,10) do (
        sc query GoodbyeDPI | find "RUNNING" >nul 2>&1 || (
            ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
            sc start GoodbyeDPI >nul 2>&1
        )
    )
)

echo [2/3] Dang toi uu Google DNS (8.8.8.8/8.8.4.4 ECS + DoH), kiem tra CohCache va dua toc do CDN PUBG song song...
powershell -NoProfile -ExecutionPolicy Bypass -File "!BASEDIR!\pubg_autofix.ps1"

echo.
sc query GoodbyeDPI | find "RUNNING" >nul 2>&1 && (
    echo =========================================================================
    echo  TRANG THAI: GoodbyeDPI DANG CHAY NGAM ON DINH ^(Windows Service^)
    echo  Luu y: GoodbyeDPI chay ngam trong Windows Services, KHONG tat khi
    echo  ban dong cua so nay. Muon tat han hay dung nut "GoodbyeDPI TAT".
    echo =========================================================================
) || (
    echo LOI: GoodbyeDPI khong bat duoc. Chay CAI_DAT_1_CLICK.cmd de sua.
)
echo.
if /I "%~1"=="--nopause" exit /b 0
echo Cua so nay duoc giu nguyen de ban kiem tra. Bam phim bat ky khi muon dong...
pause >nul
exit /b 0
