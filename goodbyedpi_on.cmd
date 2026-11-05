@echo off
setlocal EnableDelayedExpansion
set "NO_WAIT_FLAG=%TEMP%\goodbyedpi_on_nowait.flag"
set "LAST_LOG=%TEMP%\goodbyedpi_on_last.log"
net session >nul 2>&1
if !errorlevel! equ 0 goto :is_admin

schtasks /query /tn "GoodbyeDPI-On" >nul 2>&1
if !errorlevel! neq 0 goto :uac_elevate

if /I "%~1"=="-NoWait" goto :run_task_nowait
if /I "%~1"=="--nowait" goto :run_task_nowait
if /I "%~1"=="--nopause" goto :run_task_nowait
schtasks /run /tn "GoodbyeDPI-On" >nul 2>&1
exit /b 0

:run_task_nowait
del /F /Q "!LAST_LOG!" >nul 2>&1
echo 1 > "!NO_WAIT_FLAG!"
schtasks /run /tn "GoodbyeDPI-On" >nul 2>&1
for /L %%w in (1,1,40) do (
    ping 127.0.0.1 -n 2 >nul 2>&1
    schtasks /query /tn "GoodbyeDPI-On" | find "Running" >nul 2>&1 || goto :task_done
)
:task_done
if exist "!LAST_LOG!" type "!LAST_LOG!"
exit /b 0

:uac_elevate
set "GDPI_SELF=%~f0" & set "GDPI_ARG=%~1" & powershell -NoProfile -Command "if ($env:GDPI_ARG) { Start-Process -FilePath $env:GDPI_SELF -ArgumentList $env:GDPI_ARG -Verb RunAs } else { Start-Process -FilePath $env:GDPI_SELF -Verb RunAs }"
exit /b 0

:is_admin

set "CAPTURE_LOG=0"
if exist "!NO_WAIT_FLAG!" (
    del /F /Q "!NO_WAIT_FLAG!" >nul 2>&1
    set "CAPTURE_LOG=1"
)

title GoodbyeDPI - TRANG THAI HOAT DONG

set "BASEDIR=%~dp0"
if "!BASEDIR:~-1!"=="\" set "BASEDIR=!BASEDIR:~0,-1!"
set "BLACKLIST=!BASEDIR!\steam-blacklist.txt"

echo [1/3] Dang kiem tra/khoi dong dich vu ngam GoodbyeDPI (2-byte native-frag + allow-no-sni + max-payload 1200)...
set "SVC_OK=0"
sc query GoodbyeDPI | find "RUNNING" >nul 2>&1 && (
    sc qc GoodbyeDPI | find "--native-frag --allow-no-sni --max-payload 1200" >nul 2>&1 && (
        sc qc GoodbyeDPI | find "DEMAND_START" >nul 2>&1 && (
            sc qc GoodbyeDPI | find "--dns-addr" >nul 2>&1 || (
                set "SVC_OK=1"
                goto :svc_ready
            )
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

sc config GoodbyeDPI binPath= "\"!BASEDIR!\x86_64\goodbyedpi.exe\" -p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200 --blacklist \"!BLACKLIST!\"" start= demand >nul 2>&1 || (
    sc create GoodbyeDPI binPath= "\"!BASEDIR!\x86_64\goodbyedpi.exe\" -p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200 --blacklist \"!BLACKLIST!\"" start= demand >nul 2>&1
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
if "!CAPTURE_LOG!"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!BASEDIR!\pubg_autofix.ps1" -NoWait > "!LAST_LOG!" 2>&1
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!BASEDIR!\pubg_autofix.ps1" %*
)
exit /b 0
