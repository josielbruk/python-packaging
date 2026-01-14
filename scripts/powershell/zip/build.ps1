#Requires -Version 5.1
<#
.SYNOPSIS
    Build ZIP package with portable Python environment
.DESCRIPTION
    Creates a ZIP archive containing the application and a portable virtual environment.
    This is the selected Blue/Green deployment strategy.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version = "1.0.0",

    [Parameter()]
    [string]$OutputDir = ".\dist",

    [Parameter()]
    # Default assumes script is at: repo/scripts/powershell/build.ps1
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent | Split-Path -Parent),

    [Parameter()]
    [string]$ApplicationPath = "src"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$buildStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building ZIP Package (Blue/Green Strategy)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Version: $Version"
Write-Host "Output Directory: $OutputDir"
Write-Host "Repository Root: $RepoRoot"
Write-Host "Application Path: $ApplicationPath"
Write-Host ""

# Step 1: Check for Python
Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Yellow

$python = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Error "Python not found in PATH. Please install Python 3.12+"
    exit 1
}

Write-Host "Python found: $($python.Source)" -ForegroundColor Green

# Step 2: Create temporary build directory
Write-Host "`nStep 2: Preparing build directory..." -ForegroundColor Yellow

$buildDir = Join-Path $env:TEMP "dicom-gateway-build-$Version"
if (Test-Path $buildDir) {
    Remove-Item -Path $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

Write-Host "Build directory: $buildDir" -ForegroundColor Green

# Step 3: Create virtual environment
Write-Host "`nStep 3: Creating portable virtual environment..." -ForegroundColor Yellow

$venvPath = Join-Path $buildDir "venv"
& python -m venv $venvPath --clear
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create virtual environment"
    exit 1
}

Write-Host "Virtual environment created" -ForegroundColor Green

# Step 4: Install dependencies from pyproject.toml
Write-Host "`nStep 4: Installing dependencies..." -ForegroundColor Yellow

$pipExe = Join-Path $venvPath "Scripts\pip.exe"
$pyprojectPath = Join-Path $RepoRoot "pyproject.toml"

if (-not (Test-Path $pyprojectPath)) {
    Write-Error "pyproject.toml not found at: $pyprojectPath"
    exit 1
}

Write-Host "Installing from: $pyprojectPath" -ForegroundColor Gray
& $pipExe install $RepoRoot --quiet --no-warn-script-location
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Some dependencies may have failed to install"
}

Write-Host "Dependencies installed" -ForegroundColor Green

# Step 5: Copy application files
Write-Host "`nStep 5: Copying application files..." -ForegroundColor Yellow

$appDir = Join-Path $buildDir "app"
New-Item -ItemType Directory -Path $appDir -Force | Out-Null

$sourcePath = Join-Path $RepoRoot $ApplicationPath
if (-not (Test-Path $sourcePath)) {
    Write-Error "Application path not found: $sourcePath"
    exit 1
}

Copy-Item -Path "$sourcePath\*" -Destination $appDir -Recurse -Force
Write-Host "  Copied from: $sourcePath" -ForegroundColor Gray

Write-Host "Application files copied" -ForegroundColor Green

# Step 6: Create VERSION file
$versionFile = Join-Path $buildDir "VERSION"
Set-Content -Path $versionFile -Value $Version -NoNewline

# Step 7: Create startup script
Write-Host "`nStep 6: Creating startup script..." -ForegroundColor Yellow

$startScript = @'
@echo off
REM Startup script for DICOM Gateway Service
REM This script activates the venv and runs the application

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

REM Activate virtual environment
call venv\Scripts\activate.bat

REM Run the application
python app\main.py

pause
'@

$startScriptPath = Join-Path $buildDir "start-service.bat"
Set-Content -Path $startScriptPath -Value $startScript

Write-Host "Startup script created" -ForegroundColor Green

# Step 8: Create ZIP archive
Write-Host "`nStep 7: Creating ZIP archive..." -ForegroundColor Yellow

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$zipPath = Join-Path $OutputDir "DicomGatewayMock-$Version.zip"

# Remove existing ZIP if present
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

# Create ZIP using .NET (faster than Compress-Archive for large files)
Add-Type -Assembly System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($buildDir, $zipPath, 'Optimal', $false)

Write-Host "ZIP archive created" -ForegroundColor Green

# Step 9: Cleanup build directory
Remove-Item -Path $buildDir -Recurse -Force

# Calculate build time
$buildEnd = Get-Date
$buildDuration = ($buildEnd - $buildStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "ZIP Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Output: $zipPath"
Write-Host "Size: $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB"
Write-Host "Build Duration: $([math]::Round($buildDuration, 2)) seconds"
Write-Host ""
