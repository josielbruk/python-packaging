#Requires -Version 5.1
<#
.SYNOPSIS
    Rollback MSI deployment to previous version
.DESCRIPTION
    Uninstalls current MSI and reinstalls the previous version.
    Measures rollback time for performance comparison.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PreviousMsiPath,

    [Parameter()]
    [string]$LogPath = "C:\Temp\msi-rollback.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$rollbackStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rolling Back MSI Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Previous MSI: $PreviousMsiPath"
Write-Host ""

# Ensure log directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Step 1: Find current installation
Write-Host "Step 1: Locating current installation..." -ForegroundColor Yellow

$productName = "DICOM Gateway Mock"
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$installedProduct = $null
foreach ($key in $uninstallKeys) {
    $installedProduct = Get-ItemProperty $key -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -eq $productName } |
                       Select-Object -First 1
    if ($installedProduct) { break }
}

if ($installedProduct) {
    $productCode = $installedProduct.PSChildName
    Write-Host "Found installed product: $productName" -ForegroundColor Green
    Write-Host "Product Code: $productCode"

    # Step 2: Uninstall current version
    Write-Host "`nStep 2: Uninstalling current version..." -ForegroundColor Yellow

    $uninstallArgs = @(
        "/x", $productCode,
        "/quiet",
        "/norestart",
        "/l*v", "$LogPath.uninstall"
    )

    $process = Start-Process -FilePath "msiexec.exe" `
                            -ArgumentList $uninstallArgs `
                            -Wait `
                            -PassThru `
                            -NoNewWindow

    if ($process.ExitCode -ne 0) {
        Write-Warning "Uninstallation completed with exit code: $($process.ExitCode)"
    } else {
        Write-Host "Current version uninstalled successfully" -ForegroundColor Green
    }
} else {
    Write-Warning "No current installation found. Skipping uninstall step."
}

# Step 3: Install previous version
Write-Host "`nStep 3: Installing previous version..." -ForegroundColor Yellow

if (-not (Test-Path $PreviousMsiPath)) {
    Write-Error "Previous MSI file not found: $PreviousMsiPath"
    exit 1
}

$installArgs = @(
    "/i", $PreviousMsiPath,
    "/quiet",
    "/norestart",
    "/l*v", "$LogPath.install"
)

$process = Start-Process -FilePath "msiexec.exe" `
                        -ArgumentList $installArgs `
                        -Wait `
                        -PassThru `
                        -NoNewWindow

if ($process.ExitCode -ne 0) {
    Write-Error "Installation of previous version failed with exit code: $($process.ExitCode)"
    exit $process.ExitCode
}

Write-Host "Previous version installed successfully" -ForegroundColor Green

# Step 4: Verify rollback
Write-Host "`nStep 4: Verifying rollback..." -ForegroundColor Yellow

$installPath = "${env:ProgramFiles}\DicomGatewayMock"
if (Test-Path "$installPath\mock_service.py") {
    Write-Host "Rollback verified at: $installPath" -ForegroundColor Green
} else {
    Write-Warning "Rollback verification failed - installation path not found"
}

# Calculate rollback time
$rollbackEnd = Get-Date
$rollbackDuration = ($rollbackEnd - $rollbackStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "MSI Rollback Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Rollback Duration: $([math]::Round($rollbackDuration, 2)) seconds"
Write-Host ""

# Return rollback metrics as JSON for benchmarking
$metrics = @{
    strategy = "MSI"
    rollbackTime = $rollbackDuration
    timestamp = $rollbackEnd.ToString("yyyy-MM-dd HH:mm:ss")
}

return $metrics
