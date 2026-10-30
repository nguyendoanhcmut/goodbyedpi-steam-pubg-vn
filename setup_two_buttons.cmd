@echo off
:: Portable 1-click installer for this PC or any friend's PC:
:: Copies to C:\Tools\goodbyedpi-0.2.3rc3-2 if run from another folder, creates 2 Desktop buttons, and starts GoodbyeDPI.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "DST=C:\Tools\goodbyedpi-0.2.3rc3-2"

if /I not "%SRC%"=="%DST%" (
    echo Dang sao chep bo cong cu vao %DST% ...
    if not exist "%DST%" mkdir "%DST%"
    xcopy "%SRC%\*" "%DST%\" /E /I /Y >nul
)

echo Dang tao 2 nut GoodbyeDPI BAT va GoodbyeDPI TAT tren Desktop...
schtasks /create /tn "GoodbyeDPI-On" /tr "\"%DST%\goodbyedpi_on.cmd\"" /sc once /st 00:00 /sd 01/01/2000 /rl highest /it /f >nul
schtasks /create /tn "GoodbyeDPI-Off" /tr "\"%DST%\goodbyedpi_off.cmd\"" /sc once /st 00:00 /sd 01/01/2000 /rl highest /it /f >nul

powershell -NoProfile -Command "$d=[Environment]::GetFolderPath('Desktop'); $w=New-Object -ComObject WScript.Shell; foreach($p in @(@('GoodbyeDPI BAT','GoodbyeDPI-On','shell32.dll,294'),@('GoodbyeDPI TAT','GoodbyeDPI-Off','shell32.dll,131'))){ $s=$w.CreateShortcut($d+'\'+$p[0]+'.lnk'); $s.TargetPath='C:\Windows\System32\schtasks.exe'; $s.Arguments='/run /tn '+$p[1]; $s.IconLocation='C:\Windows\System32\'+$p[2]; $s.WindowStyle=7; $s.Save() }; Remove-Item ($d+'\GoodbyeDPI Bat-Tat.lnk') -ErrorAction SilentlyContinue"

echo.
echo Da tao xong 2 nut tren Desktop! Dang kich hoat GoodbyeDPI va kiem tra ket noi...
call "%DST%\goodbyedpi_on.cmd"
