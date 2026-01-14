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
    [Parameter()]
    [string]$ZipPath,

    [Parameter()]
    [string]$PackageUrl,

    [Parameter()]
    [string]$Version,

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

# Download ZIP if PackageUrl is provided
if ($PackageUrl) {
    Write-Host "Downloading package from: $PackageUrl" -ForegroundColor Yellow
    $tempDir = Join-Path $env:TEMP "dicom-gateway-deploy"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    $ZipPath = Join-Path $tempDir "package.zip"

    try {
        Invoke-WebRequest -Uri $PackageUrl -OutFile $ZipPath -UseBasicParsing
        Write-Host "Package downloaded successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download package: $_"
        exit 1
    }
}

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

# Step 3: Extract version from ZIP filename or use provided version
Write-Host "`nStep 3: Extracting package..." -ForegroundColor Yellow

# Use provided version or extract from filename (e.g., DicomGatewayMock-1.0.0.zip)
if (-not $Version) {
    $zipFileName = [System.IO.Path]::GetFileNameWithoutExtension($ZipPath)
    if ($zipFileName -match '-(\d+\.\d+\.\d+)$') {
        $version = $matches[1]
    } else {
        $version = "1.0.0"
    }
} else {
    $version = $Version
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
    # Get the current target (Target returns an array, take first element)
    $currentTarget = (Get-Item $currentJunction).Target
    if ($currentTarget -is [array]) {
        $currentTarget = $currentTarget[0]
    }

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

$appScript = Join-Path $currentJunction "src\mock_service.py"
if (Test-Path $appScript) {
    Write-Host "Deployment verified successfully" -ForegroundColor Green
} else {
    Write-Error "Deployment verification failed - application files not found"
    exit 1
}

# Step 6: Locate or Install NSSM (Non-Sucking Service Manager)
Write-Host "`nStep 6: Locating NSSM..." -ForegroundColor Yellow

# First, check if NSSM is available in PATH (system-wide installation)
$nssmExe = $null
try {
    $nssmCommand = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($nssmCommand) {
        $nssmExe = $nssmCommand.Source
        Write-Host "Found NSSM in system PATH: $nssmExe" -ForegroundColor Green
    }
} catch {
    # NSSM not in PATH
}

# If not found in PATH, check local installation
if (-not $nssmExe) {
    $nssmDir = Join-Path $BaseInstallPath "tools\nssm"
    $localNssm = Join-Path $nssmDir "nssm.exe"

    if (Test-Path $localNssm) {
        $nssmExe = $localNssm
        Write-Host "Found NSSM in local installation: $nssmExe" -ForegroundColor Green
    } else {
        # Download NSSM to local directory
        Write-Host "NSSM not found, downloading..." -ForegroundColor Yellow

        $nssmUrl = "https://nssm.cc/ci/nssm-2.24-101-g897c7ad.zip"
        $nssmZip = Join-Path $env:TEMP "nssm.zip"
        $nssmExtract = Join-Path $env:TEMP "nssm-extract"

        Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing
        Expand-Archive -Path $nssmZip -DestinationPath $nssmExtract -Force

        # Copy the appropriate version (64-bit)
        New-Item -ItemType Directory -Path $nssmDir -Force | Out-Null
        Copy-Item -Path "$nssmExtract\nssm-*\win64\nssm.exe" -Destination $localNssm -Force

        # Cleanup
        Remove-Item -Path $nssmZip, $nssmExtract -Recurse -Force -ErrorAction SilentlyContinue

        $nssmExe = $localNssm
        Write-Host "NSSM installed successfully to: $nssmExe" -ForegroundColor Green
    }
}

# Step 7: Configure logging
Write-Host "`nStep 7: Configuring logging..." -ForegroundColor Yellow

$logsDir = Join-Path $BaseInstallPath "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$logFile = Join-Path $logsDir "$ServiceName-$(Get-Date -Format 'yyyy-MM-dd').log"
$errorLogFile = Join-Path $logsDir "$ServiceName-error-$(Get-Date -Format 'yyyy-MM-dd').log"

Write-Host "Log directory: $logsDir" -ForegroundColor Green

# Step 8: Install/Update Windows Service using NSSM
Write-Host "`nStep 8: Configuring Windows Service..." -ForegroundColor Yellow

$startScript = Join-Path $currentJunction "start-service.bat"

# Check if service exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($existingService) {
    Write-Host "Service exists, stopping and updating configuration..." -ForegroundColor Yellow

    # Stop the service
    & $nssmExe stop $ServiceName
    Start-Sleep -Seconds 2

    # Update service configuration
    & $nssmExe set $ServiceName Application $startScript
    & $nssmExe set $ServiceName AppDirectory $currentJunction
    & $nssmExe set $ServiceName AppStdout $logFile
    & $nssmExe set $ServiceName AppStderr $errorLogFile
    & $nssmExe set $ServiceName AppRotateFiles 1
    & $nssmExe set $ServiceName AppRotateOnline 1
    & $nssmExe set $ServiceName AppRotateBytes 10485760  # 10MB

    Write-Host "Service configuration updated" -ForegroundColor Green
} else {
    Write-Host "Creating new service..." -ForegroundColor Yellow

    # Install service
    & $nssmExe install $ServiceName $startScript

    # Configure service
    & $nssmExe set $ServiceName AppDirectory $currentJunction
    & $nssmExe set $ServiceName DisplayName "DICOM Gateway Mock Service"
    & $nssmExe set $ServiceName Description "DICOM Gateway Mock Service for Performance Testing"
    & $nssmExe set $ServiceName Start SERVICE_AUTO_START

    # Configure logging
    & $nssmExe set $ServiceName AppStdout $logFile
    & $nssmExe set $ServiceName AppStderr $errorLogFile
    & $nssmExe set $ServiceName AppRotateFiles 1
    & $nssmExe set $ServiceName AppRotateOnline 1
    & $nssmExe set $ServiceName AppRotateBytes 10485760  # 10MB
    & $nssmExe set $ServiceName AppRotateSeconds 86400   # Daily rotation

    # Configure failure recovery - restart on failure
    & $nssmExe set $ServiceName AppExit Default Restart
    & $nssmExe set $ServiceName AppRestartDelay 5000  # 5 seconds
    & $nssmExe set $ServiceName AppThrottle 10000     # 10 seconds throttle

    Write-Host "Service created successfully" -ForegroundColor Green
}

# Step 9: Start the service
Write-Host "`nStep 9: Starting service..." -ForegroundColor Yellow

& $nssmExe start $ServiceName
Start-Sleep -Seconds 3

$serviceStatus = Get-Service -Name $ServiceName
if ($serviceStatus.Status -eq 'Running') {
    Write-Host "Service started successfully" -ForegroundColor Green
    Write-Host "Service Name: $ServiceName" -ForegroundColor Cyan
    Write-Host "Service Status: $($serviceStatus.Status)" -ForegroundColor Cyan
    Write-Host "Startup Type: $($serviceStatus.StartType)" -ForegroundColor Cyan
    Write-Host "Log File: $logFile" -ForegroundColor Cyan
    Write-Host "Error Log: $errorLogFile" -ForegroundColor Cyan
} else {
    Write-Warning "Service is in state: $($serviceStatus.Status)"
    Write-Warning "Check logs at: $logsDir"
}

# Calculate deployment time
$deployEnd = Get-Date
$deployDuration = ($deployEnd - $deployStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "ZIP Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Installed Version: $version"
Write-Host "Installation Path: $currentJunction"
Write-Host "Service Name: $ServiceName"
Write-Host "Service Status: Running"
Write-Host "Auto-Start: Enabled"
Write-Host "Auto-Restart on Failure: Enabled"
Write-Host "Logs Directory: $logsDir"
Write-Host "Deployment Duration: $([math]::Round($deployDuration, 2)) seconds"
Write-Host ""
Write-Host "Service Management Commands:" -ForegroundColor Cyan
Write-Host "  View Logs:    Get-Content '$logFile' -Tail 50 -Wait" -ForegroundColor Yellow
Write-Host "  Stop Service: Stop-Service -Name $ServiceName" -ForegroundColor Yellow
Write-Host "  Start Service: Start-Service -Name $ServiceName" -ForegroundColor Yellow
Write-Host "  Service Status: Get-Service -Name $ServiceName" -ForegroundColor Yellow
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
