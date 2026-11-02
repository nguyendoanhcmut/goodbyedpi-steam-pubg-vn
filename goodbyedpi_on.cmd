@echo off
setlocal EnableDelayedExpansion
:: Start/Restart GoodbyeDPI cleanly with 2-byte forward native fragmentation (--native-frag --allow-no-sni --max-payload 1200) + OpenDNS:5353,
:: run pubg_autofix.ps1 (ECS-preserving Google DNS + parallel 7-IP CDN race + batched curl -Z endpoint verification).
net session >nul 2>&1 || (set "GDPI_SELF=%~f0" & set "GDPI_ARG=%~1" & powershell -NoProfile -Command "if ($env:GDPI_ARG) { Start-Process -FilePath $env:GDPI_SELF -ArgumentList $env:GDPI_ARG -Verb RunAs } else { Start-Process -FilePath $env:GDPI_SELF -Verb RunAs }" & exit /b)

title GoodbyeDPI - TRANG THAI HOAT DONG

set "BASEDIR=%~dp0"
if "!BASEDIR:~-1!"=="\" set "BASEDIR=!BASEDIR:~0,-1!"
set "BLACKLIST=!BASEDIR!\steam-blacklist.txt"

echo [1/3] Dang kiem tra/khoi dong dich vu ngam GoodbyeDPI (2-byte native-frag + allow-no-sni + max-payload 1200 + OpenDNS:5353)...
set "SVC_OK=0"
sc query GoodbyeDPI | find "RUNNING" >nul 2>&1 && (
    sc qc GoodbyeDPI | find "--native-frag --allow-no-sni --max-payload 1200" >nul 2>&1 && (
        sc qc GoodbyeDPI | find "DEMAND_START" >nul 2>&1 && (
            set "SVC_OK=1"
            goto :svc_ready
        )
    )
)

sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
for /L %%i in (1,1,10) do (
    sc query GoodbyeDPI | find "STOP_PENDING" >nul 2>&1 || goto :stop_done
    ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
)
:stop_done

sc config GoodbyeDPI binPath= "\"!BASEDIR!\x86_64\goodbyedpi.exe\" -p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200 --blacklist \"!BLACKLIST!\" --dns-addr 208.67.222.222 --dns-port 5353 --dnsv6-addr 2620:119:35::35 --dnsv6-port 5353" start= demand >nul 2>&1 || (
    sc create GoodbyeDPI binPath= "\"!BASEDIR!\x86_64\goodbyedpi.exe\" -p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200 --blacklist \"!BLACKLIST!\" --dns-addr 208.67.222.222 --dns-port 5353 --dnsv6-addr 2620:119:35::35 --dnsv6-port 5353" start= demand >nul 2>&1
)
sc start GoodbyeDPI >nul 2>&1
for /L %%i in (1,1,10) do (
    sc query GoodbyeDPI | find "RUNNING" >nul 2>&1 && (
        set "SVC_OK=1"
        goto :svc_ready
    )
    ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
    sc start GoodbyeDPI >nul 2>&1
)
:svc_ready

echo [2/3] Dang toi uu Google DNS (8.8.8.8/8.8.4.4 ECS + DoH), kiem tra CohCache va dua toc do CDN PUBG song song...
powershell -NoProfile -ExecutionPolicy Bypass -File "!BASEDIR!\pubg_autofix.ps1" %~1
exit /b 0
