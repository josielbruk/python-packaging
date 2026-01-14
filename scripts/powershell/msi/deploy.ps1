#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy DICOM Gateway MSI package
.DESCRIPTION
    Installs the MSI package and measures deployment time.
    Simulates Arc Run Command deployment scenario.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MsiPath,

    [Parameter()]
    [string]$LogPath = "C:\Temp\msi-install.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$deployStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying MSI Package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MSI Path: $MsiPath"
Write-Host "Log Path: $LogPath"
Write-Host ""

# Validate MSI exists
if (-not (Test-Path $MsiPath)) {
    Write-Error "MSI file not found: $MsiPath"
    exit 1
}

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Step 1: Install MSI
Write-Host "Installing MSI package..." -ForegroundColor Yellow

$msiexecArgs = @(
    "/i", $MsiPath,
    "/quiet",
    "/norestart",
    "/l*v", $LogPath
)

$process = Start-Process -FilePath "msiexec.exe" `
                        -ArgumentList $msiexecArgs `
                        -Wait `
                        -PassThru `
                        -NoNewWindow

if ($process.ExitCode -ne 0) {
    Write-Error "MSI installation failed with exit code: $($process.ExitCode)"
    Write-Host "Check log file: $LogPath" -ForegroundColor Yellow
    exit $process.ExitCode
}

Write-Host "MSI installation completed successfully" -ForegroundColor Green

# Step 2: Verify installation
Write-Host "`nVerifying installation..." -ForegroundColor Yellow

$installPath = "${env:ProgramFiles}\DicomGatewayMock"
if (Test-Path "$installPath\mock_service.py") {
    Write-Host "Installation verified at: $installPath" -ForegroundColor Green
} else {
    Write-Warning "Installation path not found or incomplete"
}

# Calculate deployment time
$deployEnd = Get-Date
$deployDuration = ($deployEnd - $deployStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "MSI Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Installation Path: $installPath"
Write-Host "Deployment Duration: $([math]::Round($deployDuration, 2)) seconds"
Write-Host ""

# Return deployment metrics as JSON for benchmarking
$metrics = @{
    strategy = "MSI"
    deploymentTime = $deployDuration
    installPath = $installPath
    timestamp = $deployEnd.ToString("yyyy-MM-dd HH:mm:ss")
}

return $metrics
