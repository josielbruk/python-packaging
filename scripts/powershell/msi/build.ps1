#Requires -Version 5.1
<#
.SYNOPSIS
    Build MSI package for DICOM Gateway Mock Service
.DESCRIPTION
    Uses WiX Toolset to compile the MSI installer from the WXS definition file.
    Requires WiX Toolset 3.11+ to be installed on the system.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version = "1.0.0",

    [Parameter()]
    [string]$OutputDir = ".\output"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Start timing
$buildStart = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building MSI Package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Version: $Version"
Write-Host "Output Directory: $OutputDir"
Write-Host ""

# Check for WiX Toolset
$candleExe = Get-Command "candle.exe" -ErrorAction SilentlyContinue
$lightExe = Get-Command "light.exe" -ErrorAction SilentlyContinue

if (-not $candleExe -or -not $lightExe) {
    Write-Warning "WiX Toolset not found in PATH. Attempting to locate in common installation directories..."

    $wixPaths = @(
        "C:\Program Files (x86)\WiX Toolset v3.11\bin",
        "C:\Program Files\WiX Toolset v3.11\bin",
        "${env:ProgramFiles(x86)}\WiX Toolset v3.14\bin"
    )

    foreach ($path in $wixPaths) {
        if (Test-Path "$path\candle.exe") {
            $env:PATH = "$path;$env:PATH"
            Write-Host "Found WiX Toolset at: $path" -ForegroundColor Green
            break
        }
    }

    # Re-check
    $candleExe = Get-Command "candle.exe" -ErrorAction SilentlyContinue
    if (-not $candleExe) {
        Write-Error "WiX Toolset not found. Please install from: https://wixtoolset.org/"
        exit 1
    }
}

Write-Host "WiX Toolset found: $($candleExe.Source)" -ForegroundColor Green

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Step 1: Compile WXS to WIXOBJ (candle)
Write-Host "`nStep 1: Compiling WXS definition..." -ForegroundColor Yellow
$wixobjPath = Join-Path $OutputDir "DicomGateway.wixobj"

$candleArgs = @(
    "DicomGateway.wxs",
    "-o", $wixobjPath,
    "-dVersion=$Version"
)

& candle.exe @candleArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Candle.exe failed with exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Successfully compiled to WIXOBJ" -ForegroundColor Green

# Step 2: Link WIXOBJ to MSI (light)
Write-Host "`nStep 2: Linking MSI installer..." -ForegroundColor Yellow
$msiPath = Join-Path $OutputDir "DicomGateway-$Version.msi"

$lightArgs = @(
    $wixobjPath,
    "-o", $msiPath,
    "-ext", "WixUIExtension",
    "-sval"  # Suppress validation for faster builds
)

& light.exe @lightArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Light.exe failed with exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

# Calculate build time
$buildEnd = Get-Date
$buildDuration = ($buildEnd - $buildStart).TotalSeconds

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "MSI Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Output: $msiPath"
Write-Host "Size: $([math]::Round((Get-Item $msiPath).Length / 1MB, 2)) MB"
Write-Host "Build Duration: $([math]::Round($buildDuration, 2)) seconds"
Write-Host ""
