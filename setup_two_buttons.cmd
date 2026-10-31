@echo off
:: Portable 1-click installer for this PC or any friend's PC:
:: Stops running GoodbyeDPI before copying to C:\Tools\goodbyedpi-0.2.3rc3-2, creates 2 Desktop buttons, and starts GoodbyeDPI.
net session >nul 2>&1 || (set "GDPI_SELF=%~f0" & set "GDPI_ARG=%~1" & powershell -NoProfile -Command "if ($env:GDPI_ARG) { Start-Process -FilePath $env:GDPI_SELF -ArgumentList $env:GDPI_ARG -Verb RunAs } else { Start-Process -FilePath $env:GDPI_SELF -Verb RunAs }" & exit /b)

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "DST=C:\Tools\goodbyedpi-0.2.3rc3-2"

if /I "%SRC%"=="%DST%" goto :skip_copy
echo Dang sao chep bo cong cu vao %DST% ...
sc stop GoodbyeDPI >nul 2>&1
taskkill /F /IM goodbyedpi.exe >nul 2>&1
for /L %%i in (1,1,10) do (
    sc query GoodbyeDPI | find "STOP_PENDING" >nul 2>&1 || goto :copy_ready
    ping 192.0.2.1 -n 1 -w 50 >nul 2>&1
)
:copy_ready
if not exist "%DST%" mkdir "%DST%"
xcopy "%SRC%\*" "%DST%\" /E /I /C /R /Y >nul
:skip_copy

echo Dang tao 2 nut GoodbyeDPI BAT va GoodbyeDPI TAT tren Desktop...
schtasks /create /tn "GoodbyeDPI-On" /tr "\"%DST%\goodbyedpi_on.cmd\"" /sc once /st 00:00 /sd 01/01/2000 /rl highest /it /f >nul
schtasks /create /tn "GoodbyeDPI-Off" /tr "\"%DST%\goodbyedpi_off.cmd\"" /sc once /st 00:00 /sd 01/01/2000 /rl highest /it /f >nul
schtasks /delete /tn "GoodbyeDPI-Toggle" /f >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel; Set-ScheduledTask -TaskName 'GoodbyeDPI-On' -Settings $s | Out-Null; Set-ScheduledTask -TaskName 'GoodbyeDPI-Off' -Settings $s | Out-Null; $d=[Environment]::GetFolderPath('Desktop'); $w=New-Object -ComObject WScript.Shell; foreach($p in @(@('GoodbyeDPI BAT','GoodbyeDPI-On','shell32.dll,294'),@('GoodbyeDPI TAT','GoodbyeDPI-Off','shell32.dll,131'))){ $sc=$w.CreateShortcut($d+'\'+$p[0]+'.lnk'); $sc.TargetPath='C:\Windows\System32\schtasks.exe'; $sc.Arguments='/run /tn '+$p[1]; $sc.IconLocation='C:\Windows\System32\'+$p[2]; $sc.WindowStyle=7; $sc.Save() }; Remove-Item ($d+'\GoodbyeDPI Bat-Tat.lnk') -ErrorAction SilentlyContinue"

echo.
echo Da tao xong 2 nut tren Desktop! Dang kich hoat GoodbyeDPI va kiem tra ket noi...
call "%DST%\goodbyedpi_on.cmd" %~1
