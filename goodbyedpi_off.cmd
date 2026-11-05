@echo off
setlocal EnableDelayedExpansion
set "NO_WAIT_FLAG=%TEMP%\goodbyedpi_off_nowait.flag"
net session >nul 2>&1
if !errorlevel! equ 0 goto :is_admin

schtasks /query /tn "GoodbyeDPI-Off" >nul 2>&1
if !errorlevel! neq 0 goto :uac_elevate

if /I "%~1"=="-NoWait" goto :run_off_nowait
if /I "%~1"=="--nowait" goto :run_off_nowait
if /I "%~1"=="--nopause" goto :run_off_nowait
schtasks /run /tn "GoodbyeDPI-Off" >nul 2>&1
exit /b 0

:run_off_nowait
echo 1 > "!NO_WAIT_FLAG!"
schtasks /run /tn "GoodbyeDPI-Off" >nul 2>&1
for /L %%w in (1,1,30) do (
    ping 127.0.0.1 -n 2 >nul 2>&1
    schtasks /query /tn "GoodbyeDPI-Off" | find "Running" >nul 2>&1 || exit /b 0
)
exit /b 0

:uac_elevate
set "GDPI_SELF=%~f0" & set "GDPI_ARG=%~1" & powershell -NoProfile -Command "if ($env:GDPI_ARG) { Start-Process -FilePath $env:GDPI_SELF -ArgumentList $env:GDPI_ARG -Verb RunAs } else { Start-Process -FilePath $env:GDPI_SELF -Verb RunAs }"
exit /b 0

:is_admin

set "SKIP_PAUSE=0"
if exist "!NO_WAIT_FLAG!" (
    del /F /Q "!NO_WAIT_FLAG!" >nul 2>&1
    set "SKIP_PAUSE=1"
)

title GoodbyeDPI - TRANG THAI TAT

echo Dang tat dich vu ngam GoodbyeDPI, khoi phuc DNS DHCP va go ghim hosts...
sc config GoodbyeDPI start= demand >nul 2>&1
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
set "SVC_STOPPED=0"
for /L %%i in (1,1,10) do (
    sc query GoodbyeDPI | find "STOPPED" >nul 2>&1 && (
        set "SVC_STOPPED=1"
        goto :off_stopped
    )
    ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
)
:off_stopped

powershell -NoProfile -ExecutionPolicy Bypass -Command "$m = New-Object System.Threading.Mutex($false, 'Global\GoodbyeDPI_Toolkit_Mutex'); $has = $false; try { try { $has = $m.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { $has = $true }; try { $cmdProcs = @(([wmisearcher]\"SELECT ProcessId, ParentProcessId, CommandLine FROM Win32_Process WHERE Name='cmd.exe' OR ProcessId=$PID\").Get()); $myParentPid = ($cmdProcs | Where-Object { $_.ProcessId -eq $PID } | Select-Object -First 1).ParentProcessId; foreach ($cp in $cmdProcs) { if ($cp.ProcessId -ne $PID -and $cp.ProcessId -ne $myParentPid -and $cp.CommandLine -match 'goodbyedpi_(on|off)\.cmd' -and $cp.CommandLine -notmatch '(-NoWait|--nowait|--nopause)') { Stop-Process -Id $cp.ProcessId -Force -ErrorAction SilentlyContinue } } } catch {}; Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -ErrorAction SilentlyContinue; $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' -and $_.Description -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback' }; foreach ($n in $nics) { $g = $n.Id; $ns4 = (Get-ItemProperty -Path \"HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g\" -Name NameServer -ErrorAction SilentlyContinue).NameServer; if ($ns4) { & netsh.exe interface ipv4 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null }; & netsh.exe interface ipv6 set interface \"$($n.Name)\" routerdiscovery=enabled | Out-Null; & netsh.exe interface ipv6 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null }; Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue | ForEach-Object { if ((Get-ItemProperty -Path $_.PSPath -Name NameServer -ErrorAction SilentlyContinue).NameServer -eq '8.8.8.8,8.8.4.4') { Set-ItemProperty -Path $_.PSPath -Name NameServer -Value '' -ErrorAction SilentlyContinue } }; Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters' -ErrorAction SilentlyContinue | ForEach-Object { $dohBase = Join-Path $_.PSPath 'DohInterfaceSettings\Doh'; foreach ($ip in @('8.8.8.8','8.8.4.4','1.1.1.1','1.0.0.1','::1')) { if (Test-Path \"$dohBase\$ip\") { Remove-Item -Path \"$dohBase\$ip\" -Recurse -Force -ErrorAction SilentlyContinue } } }; $h = \"$env:SystemRoot\System32\drivers\etc\hosts\"; for ($i=0; $i -lt 5; $i++) { try { $lines = [System.IO.File]::ReadAllLines($h, [System.Text.Encoding]::UTF8); $clean = [string[]]@($lines | Where-Object { $_ -notmatch 'prod-live-front\.playbattlegrounds\.com' }); [System.IO.File]::WriteAllLines($h, $clean, (New-Object System.Text.UTF8Encoding($false))); break } catch { Start-Sleep -Milliseconds 40 } } } finally { if ($has) { try { $m.ReleaseMutex() } catch {} }; $m.Dispose() }" >nul 2>&1
ipconfig /flushdns >nul 2>&1

echo.
if "!SVC_STOPPED!"=="1" (
    echo ========================================================
    echo  TRANG THAI: GoodbyeDPI DA TAT HOAN TOAN ^(Khong tu bat lai khi khoi dong may^).
    echo ========================================================
) else (
    sc query GoodbyeDPI | find "STOPPED" >nul 2>&1 && (
        echo ========================================================
        echo  TRANG THAI: GoodbyeDPI DA TAT HOAN TOAN ^(Khong tu bat lai khi khoi dong may^).
        echo ========================================================
    ) || (
        echo GoodbyeDPI van dang chay. Thu lai sau vai giay.
    )
)
echo.
if "!SKIP_PAUSE!"=="1" exit /b 0
if /I "%~1"=="--nopause" exit /b 0
if /I "%~1"=="--nowait" exit /b 0
if /I "%~1"=="-NoWait" exit /b 0
echo Bam phim bat ky hoac dong cua so nay...
pause >nul
exit /b 0
