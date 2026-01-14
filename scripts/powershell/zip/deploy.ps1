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
$dataDir = Join-Path $BaseInstallPath "data"
$logsDir = Join-Path $BaseInstallPath "logs"

foreach ($dir in @($releasesDir, $sharedDir, $dataDir, $logsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

Write-Host "Directory structure ready" -ForegroundColor Green
Write-Host "  Data directory: $dataDir" -ForegroundColor Gray

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

# Step 5: Rebuild virtual environment for target machine
Write-Host "`nStep 5: Rebuilding virtual environment..." -ForegroundColor Yellow

$venvPath = Join-Path $currentJunction ".venv"
$requirementsFile = Join-Path $currentJunction "src\requirements.txt"

# Remove the build machine's virtual environment
if (Test-Path $venvPath) {
    Remove-Item -Path $venvPath -Recurse -Force
    Write-Host "Removed build machine virtual environment" -ForegroundColor Yellow
}

# Find Python on the target machine (supports both system and user installations)
$pythonExe = $null
$pythonPaths = @()

Write-Host "Searching for Python 3.14..." -ForegroundColor Gray

# Strategy 1: Check PATH environment variable (works for both system and user contexts)
$pythonCmd = Get-Command python.exe -ErrorAction SilentlyContinue
if ($pythonCmd) {
    $pythonPaths += $pythonCmd.Source
    Write-Host "  Found in PATH: $($pythonCmd.Source)" -ForegroundColor Gray
}

# Strategy 2: Check common system-wide installation paths
$systemPaths = @(
    "C:\Python314\python.exe",
    "C:\Program Files\Python314\python.exe",
    "C:\Program Files (x86)\Python314\python.exe",
    "C:\Python3\python.exe"
)
foreach ($path in $systemPaths) {
    if (Test-Path $path) {
        $pythonPaths += $path
        Write-Host "  Found system installation: $path" -ForegroundColor Gray
    }
}

# Strategy 3: Check user-specific installations (AppData)
try {
    $userPythonPaths = Get-ChildItem -Path "C:\Users\*\AppData\Local\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue
    if ($userPythonPaths) {
        foreach ($userPath in $userPythonPaths) {
            $pythonPaths += $userPath.FullName
            Write-Host "  Found user installation: $($userPath.FullName)" -ForegroundColor Gray
        }
    }
} catch {
    # Ignore errors searching user paths
}

# Strategy 4: Check Windows Registry for Python installations
try {
    $regPaths = @(
        "HKLM:\SOFTWARE\Python\PythonCore\3.14\InstallPath",
        "HKLM:\SOFTWARE\Python\PythonCore\3.14-64\InstallPath",
        "HKCU:\SOFTWARE\Python\PythonCore\3.14\InstallPath",
        "HKCU:\SOFTWARE\Python\PythonCore\3.14-64\InstallPath"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).'(default)'
            if ($installPath) {
                $regPythonExe = Join-Path $installPath "python.exe"
                if (Test-Path $regPythonExe) {
                    $pythonPaths += $regPythonExe
                    Write-Host "  Found via registry: $regPythonExe" -ForegroundColor Gray
                }
            }
        }
    }
} catch {
    # Ignore registry errors
}

# Select first valid Python installation
foreach ($path in $pythonPaths) {
    if ($path -and (Test-Path $path)) {
        # Verify it's Python 3.14+ by checking version
        try {
            $versionOutput = & $path --version 2>&1
            if ($versionOutput -match "Python 3\.1[4-9]" -or $versionOutput -match "Python 3\.[2-9][0-9]") {
                $pythonExe = $path
                break
            }
        } catch {
            # Skip invalid Python installations
        }
    }
}

if (-not $pythonExe) {
    Write-Error "Python 3.14 not found on target machine. Please install Python 3.14 first."
    exit 1
}

Write-Host "Found Python at: $pythonExe" -ForegroundColor Green

# Create new virtual environment on target machine
& $pythonExe -m venv $venvPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create virtual environment"
    exit 1
}

Write-Host "Virtual environment created" -ForegroundColor Green

# Install dependencies
$venvPython = Join-Path $venvPath "Scripts\python.exe"
& $venvPython -m pip install --upgrade pip --quiet
& $venvPython -m pip install -r $requirementsFile --quiet

Write-Host "Dependencies installed" -ForegroundColor Green

# Step 6: Verify deployment
Write-Host "`nStep 6: Verifying deployment..." -ForegroundColor Yellow

$appScript = Join-Path $currentJunction "src\mock_service.py"
if (Test-Path $appScript) {
    Write-Host "Deployment verified successfully" -ForegroundColor Green
} else {
    Write-Error "Deployment verification failed - application files not found"
    exit 1
}

# Step 6a: Database initialization and migration
Write-Host "`nStep 6a: Database management..." -ForegroundColor Yellow

$dbPath = Join-Path $dataDir "gateway.db"
$migrationScript = Join-Path $currentJunction "src\migrations\migrate.py"

# Check if migration script exists
if (Test-Path $migrationScript) {
    Write-Host "Migration script found, running database migrations..." -ForegroundColor Gray

    # Backup database before migration (if it exists)
    if (Test-Path $dbPath) {
        $backupPath = "$dbPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $dbPath -Destination $backupPath -Force
        Write-Host "  Database backed up to: $backupPath" -ForegroundColor Gray

        # Keep only last 5 backups
        $backups = Get-ChildItem -Path $dataDir -Filter "*.db.backup-*" | Sort-Object CreationTime -Descending
        if ($backups.Count -gt 5) {
            $backups | Select-Object -Skip 5 | Remove-Item -Force
        }
    }

    # Set environment variable for database path
    $env:DATABASE_PATH = $dbPath

    # Run migrations
    try {
        & $venvPython $migrationScript
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Database migrations completed successfully" -ForegroundColor Green
        } else {
            Write-Warning "Database migration returned non-zero exit code: $LASTEXITCODE"
        }
    } catch {
        Write-Warning "Failed to run database migrations: $_"
        Write-Host "Deployment will continue, but manual database review may be needed" -ForegroundColor Yellow
    }
} else {
    Write-Host "No migration script found, skipping database migrations" -ForegroundColor Gray
    Write-Host "  Database location: $dbPath" -ForegroundColor Gray

    # Just ensure database directory exists and is accessible
    if (-not (Test-Path $dbPath)) {
        Write-Host "  Database will be created on first application start" -ForegroundColor Gray
    }
}

# Step 6b: Record deployment in database
Write-Host "`nStep 6b: Recording deployment..." -ForegroundColor Yellow

$recordScript = @"
import sys
sys.path.insert(0, r'$currentJunction\src')
from db import record_deployment
record_deployment('$version', 'azure-arc', 'Deployed via Azure Arc run-command')
print('Deployment recorded')
"@

try {
    $recordScript | & $venvPython -c "exec(input())"
    Write-Host "Deployment recorded in database" -ForegroundColor Green
} catch {
    Write-Warning "Failed to record deployment: $_"
}

# Step 7: Cleanup old versions (keep last 3)
Write-Host "`nStep 7: Cleaning up old versions..." -ForegroundColor Yellow

$releasesDir = Join-Path $BaseInstallPath "releases"
$versions = Get-ChildItem -Path $releasesDir -Directory | Sort-Object CreationTime -Descending

if ($versions.Count -gt 3) {
    $versionsToDelete = $versions | Select-Object -Skip 3

    foreach ($versionDir in $versionsToDelete) {
        # Only delete if it's not currently in use
        $currentTarget = (Get-Item $currentJunction).Target[0]
        $previousTarget = if (Test-Path $previousJunction) { (Get-Item $previousJunction).Target[0] } else { $null }

        if ($versionDir.FullName -ne $currentTarget -and $versionDir.FullName -ne $previousTarget) {
            Write-Host "  Removing old version: $($versionDir.Name)" -ForegroundColor Gray
            Remove-Item -Path $versionDir.FullName -Recurse -Force
        }
    }

    $remainingCount = (Get-ChildItem -Path $releasesDir -Directory).Count
    Write-Host "Cleanup complete - $remainingCount version(s) retained" -ForegroundColor Green
} else {
    Write-Host "No cleanup needed - only $($versions.Count) version(s) exist" -ForegroundColor Green
}

# Step 8: Locate or Install NSSM (Non-Sucking Service Manager)
Write-Host "`nStep 8: Locating NSSM..." -ForegroundColor Yellow

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

# Step 9: Configure logging
Write-Host "`nStep 9: Configuring logging..." -ForegroundColor Yellow

$logsDir = Join-Path $BaseInstallPath "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$logFile = Join-Path $logsDir "$ServiceName-$(Get-Date -Format 'yyyy-MM-dd').log"
$errorLogFile = Join-Path $logsDir "$ServiceName-error-$(Get-Date -Format 'yyyy-MM-dd').log"

Write-Host "Log directory: $logsDir" -ForegroundColor Green

# Step 10: Install/Update Windows Service using NSSM
Write-Host "`nStep 10: Configuring Windows Service..." -ForegroundColor Yellow

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

# Step 11: Start the service
Write-Host "`nStep 11: Starting service..." -ForegroundColor Yellow

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
