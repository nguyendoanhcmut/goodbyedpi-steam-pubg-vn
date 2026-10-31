@echo off
:: Complete 1-click uninstaller: removes GoodbyeDPI service, WinDivert driver, Scheduled Tasks, Desktop buttons,
:: resets IPv4/IPv6 DNS to DHCP across all physical/detached adapters, removes interface DoH overrides, and safely restores hosts file.
net session >nul 2>&1 || (set "GDPI_SELF=%~f0" & set "GDPI_ARG=%~1" & powershell -NoProfile -Command "if ($env:GDPI_ARG) { Start-Process -FilePath $env:GDPI_SELF -ArgumentList $env:GDPI_ARG -Verb RunAs } else { Start-Process -FilePath $env:GDPI_SELF -Verb RunAs }" & exit /b)

echo Dang go cai dat hoan toan GoodbyeDPI...
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
for /L %%i in (1,1,10) do (
    sc query GoodbyeDPI | find "STOP_PENDING" >nul 2>&1 || goto :rm_stopped
    ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
)
:rm_stopped
sc delete GoodbyeDPI >nul 2>&1
sc stop WinDivert >nul 2>&1
sc delete WinDivert >nul 2>&1
sc stop WinDivert14 >nul 2>&1
sc delete WinDivert14 >nul 2>&1

schtasks /delete /tn "GoodbyeDPI-On" /f >nul 2>&1
schtasks /delete /tn "GoodbyeDPI-Off" /f >nul 2>&1
schtasks /delete /tn "GoodbyeDPI-Toggle" /f >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$m = New-Object System.Threading.Mutex($false, 'Global\GoodbyeDPI_Toolkit_Mutex'); $has = $false; try { try { $has = $m.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { $has = $true }; try { $cmdProcs = @(([wmisearcher]\"SELECT ProcessId, ParentProcessId, CommandLine FROM Win32_Process WHERE Name='cmd.exe' OR ProcessId=$PID\").Get()); $myParentPid = ($cmdProcs | Where-Object { $_.ProcessId -eq $PID } | Select-Object -First 1).ParentProcessId; foreach ($cp in $cmdProcs) { if ($cp.ProcessId -ne $PID -and $cp.ProcessId -ne $myParentPid -and $cp.CommandLine -match 'goodbyedpi_(on|off)\.cmd') { Stop-Process -Id $cp.ProcessId -Force -ErrorAction SilentlyContinue } } } catch {}; $d = [Environment]::GetFolderPath('Desktop'); Remove-Item ($d+'\GoodbyeDPI BAT.lnk'),($d+'\GoodbyeDPI TAT.lnk'),($d+'\GoodbyeDPI Bat-Tat.lnk') -Force -ErrorAction SilentlyContinue; $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' -and $_.Description -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback' }; foreach ($n in $nics) { $g = $n.Id; $ns4 = (Get-ItemProperty -Path \"HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g\" -Name NameServer -ErrorAction SilentlyContinue).NameServer; if ($ns4) { & netsh.exe interface ipv4 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null }; $ns6 = (Get-ItemProperty -Path \"HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$g\" -Name NameServer -ErrorAction SilentlyContinue).NameServer; if ($ns6) { & netsh.exe interface ipv6 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null } }; Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue | ForEach-Object { if ((Get-ItemProperty -Path $_.PSPath -Name NameServer -ErrorAction SilentlyContinue).NameServer -eq '8.8.8.8,8.8.4.4') { Set-ItemProperty -Path $_.PSPath -Name NameServer -Value '' -ErrorAction SilentlyContinue } }; Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters' -ErrorAction SilentlyContinue | ForEach-Object { $dohBase = Join-Path $_.PSPath 'DohInterfaceSettings\Doh'; foreach ($ip in @('8.8.8.8','8.8.4.4','1.1.1.1','1.0.0.1','::1')) { if (Test-Path \"$dohBase\$ip\") { Remove-Item -Path \"$dohBase\$ip\" -Recurse -Force -ErrorAction SilentlyContinue } } }; $h = \"$env:SystemRoot\System32\drivers\etc\hosts\"; for ($i=0; $i -lt 5; $i++) { try { $lines = [System.IO.File]::ReadAllLines($h, [System.Text.Encoding]::UTF8); $clean = [string[]]@($lines | Where-Object { $_ -notmatch 'prod-live-front\.playbattlegrounds\.com' }); [System.IO.File]::WriteAllLines($h, $clean, (New-Object System.Text.UTF8Encoding($false))); break } catch { Start-Sleep -Milliseconds 40 } } } finally { if ($has) { try { $m.ReleaseMutex() } catch {} }; $m.Dispose() }" >nul 2>&1
ipconfig /flushdns >nul 2>&1

echo Da go cai dat GoodbyeDPI, xoa 2 nut Desktop, khoi phuc DNS DHCP va file hosts.
if /I "%~1"=="--nopause" exit /b 0
pause
