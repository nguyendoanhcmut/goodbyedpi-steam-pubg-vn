@echo off
:: Restart/Start GoodbyeDPI cleanly with SNI fragmentation + OpenDNS:5353, run pubg_autofix.ps1, and verify.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)

taskkill /F /FI "WINDOWTITLE eq GoodbyeDPI - TRANG THAI*" >nul 2>&1
title GoodbyeDPI - TRANG THAI HOAT DONG

set "BASEDIR=%~dp0"
if "%BASEDIR:~-1%"=="\" set "BASEDIR=%BASEDIR:~0,-1%"

echo [1/3] Dang khoi dong lai dich vu ngam GoodbyeDPI (-8 --frag-by-sni + OpenDNS:5353)...
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
ping 127.0.0.1 -n 2 >nul

sc config GoodbyeDPI binPath= "\"%BASEDIR%\x86_64\goodbyedpi.exe\" -8 --frag-by-sni --blacklist \"%BASEDIR%\steam-blacklist.txt\" --dns-addr 208.67.222.222 --dns-port 5353 --dnsv6-addr 2620:119:35::35 --dnsv6-port 5353" start= auto >nul 2>&1
sc start GoodbyeDPI >nul 2>&1
ping 127.0.0.1 -n 2 >nul

echo [2/3] Dang kich hoat DNS-over-HTTPS (DoH), kiem tra CohCache va dua toc do CDN PUBG...
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASEDIR%\pubg_autofix.ps1"

echo.
sc query GoodbyeDPI | find "RUNNING" >nul && (
    echo =========================================================================
    echo  TRANG THAI: GoodbyeDPI DANG CHAY NGAM ON DINH ^(Windows Service^)
    echo  Luu y: GoodbyeDPI chay ngam trong Windows Services, KHONG tat khi
    echo  ban dong cua so nay. Muon tat han hay dung nut "GoodbyeDPI TAT".
    echo =========================================================================
    tasklist /FI "IMAGENAME eq goodbyedpi.exe"
    echo.
    echo [3/3] Dang verify ket noi thuc te den Steam va PUBG:
    curl.exe -s -o NUL -w "  - Steam Store      (store.steampowered) : HTTP %%{http_code} | IP: %%{remote_ip} | Time: %%{time_total}s\n" --max-time 6 "https://store.steampowered.com/"
    curl.exe -s -o NUL -w "  - Steam Download   (lancache.steam)     : HTTP %%{http_code} | IP: %%{remote_ip} | Time: %%{time_total}s\n" --max-time 6 "http://lancache.steamcontent.com/"
    curl.exe -s -o NUL --range 0-524287 -w "  - PUBG Lobby 512KB (prod-live-front)    : HTTP %%{http_code} | IP: %%{remote_ip} | Time: %%{time_total}s\n" --max-time 6 "https://prod-live-front.playbattlegrounds.com/app/pc-2610-202/main.cb4691e73a746a46.js"
    curl.exe -s -o NUL -w "  - PUBG API Bypass  (bridge-release)     : HTTP %%{http_code} | IP: %%{remote_ip} | Time: %%{time_total}s\n" --max-time 6 "https://bridge-release.pubg.io/"
    echo =========================================================================
) || (
    echo LOI: GoodbyeDPI khong bat duoc. Chay CAI_DAT_1_CLICK.cmd de sua.
)
echo.
if /I "%~1"=="--nopause" exit /b 0
echo Cua so nay duoc giu nguyen de ban kiem tra. Bam phim bat ky khi muon dong...
pause >nul
exit /b 0
