#Requires -Version 5.1
<#
.SYNOPSIS
    Build EXE package using PyInstaller
.DESCRIPTION
    Creates a single-file executable containing the Python application and all dependencies.
    Requires PyInstaller to be installed (pip install pyinstaller).
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version = "1.0.0",

    [Parameter()]
    [string]$OutputDir = ".\dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$buildStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building EXE Package (PyInstaller)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Version: $Version"
Write-Host "Output Directory: $OutputDir"
Write-Host ""

# Step 1: Check for Python and PyInstaller
Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Yellow

$python = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Error "Python not found in PATH. Please install Python 3.12+"
    exit 1
}

Write-Host "Python found: $($python.Source)" -ForegroundColor Green

# Check if PyInstaller is installed
$pyinstallerCheck = & python -m pip list 2>&1 | Select-String "pyinstaller"
if (-not $pyinstallerCheck) {
    Write-Host "PyInstaller not found. Installing..." -ForegroundColor Yellow
    & python -m pip install pyinstaller
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install PyInstaller"
        exit 1
    }
}

Write-Host "PyInstaller is available" -ForegroundColor Green

# Step 2: Install dependencies
Write-Host "`nStep 2: Installing application dependencies..." -ForegroundColor Yellow
$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$requirementsPath = Join-Path $repoRoot "src\requirements.txt"
if (Test-Path $requirementsPath) {
    & python -m pip install -r $requirementsPath --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Some dependencies may have failed to install"
    }
} else {
    Write-Warning "Requirements file not found at: $requirementsPath"
}

Write-Host "Dependencies installed" -ForegroundColor Green

# Step 3: Build with PyInstaller
Write-Host "`nStep 3: Building executable with PyInstaller..." -ForegroundColor Yellow

$pyinstallerArgs = @(
    "-m", "PyInstaller",
    "build.spec",
    "--clean",
    "--noconfirm",
    "--distpath", $OutputDir
)

& python @pyinstallerArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "PyInstaller build failed with exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

# Step 4: Verify output
$exePath = Join-Path $OutputDir "DicomGatewayMock.exe"
if (-not (Test-Path $exePath)) {
    Write-Error "Build completed but executable not found at: $exePath"
    exit 1
}

# Rename to include version
$versionedExePath = Join-Path $OutputDir "DicomGatewayMock-$Version.exe"
Move-Item -Path $exePath -Destination $versionedExePath -Force

# Calculate build time
$buildEnd = Get-Date
$buildDuration = ($buildEnd - $buildStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "EXE Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Output: $versionedExePath"
Write-Host "Size: $([math]::Round((Get-Item $versionedExePath).Length / 1MB, 2)) MB"
Write-Host "Build Duration: $([math]::Round($buildDuration, 2)) seconds"
Write-Host ""
