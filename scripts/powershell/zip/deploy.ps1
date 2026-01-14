#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy ZIP package using Blue/Green strategy with directory junctions
.DESCRIPTION
    Extracts ZIP to versioned directory, creates junction, and measures deployment time.
    This is the production deployment strategy.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ZipPath,

    [Parameter()]
    [string]$BaseInstallPath = "C:\Apps\DicomGatewayMock",

    [Parameter()]
    [string]$ServiceName = "DicomGatewayMock"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$deployStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying ZIP Package (Blue/Green)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ZIP Path: $ZipPath"
Write-Host "Base Install Path: $BaseInstallPath"
Write-Host ""

# Validate ZIP exists
if (-not (Test-Path $ZipPath)) {
    Write-Error "ZIP file not found: $ZipPath"
    exit 1
}

# Step 1: Stop service if running
Write-Host "Step 1: Stopping service..." -ForegroundColor Yellow

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 1
    Write-Host "Service stopped" -ForegroundColor Green
} else {
    Write-Host "Service not running or not installed" -ForegroundColor Yellow
}

# Step 2: Create directory structure
Write-Host "`nStep 2: Preparing directory structure..." -ForegroundColor Yellow

$releasesDir = Join-Path $BaseInstallPath "releases"
$sharedDir = Join-Path $BaseInstallPath "shared"

if (-not (Test-Path $releasesDir)) {
    New-Item -ItemType Directory -Path $releasesDir -Force | Out-Null
}

if (-not (Test-Path $sharedDir)) {
    New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null
}

Write-Host "Directory structure ready" -ForegroundColor Green

# Step 3: Extract version from ZIP filename
Write-Host "`nStep 3: Extracting package..." -ForegroundColor Yellow

# Extract version from filename (e.g., DicomGatewayMock-1.0.0.zip)
$zipFileName = [System.IO.Path]::GetFileNameWithoutExtension($ZipPath)
if ($zipFileName -match '-(\d+\.\d+\.\d+)$') {
    $version = $matches[1]
} else {
    $version = "1.0.0"
}

Write-Host "Detected version: $version" -ForegroundColor Green

# Extract to versioned directory
$versionDir = Join-Path $releasesDir $version
if (Test-Path $versionDir) {
    Write-Host "Version directory exists, removing..." -ForegroundColor Yellow
    Remove-Item -Path $versionDir -Recurse -Force
}

# Extract ZIP
Add-Type -Assembly System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $versionDir)

Write-Host "Package extracted to: $versionDir" -ForegroundColor Green

# Step 4: Update directory junction
Write-Host "`nStep 4: Switching junction to new version..." -ForegroundColor Yellow

$currentJunction = Join-Path $BaseInstallPath "current"
$previousJunction = Join-Path $BaseInstallPath "previous"

# If current junction exists, preserve it as previous
if (Test-Path $currentJunction) {
    # Get the current target
    $currentTarget = (Get-Item $currentJunction).Target

    # Remove previous junction if exists
    if (Test-Path $previousJunction) {
        (Get-Item $previousJunction).Delete()
    }

    # Create new previous junction pointing to old current target
    if ($currentTarget) {
        New-Item -ItemType Junction -Path $previousJunction -Target $currentTarget -Force | Out-Null
        Write-Host "Previous junction created" -ForegroundColor Green
    }

    # Remove current junction
    (Get-Item $currentJunction).Delete()
}

# Create new current junction pointing to new version
New-Item -ItemType Junction -Path $currentJunction -Target $versionDir -Force | Out-Null
Write-Host "Current junction updated to: $version" -ForegroundColor Green

# Step 5: Verify deployment
Write-Host "`nStep 5: Verifying deployment..." -ForegroundColor Yellow

$appScript = Join-Path $currentJunction "app\mock_service.py"
if (Test-Path $appScript) {
    Write-Host "Deployment verified successfully" -ForegroundColor Green
} else {
    Write-Error "Deployment verification failed - application files not found"
    exit 1
}

# Step 6: Restart service
if ($service) {
    Write-Host "`nStep 6: Starting service..." -ForegroundColor Yellow
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
Write-Host "ZIP Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Installed Version: $version"
Write-Host "Installation Path: $currentJunction"
Write-Host "Deployment Duration: $([math]::Round($deployDuration, 2)) seconds"
Write-Host ""

# Return deployment metrics as JSON for benchmarking
$metrics = @{
    strategy = "ZIP"
    deploymentTime = $deployDuration
    version = $version
    installPath = $currentJunction
    timestamp = $deployEnd.ToString("yyyy-MM-dd HH:mm:ss")
}

return $metrics
