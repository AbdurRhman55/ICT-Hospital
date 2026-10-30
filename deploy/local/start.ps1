# ICTHospital — start the local server
#
#   .\deploy\local\start.ps1
#   .\deploy\local\start.ps1 -Port 8080 -HostAddress 0.0.0.0
#
param(
    [int]$Port = 8000,
    [string]$HostAddress = "0.0.0.0"
)

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $appRoot

if (-not (Test-Path ".env")) {
    Write-Error ".env is missing. Copy .env.example to .env and configure the database first."
}

Write-Host "ICTHospital" -ForegroundColor Cyan
Write-Host "  app     : $appRoot"
Write-Host "  address : http://localhost:$Port"
Write-Host ""

php artisan migrate --force

Write-Host "Serving. Press Ctrl+C to stop." -ForegroundColor Green
php artisan serve --host=$HostAddress --port=$Port
