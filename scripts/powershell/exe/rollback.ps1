#Requires -Version 5.1
<#
.SYNOPSIS
    Rollback EXE deployment to previous version
.DESCRIPTION
    Restores the backed-up executable and measures rollback time.
    Simulates failure recovery scenario.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = "C:\Apps\DicomGatewayMock",

    [Parameter()]
    [string]$ServiceName = "DicomGatewayMock"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$rollbackStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rolling Back EXE Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Install Path: $InstallPath"
Write-Host ""

# Step 1: Stop service
Write-Host "Step 1: Stopping service..." -ForegroundColor Yellow

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 2
    Write-Host "Service stopped" -ForegroundColor Green
} else {
    Write-Host "Service not running" -ForegroundColor Yellow
}

# Step 2: Verify backup exists
Write-Host "`nStep 2: Locating backup..." -ForegroundColor Yellow

$currentExe = Join-Path $InstallPath "DicomGatewayMock.exe"
$backupExe = Join-Path $InstallPath "DicomGatewayMock.exe.backup"

if (-not (Test-Path $backupExe)) {
    Write-Error "Backup file not found: $backupExe"
    Write-Host "Cannot perform rollback without backup"
    exit 1
}

Write-Host "Backup found: $backupExe" -ForegroundColor Green

# Step 3: Restore backup
Write-Host "`nStep 3: Restoring previous version..." -ForegroundColor Yellow

# Remove current version
if (Test-Path $currentExe) {
    Remove-Item -Path $currentExe -Force
}

# Restore from backup
Copy-Item -Path $backupExe -Destination $currentExe -Force
Write-Host "Previous version restored" -ForegroundColor Green

# Step 4: Verify rollback
Write-Host "`nStep 4: Verifying rollback..." -ForegroundColor Yellow

if (Test-Path $currentExe) {
    Write-Host "Rollback verification successful" -ForegroundColor Green
} else {
    Write-Error "Rollback verification failed - executable not found"
    exit 1
}

# Step 5: Restart service
if ($service) {
    Write-Host "`nStep 5: Restarting service..." -ForegroundColor Yellow
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2

    $serviceStatus = (Get-Service -Name $ServiceName).Status
    if ($serviceStatus -eq 'Running') {
        Write-Host "Service restarted successfully" -ForegroundColor Green
    } else {
        Write-Warning "Service is in state: $serviceStatus"
    }
}

# Calculate rollback time
$rollbackEnd = Get-Date
$rollbackDuration = ($rollbackEnd - $rollbackStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "EXE Rollback Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Rollback Duration: $([math]::Round($rollbackDuration, 2)) seconds"
Write-Host ""

# Return rollback metrics as JSON for benchmarking
$metrics = @{
    strategy = "EXE"
    rollbackTime = $rollbackDuration
    timestamp = $rollbackEnd.ToString("yyyy-MM-dd HH:mm:ss")
}

return $metrics
