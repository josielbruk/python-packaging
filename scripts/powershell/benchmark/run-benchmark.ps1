#Requires -Version 5.1
<#
.SYNOPSIS
    Automated benchmark runner for packaging strategy evaluation
.DESCRIPTION
    Executes the full benchmark suite for MSI, EXE, and ZIP packaging strategies.
    Collects deployment time, rollback time, and resource metrics.

    This script simulates the Arc-managed deployment scenario and validates
    the architectural decision of using ZIP + Directory Junctions.

.PARAMETER Strategies
    Strategies to benchmark. Options: MSI, EXE, ZIP, All (default: All)

.PARAMETER Iterations
    Number of iterations per strategy (default: 3 for statistical validity)

.PARAMETER OutputPath
    Path for benchmark results report (default: .\results\benchmark-report.json)

.EXAMPLE
    .\run-benchmark.ps1 -Strategies All -Iterations 3

.EXAMPLE
    .\run-benchmark.ps1 -Strategies ZIP -Iterations 5
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("MSI", "EXE", "ZIP", "All")]
    [string]$Strategies = "All",

    [Parameter()]
    [int]$Iterations = 3,

    [Parameter()]
    [string]$OutputPath = ".\results\benchmark-report.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================
# Configuration
# ============================================

$script:BenchmarkStart = Get-Date
$script:Results = @()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Packaging Strategy Benchmark Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Start Time: $($script:BenchmarkStart.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Strategies: $Strategies"
Write-Host "Iterations: $Iterations"
Write-Host ""

# Determine which strategies to test
$strategiesToTest = @()
if ($Strategies -eq "All") {
    $strategiesToTest = @("ZIP", "EXE", "MSI")  # ZIP first as it's the selected strategy
} else {
    $strategiesToTest = @($Strategies)
}

# ============================================
# Helper Functions
# ============================================

function Write-BenchmarkSection {
    param([string]$Message)
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
}

function Measure-BuildTime {
    param(
        [string]$Strategy,
        [string]$BuildScript
    )

    Write-Host "`nBuilding $Strategy package..." -ForegroundColor Cyan

    $buildStart = Get-Date
    & $BuildScript -Version "1.0.0"
    $buildEnd = Get-Date

    $buildTime = ($buildEnd - $buildStart).TotalSeconds
    Write-Host "Build completed in $([math]::Round($buildTime, 2)) seconds" -ForegroundColor Green

    return $buildTime
}

function Measure-DeploymentTime {
    param(
        [string]$Strategy,
        [string]$DeployScript,
        [string]$PackagePath
    )

    Write-Host "`nDeploying $Strategy package..." -ForegroundColor Cyan

    $deployStart = Get-Date
    $metrics = & $DeployScript -PackagePath $PackagePath -ErrorAction Stop
    $deployEnd = Get-Date

    $deployTime = ($deployEnd - $deployStart).TotalSeconds
    Write-Host "Deployment completed in $([math]::Round($deployTime, 2)) seconds" -ForegroundColor Green

    return $deployTime
}

function Measure-RollbackTime {
    param(
        [string]$Strategy,
        [string]$RollbackScript
    )

    Write-Host "`nRolling back $Strategy deployment..." -ForegroundColor Cyan

    $rollbackStart = Get-Date
    $metrics = & $RollbackScript -ErrorAction Stop
    $rollbackEnd = Get-Date

    $rollbackTime = ($rollbackEnd - $rollbackStart).TotalSeconds
    Write-Host "Rollback completed in $([math]::Round($rollbackTime, 2)) seconds" -ForegroundColor Green

    return $rollbackTime
}

function Get-ArtifactSize {
    param([string]$Path)

    if (Test-Path $Path) {
        return (Get-Item $Path).Length
    }
    return 0
}

function Test-Prerequisites {
    Write-BenchmarkSection "Checking Prerequisites"

    $allGood = $true

    # Check Python
    $python = Get-Command "python" -ErrorAction SilentlyContinue
    if ($python) {
        $pythonVersion = & python --version
        Write-Host "[OK] Python: $pythonVersion" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Python not found" -ForegroundColor Red
        $allGood = $false
    }

    # Check for MSI prerequisites (WiX)
    if ($strategiesToTest -contains "MSI") {
        $candle = Get-Command "candle.exe" -ErrorAction SilentlyContinue
        if ($candle) {
            Write-Host "[OK] WiX Toolset found" -ForegroundColor Green
        } else {
            Write-Host "[WARN] WiX Toolset not found - MSI benchmarks will be skipped" -ForegroundColor Yellow
            $script:strategiesToTest = $strategiesToTest | Where-Object { $_ -ne "MSI" }
        }
    }

    # Check for EXE prerequisites (PyInstaller)
    if ($strategiesToTest -contains "EXE") {
        $pyinstaller = & python -m pip list 2>&1 | Select-String "pyinstaller"
        if ($pyinstaller) {
            Write-Host "[OK] PyInstaller found" -ForegroundColor Green
        } else {
            Write-Host "[WARN] PyInstaller not found - will be installed" -ForegroundColor Yellow
        }
    }

    if (-not $allGood) {
        Write-Error "Prerequisites check failed. Please install missing components."
        exit 1
    }
}

# ============================================
# Benchmark Strategy: ZIP
# ============================================

function Invoke-ZipBenchmark {
    Write-BenchmarkSection "Benchmarking ZIP Strategy"

    $zipResults = @{
        strategy = "ZIP"
        buildTimes = @()
        deployTimes = @()
        rollbackTimes = @()
        artifactSizes = @()
    }

    for ($i = 1; $i -le $Iterations; $i++) {
        Write-Host "`n--- Iteration $i of $Iterations ---" -ForegroundColor Magenta

        # Build
        $buildTime = Measure-BuildTime -Strategy "ZIP" -BuildScript ".\zip\build.ps1"
        $zipResults.buildTimes += $buildTime

        # Get artifact info
        $zipFile = Get-ChildItem ".\zip\dist\*.zip" | Select-Object -First 1
        if ($zipFile) {
            $zipResults.artifactSizes += $zipFile.Length
        }

        # Deploy (initial)
        $deployTime = Measure-DeploymentTime -Strategy "ZIP" `
                                             -DeployScript ".\zip\deploy.ps1" `
                                             -PackagePath $zipFile.FullName
        $zipResults.deployTimes += $deployTime

        # Deploy (update) - simulate upgrade
        Start-Sleep -Seconds 2
        & .\zip\build.ps1 -Version "1.0.1" | Out-Null
        $zipFile2 = Get-ChildItem ".\zip\dist\*1.0.1*.zip" | Select-Object -First 1
        if ($zipFile2) {
            $updateTime = Measure-DeploymentTime -Strategy "ZIP" `
                                                  -DeployScript ".\zip\deploy.ps1" `
                                                  -PackagePath $zipFile2.FullName
            $zipResults.deployTimes += $updateTime
        }

        # Rollback
        $rollbackTime = Measure-RollbackTime -Strategy "ZIP" -RollbackScript ".\zip\rollback.ps1"
        $zipResults.rollbackTimes += $rollbackTime

        # Cleanup for next iteration
        if ($i -lt $Iterations) {
            Start-Sleep -Seconds 2
        }
    }

    return $zipResults
}

# ============================================
# Benchmark Strategy: EXE
# ============================================

function Invoke-ExeBenchmark {
    Write-BenchmarkSection "Benchmarking EXE Strategy"

    $exeResults = @{
        strategy = "EXE"
        buildTimes = @()
        deployTimes = @()
        rollbackTimes = @()
        artifactSizes = @()
    }

    for ($i = 1; $i -le $Iterations; $i++) {
        Write-Host "`n--- Iteration $i of $Iterations ---" -ForegroundColor Magenta

        # Build
        $buildTime = Measure-BuildTime -Strategy "EXE" -BuildScript ".\exe\build.ps1"
        $exeResults.buildTimes += $buildTime

        # Get artifact info
        $exeFile = Get-ChildItem ".\exe\dist\*.exe" | Select-Object -First 1
        if ($exeFile) {
            $exeResults.artifactSizes += $exeFile.Length
        }

        # Deploy (initial)
        $deployTime = Measure-DeploymentTime -Strategy "EXE" `
                                             -DeployScript ".\exe\deploy.ps1" `
                                             -PackagePath $exeFile.FullName
        $exeResults.deployTimes += $deployTime

        # Deploy (update)
        Start-Sleep -Seconds 2
        & .\exe\build.ps1 -Version "1.0.1" | Out-Null
        $exeFile2 = Get-ChildItem ".\exe\dist\*1.0.1*.exe" | Select-Object -First 1
        if ($exeFile2) {
            $updateTime = Measure-DeploymentTime -Strategy "EXE" `
                                                  -DeployScript ".\exe\deploy.ps1" `
                                                  -PackagePath $exeFile2.FullName
            $exeResults.deployTimes += $updateTime
        }

        # Rollback
        $rollbackTime = Measure-RollbackTime -Strategy "EXE" -RollbackScript ".\exe\rollback.ps1"
        $exeResults.rollbackTimes += $rollbackTime

        if ($i -lt $Iterations) {
            Start-Sleep -Seconds 2
        }
    }

    return $exeResults
}

# ============================================
# Benchmark Strategy: MSI
# ============================================

function Invoke-MsiBenchmark {
    Write-BenchmarkSection "Benchmarking MSI Strategy"

    $msiResults = @{
        strategy = "MSI"
        buildTimes = @()
        deployTimes = @()
        rollbackTimes = @()
        artifactSizes = @()
    }

    for ($i = 1; $i -le $Iterations; $i++) {
        Write-Host "`n--- Iteration $i of $Iterations ---" -ForegroundColor Magenta

        # Build
        $buildTime = Measure-BuildTime -Strategy "MSI" -BuildScript ".\msi\build.ps1"
        $msiResults.buildTimes += $buildTime

        # Get artifact info
        $msiFile = Get-ChildItem ".\msi\output\*.msi" | Select-Object -First 1
        if ($msiFile) {
            $msiResults.artifactSizes += $msiFile.Length
        }

        # Deploy
        $deployTime = Measure-DeploymentTime -Strategy "MSI" `
                                             -DeployScript ".\msi\deploy.ps1" `
                                             -PackagePath $msiFile.FullName
        $msiResults.deployTimes += $deployTime

        # Build version 2 for rollback test
        Start-Sleep -Seconds 2
        & .\msi\build.ps1 -Version "1.0.1" | Out-Null
        $msiFile2 = Get-ChildItem ".\msi\output\*1.0.1*.msi" | Select-Object -First 1

        # Rollback
        $rollbackTime = Measure-RollbackTime -Strategy "MSI" `
                                             -RollbackScript ".\msi\rollback.ps1" `
                                             -PreviousMsiPath $msiFile.FullName
        $msiResults.rollbackTimes += $rollbackTime

        if ($i -lt $Iterations) {
            Start-Sleep -Seconds 3
        }
    }

    return $msiResults
}

# ============================================
# Statistical Analysis
# ============================================

function Get-Statistics {
    param([array]$Values)

    if ($Values.Count -eq 0) {
        return @{ mean = 0; median = 0; min = 0; max = 0 }
    }

    $sorted = $Values | Sort-Object
    $mean = ($Values | Measure-Object -Average).Average
    $median = if ($sorted.Count % 2 -eq 0) {
        ($sorted[$sorted.Count / 2 - 1] + $sorted[$sorted.Count / 2]) / 2
    } else {
        $sorted[[Math]::Floor($sorted.Count / 2)]
    }

    return @{
        mean = [math]::Round($mean, 2)
        median = [math]::Round($median, 2)
        min = [math]::Round(($sorted | Select-Object -First 1), 2)
        max = [math]::Round(($sorted | Select-Object -Last 1), 2)
    }
}

# ============================================
# Main Execution
# ============================================

# Check prerequisites
Test-Prerequisites

# Run benchmarks
foreach ($strategy in $strategiesToTest) {
    try {
        switch ($strategy) {
            "ZIP" { $script:Results += Invoke-ZipBenchmark }
            "EXE" { $script:Results += Invoke-ExeBenchmark }
            "MSI" { $script:Results += Invoke-MsiBenchmark }
        }
    } catch {
        Write-Host "[ERROR] $strategy benchmark failed: $_" -ForegroundColor Red
    }
}

# ============================================
# Generate Report
# ============================================

Write-BenchmarkSection "Generating Report"

# Ensure results directory exists
$resultsDir = Split-Path $OutputPath -Parent
if ($resultsDir -and -not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

# Calculate statistics
$report = @{
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    iterations = $Iterations
    strategies = @()
}

foreach ($result in $script:Results) {
    $strategyReport = @{
        name = $result.strategy
        build = Get-Statistics -Values $result.buildTimes
        deploy = Get-Statistics -Values $result.deployTimes
        rollback = Get-Statistics -Values $result.rollbackTimes
        artifactSize = @{
            mean = [math]::Round((($result.artifactSizes | Measure-Object -Average).Average / 1MB), 2)
            unit = "MB"
        }
    }

    $report.strategies += $strategyReport
}

# Save JSON report
$report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host "`nBenchmark report saved to: $OutputPath" -ForegroundColor Green

# ============================================
# Display Summary Table
# ============================================

Write-Host "`n"
Write-Host "========================================" -ForegroundColor Green
Write-Host "Benchmark Results Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Deployment Time (Mean):" -ForegroundColor Cyan
foreach ($strategy in $report.strategies) {
    Write-Host "  $($strategy.name): $($strategy.deploy.mean) seconds"
}

Write-Host "`nRollback Time (Mean):" -ForegroundColor Cyan
foreach ($strategy in $report.strategies) {
    Write-Host "  $($strategy.name): $($strategy.rollback.mean) seconds"
}

Write-Host "`nArtifact Size:" -ForegroundColor Cyan
foreach ($strategy in $report.strategies) {
    Write-Host "  $($strategy.name): $($strategy.artifactSize.mean) MB"
}

# Identify winner
$fastestDeploy = ($report.strategies | Sort-Object { $_.deploy.mean } | Select-Object -First 1).name
$fastestRollback = ($report.strategies | Sort-Object { $_.rollback.mean } | Select-Object -First 1).name

Write-Host "`n"
Write-Host "Fastest Deployment: $fastestDeploy" -ForegroundColor Yellow
Write-Host "Fastest Rollback: $fastestRollback" -ForegroundColor Yellow

$benchmarkEnd = Get-Date
$totalDuration = ($benchmarkEnd - $script:BenchmarkStart).TotalMinutes

Write-Host "`nTotal Benchmark Duration: $([math]::Round($totalDuration, 2)) minutes" -ForegroundColor Gray
Write-Host ""
