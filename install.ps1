$ErrorActionPreference = 'Stop'
$zip = "$env:TEMP\GoodbyeDPI-Steam-PUBG-Fix.zip"
$extractDir = "$env:TEMP\gdpi_install"
Write-Host "Dang tai GoodbyeDPI Steam & PUBG Vietnam Toolkit (v2.5 + Iris Xe Boost)..." -ForegroundColor Cyan
& "$env:SystemRoot\System32\curl.exe" -sL "https://github.com/nguyendoanhcmut/goodbyedpi-steam-pubg-vn/archive/refs/heads/main.zip" -o $zip
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
Expand-Archive -Path $zip -DestinationPath $extractDir -Force
$installer = Get-ChildItem -Path $extractDir -Filter "CAI_DAT_1_CLICK.cmd" -Recurse | Select-Object -First 1
& $installer.FullName
