$ErrorActionPreference = 'Stop'
$zip = "$env:TEMP\GoodbyeDPI-Steam-PUBG-Fix.zip"
$extractDir = "$env:TEMP\gdpi_install"
Write-Host "Dang tai GoodbyeDPI Steam & PUBG Vietnam Toolkit (v2.3)..." -ForegroundColor Cyan
& "$env:SystemRoot\System32\curl.exe" -sL "https://github.com/nguyendoanhcmut/goodbyedpi-steam-pubg-vn/releases/latest/download/GoodbyeDPI-Steam-PUBG-Fix.zip" -o $zip
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
Expand-Archive -Path $zip -DestinationPath $extractDir -Force
& "$extractDir\CAI_DAT_1_CLICK.cmd"
