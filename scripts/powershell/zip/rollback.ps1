#Requires -Version 5.1
<#
.SYNOPSIS
    Rollback ZIP deployment to previous version
.DESCRIPTION
    Switches the directory junction back to the previous version.
    This is the fastest rollback strategy - typically completes in seconds.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$BaseInstallPath = "C:\Apps\DicomGatewayMock",

    [Parameter()]
    [string]$ServiceName = "DicomGatewayMock"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$rollbackStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rolling Back ZIP Deployment (Blue/Green)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Base Install Path: $BaseInstallPath"
Write-Host ""

# Step 1: Stop service
Write-Host "Step 1: Stopping service..." -ForegroundColor Yellow

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 1
    Write-Host "Service stopped" -ForegroundColor Green
} else {
    Write-Host "Service not running" -ForegroundColor Yellow
}

# Step 2: Verify previous junction exists
Write-Host "`nStep 2: Locating previous version..." -ForegroundColor Yellow

$currentJunction = Join-Path $BaseInstallPath "current"
$previousJunction = Join-Path $BaseInstallPath "previous"

if (-not (Test-Path $previousJunction)) {
    Write-Error "Previous junction not found at: $previousJunction"
    Write-Host "Cannot perform rollback without previous version"
    exit 1
}

$previousTarget = (Get-Item $previousJunction).Target
Write-Host "Previous version found: $previousTarget" -ForegroundColor Green

# Step 3: Switch junction
Write-Host "`nStep 3: Switching junction to previous version..." -ForegroundColor Yellow

# Remove current junction
if (Test-Path $currentJunction) {
    (Get-Item $currentJunction).Delete()
}

# Create new current junction pointing to previous version
New-Item -ItemType Junction -Path $currentJunction -Target $previousTarget -Force | Out-Null
Write-Host "Junction switched to previous version" -ForegroundColor Green

# Step 4: Verify rollback
Write-Host "`nStep 4: Verifying rollback..." -ForegroundColor Yellow

$appScript = Join-Path $currentJunction "app\mock_service.py"
if (Test-Path $appScript) {
    Write-Host "Rollback verification successful" -ForegroundColor Green

    # Read version if available
    $versionFile = Join-Path $currentJunction "VERSION"
    if (Test-Path $versionFile) {
        $rolledBackVersion = Get-Content $versionFile -Raw
        Write-Host "Rolled back to version: $rolledBackVersion" -ForegroundColor Green
    }
} else {
    Write-Error "Rollback verification failed - application files not found"
    exit 1
}

# Step 5: Restart service
if ($service) {
    Write-Host "`nStep 5: Starting service..." -ForegroundColor Yellow
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2

    $serviceStatus = (Get-Service -Name $ServiceName).Status
    if ($serviceStatus -eq 'Running') {
        Write-Host "Service started successfully" -ForegroundColor Green
    } else {
        Write-Warning "Service is in state: $serviceStatus"
    }
}

# Calculate rollback time
$rollbackEnd = Get-Date
$rollbackDuration = ($rollbackEnd - $rollbackStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "ZIP Rollback Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Rollback Duration: $([math]::Round($rollbackDuration, 2)) seconds"
Write-Host ""

# Return rollback metrics as JSON for benchmarking
$metrics = @{
    strategy = "ZIP"
    rollbackTime = $rollbackDuration
    previousTarget = $previousTarget
    timestamp = $rollbackEnd.ToString("yyyy-MM-dd HH:mm:ss")
}

return $metrics
