@echo off
:: Stop GoodbyeDPI cleanly without artificial delays, set service to manual (demand),
:: reset IPv4 & IPv6 DNS to DHCP on active physical adapters, and clean hosts pin.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)

taskkill /F /FI "WINDOWTITLE eq GoodbyeDPI - TRANG THAI*" >nul 2>&1
title GoodbyeDPI - TRANG THAI TAT

echo Dang tat dich vu ngam GoodbyeDPI, khoi phuc DNS DHCP va go ghim hosts...
sc config GoodbyeDPI start= demand >nul 2>&1
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
sc query GoodbyeDPI | find "STOP_PENDING" >nul && ping 127.0.0.1 -n 1 -w 150 >nul

powershell -NoProfile -Command "$nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' -and $_.Description -notmatch 'Tailscale|WireGuard|TAP|TUN|ZeroTier|Hyper-V|Virtual|Loopback' }; foreach ($n in $nics) { netsh interface ipv4 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null; netsh interface ipv6 set dnsservers name=\"$($n.Name)\" dhcp | Out-Null }; $h=\"$env:SystemRoot\System32\drivers\etc\hosts\"; $l=@(Get-Content $h | Where-Object { $_ -notmatch 'prod-live-front\.playbattlegrounds\.com' }); [System.IO.File]::WriteAllLines($h, $l, [System.Text.Encoding]::ASCII)" >nul 2>&1
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
