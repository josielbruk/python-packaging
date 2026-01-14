#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy DICOM Gateway EXE package
.DESCRIPTION
    Deploys the single-file executable and measures deployment time.
    Simulates Arc Run Command deployment scenario with service management.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ExePath,

    [Parameter()]
    [string]$InstallPath = "C:\Apps\DicomGatewayMock",

    [Parameter()]
    [string]$ServiceName = "DicomGatewayMock"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$deployStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying EXE Package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EXE Path: $ExePath"
Write-Host "Install Path: $InstallPath"
Write-Host ""

# Validate EXE exists
if (-not (Test-Path $ExePath)) {
    Write-Error "EXE file not found: $ExePath"
    exit 1
}

# Step 1: Stop existing service if running
Write-Host "Step 1: Checking for existing service..." -ForegroundColor Yellow

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    if ($existingService.Status -eq 'Running') {
        Write-Host "Stopping existing service..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }
    Write-Host "Existing service stopped" -ForegroundColor Green
}

# Step 2: Create installation directory
Write-Host "`nStep 2: Preparing installation directory..." -ForegroundColor Yellow

if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}

# Backup current version if exists
$targetExe = Join-Path $InstallPath "DicomGatewayMock.exe"
if (Test-Path $targetExe) {
    $backupPath = Join-Path $InstallPath "DicomGatewayMock.exe.backup"
    Copy-Item -Path $targetExe -Destination $backupPath -Force
    Write-Host "Backed up current version" -ForegroundColor Green
}

# Step 3: Copy new executable
Write-Host "`nStep 3: Deploying new executable..." -ForegroundColor Yellow

Copy-Item -Path $ExePath -Destination $targetExe -Force
Write-Host "Executable deployed successfully" -ForegroundColor Green

# Step 4: Copy config file
$configSource = Join-Path (Split-Path $PSScriptRoot -Parent) "common\config.yaml"
$configDest = Join-Path $InstallPath "config.yaml"
if (Test-Path $configSource) {
    Copy-Item -Path $configSource -Destination $configDest -Force
    Write-Host "Configuration file deployed" -ForegroundColor Green
}

# Step 5: Verify executable
Write-Host "`nStep 4: Verifying deployment..." -ForegroundColor Yellow

if (Test-Path $targetExe) {
    $fileSize = (Get-Item $targetExe).Length / 1MB
    Write-Host "Deployment verified" -ForegroundColor Green
    Write-Host "Executable size: $([math]::Round($fileSize, 2)) MB"
} else {
    Write-Error "Deployment verification failed - executable not found"
    exit 1
}

# Step 6: Start service (if it was configured)
if ($existingService) {
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

# Calculate deployment time
$deployEnd = Get-Date
$deployDuration = ($deployEnd - $deployStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "EXE Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Installation Path: $InstallPath"
Write-Host "Deployment Duration: $([math]::Round($deployDuration, 2)) seconds"
Write-Host ""

# Return deployment metrics as JSON for benchmarking
$metrics = @{
    strategy = "EXE"
    deploymentTime = $deployDuration
    installPath = $InstallPath
    timestamp = $deployEnd.ToString("yyyy-MM-dd HH:mm:ss")
}

return $metrics
