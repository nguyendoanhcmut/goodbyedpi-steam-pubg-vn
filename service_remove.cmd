@echo off
:: Complete 1-click uninstaller: removes GoodbyeDPI service, WinDivert driver, Scheduled Tasks, Desktop buttons,
:: resets IPv4/IPv6 DNS to DHCP, removes interface DoH overrides, and safely restores hosts file.
net session >nul 2>&1 || (powershell -NoProfile -Command "if ('%~1') { Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs } else { Start-Process -FilePath '%~f0' -Verb RunAs }" & exit /b)

echo Dang go cai dat hoan toan GoodbyeDPI...
taskkill /F /T /FI "WINDOWTITLE eq GoodbyeDPI - TRANG THAI*" >nul 2>&1
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
for /L %%i in (1,1,10) do (
    sc query GoodbyeDPI | find "STOP_PENDING" >nul 2>&1 && ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
)
sc delete GoodbyeDPI >nul 2>&1
sc stop WinDivert >nul 2>&1
sc delete WinDivert >nul 2>&1
sc stop WinDivert14 >nul 2>&1
sc delete WinDivert14 >nul 2>&1

schtasks /delete /tn "GoodbyeDPI-On" /f >nul 2>&1
schtasks /delete /tn "GoodbyeDPI-Off" /f >nul 2>&1
schtasks /delete /tn "GoodbyeDPI-Toggle" /f >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$m = New-Object System.Threading.Mutex($false, 'Global\GoodbyeDPI_Toolkit_Mutex'); $has = $false; try { try { $has = $m.WaitOne(10000) } catch [System.Threading.AbandonedMutexException] { $has = $true }; $d = [Environment]::GetFolderPath('Desktop'); Remove-Item ($d+'\GoodbyeDPI BAT.lnk'),($d+'\GoodbyeDPI TAT.lnk'),($d+'\GoodbyeDPI Bat-Tat.lnk') -Force -ErrorAction SilentlyContinue; $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' -and $_.Description -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback' }; foreach ($n in $nics) { & netsh.exe interface ipv4 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null; & netsh.exe interface ipv6 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null; if ($n.Id) { $dohBase = \"HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($n.Id)\DohInterfaceSettings\Doh\"; foreach ($ip in @('8.8.8.8','8.8.4.4','1.1.1.1','1.0.0.1','::1')) { if (Test-Path \"$dohBase\$ip\") { Remove-Item -Path \"$dohBase\$ip\" -Recurse -Force -ErrorAction SilentlyContinue } } } }; $h = \"$env:SystemRoot\System32\drivers\etc\hosts\"; for ($i=0; $i -lt 5; $i++) { try { $lines = [System.IO.File]::ReadAllLines($h, [System.Text.Encoding]::UTF8); $clean = [string[]]@($lines | Where-Object { $_ -notmatch 'prod-live-front\.playbattlegrounds\.com' }); [System.IO.File]::WriteAllLines($h, $clean, (New-Object System.Text.UTF8Encoding($false))); break } catch { Start-Sleep -Milliseconds 40 } } } finally { if ($has) { try { $m.ReleaseMutex() } catch {} }; $m.Dispose() }" >nul 2>&1
ipconfig /flushdns >nul 2>&1

echo Da go cai dat GoodbyeDPI, xoa 2 nut Desktop, khoi phuc DNS DHCP va file hosts.
if /I "%~1"=="--nopause" exit /b 0
pause
