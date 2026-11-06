$ErrorActionPreference = 'Stop'
$zip = "$env:TEMP\GoodbyeDPI-Steam-PUBG-Fix_$PID.zip"
$extractDir = "$env:TEMP\gdpi_install_$PID"
Get-ChildItem -Path $env:TEMP -Filter "gdpi_install*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
    }
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -Path $env:TEMP -Filter "GoodbyeDPI-Steam-PUBG-Fix*.zip" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "Dang tai GoodbyeDPI Steam & PUBG Vietnam Toolkit (v2.5 + Iris Xe Boost)..." -ForegroundColor Cyan
& "$env:SystemRoot\System32\curl.exe" -fsSL "https://github.com/nguyendoanhcmut/goodbyedpi-steam-pubg-vn/archive/refs/heads/main.zip" -o $zip
if (-not (Test-Path -LiteralPath $zip) -or ((Get-Item -LiteralPath $zip).Length -le 1024)) {
    throw "Khong the tai goi cai dat GoodbyeDPI tu GitHub."
}
if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
Expand-Archive -Path $zip -DestinationPath $extractDir -Force
$installer = Get-ChildItem -Path $extractDir -Filter "CAI_DAT_1_CLICK.cmd" -Recurse | Select-Object -First 1
if ($null -ne $installer) {
    & $installer.FullName
}
