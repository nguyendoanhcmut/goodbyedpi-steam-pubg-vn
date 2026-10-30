@echo off
:: Complete 1-click uninstaller: removes GoodbyeDPI service, WinDivert driver, Scheduled Tasks, Desktop buttons, and hosts entry.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)

echo Dang go cai dat hoan toan GoodbyeDPI...
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
sc delete GoodbyeDPI >nul 2>&1
sc stop WinDivert >nul 2>&1
sc delete WinDivert >nul 2>&1
sc stop WinDivert14 >nul 2>&1
sc delete WinDivert14 >nul 2>&1

schtasks /delete /tn "GoodbyeDPI-On" /f >nul 2>&1
schtasks /delete /tn "GoodbyeDPI-Off" /f >nul 2>&1
schtasks /delete /tn "GoodbyeDPI-Toggle" /f >nul 2>&1

powershell -NoProfile -Command "$d=[Environment]::GetFolderPath('Desktop'); Remove-Item ($d+'\GoodbyeDPI BAT.lnk'),($d+'\GoodbyeDPI TAT.lnk'),($d+'\GoodbyeDPI Bat-Tat.lnk') -Force -ErrorAction SilentlyContinue; $h=\"$env:SystemRoot\System32\drivers\etc\hosts\"; $l=Get-Content $h | Where-Object { $_ -notmatch 'prod-live-front\.playbattlegrounds\.com' }; [System.IO.File]::WriteAllLines($h, $l, [System.Text.Encoding]::ASCII)" >nul 2>&1
ipconfig /flushdns >nul 2>&1

echo Da go cai dat GoodbyeDPI, xoa 2 nut Desktop va khoi phuc file hosts.
pause
