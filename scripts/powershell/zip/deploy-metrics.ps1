# Enhanced deployment metrics tracking snippet
# This shows the pattern for Step 8 replacement

# Capture VM information
$hostname = $env:COMPUTERNAME
$osVersion = (Get-CimInstance Win32_OperatingSystem).Caption
$pythonVersionFull = & $pythonExe --version 2>&1

# Get previous version from current junction
$previousVersion = $null
if (Test-Path $previousJunction) {
    $prevTarget = (Get-Item $previousJunction).Target[0]
    $previousVersion = Split-Path $prevTarget -Leaf
}

# Calculate phase durations
$extractDuration = $phaseTimings['extract']
$venvDuration = $phaseTimings['venv']
$migrationDuration = $phaseTimings['migration']
$cutoverDuration = $phaseTimings['cutover']

# Step 8: Record comprehensive deployment metrics
Write-Host "`nStep 8: Recording deployment metrics..." -ForegroundColor Yellow

$dbPath = Join-Path $BaseInstallPath "data\gateway.db"
$venvPython = Join-Path $currentJunction ".venv\Scripts\python.exe"

# Start deployment tracking
$trackingScript = @"
import sys
import os
sys.path.insert(0, r'$currentJunction\src')
os.environ['DATABASE_PATH'] = r'$dbPath'

from db import start_deployment_tracking

deployment_id = start_deployment_tracking(
    version='$version',
    previous_version='$previousVersion',
    hostname='$hostname',
    os_version='$osVersion',
    python_version='$pythonVersionFull',
    method='azure-arc'
)
print(f'deployment_id={deployment_id}')
"@

try {
    $trackingOutput = $trackingScript | & $venvPython -c "exec(input())"
    if ($trackingOutput -match 'deployment_id=(\d+)') {
        $deploymentId = $matches[1]
        Write-Host "Deployment tracking started (ID: $deploymentId)" -ForegroundColor Green

        # Update with phase timings
        $phaseUpdateScript = @"
import sys
import os
sys.path.insert(0, r'$currentJunction\src')
os.environ['DATABASE_PATH'] = r'$dbPath'

from db import update_deployment_phase

update_deployment_phase(
    $deploymentId,
    extract_duration=$extractDuration,
    venv_rebuild_duration=$venvDuration,
    migration_duration=$migrationDuration,
    cutover_duration=$cutoverDuration
)
print('Phase timings recorded')
"@
        $phaseUpdateScript | & $venvPython -c "exec(input())" | Out-Null

        # Perform health check to verify version
        Write-Host "Verifying health endpoint..." -ForegroundColor Gray
        $healthCheckStart = Get-Date
        $healthCheckSuccess = $false
        $timeToHealthy = $null

        # Wait up to 30 seconds for service to respond with correct version
        for ($i = 0; $i -lt 30; $i++) {
            try {
                $healthResponse = Invoke-RestMethod -Uri "http://localhost:8080/health" -Method Get -TimeoutSec 2
                if ($healthResponse.version -eq $version) {
                    $healthCheckEnd = Get-Date
                    $healthCheckDuration = ($healthCheckEnd - $healthCheckStart).TotalSeconds
                    $timeToHealthy = ($healthCheckEnd - $cutoverStart).TotalSeconds
                    $healthCheckSuccess = $true
                    Write-Host "  Health check passed - service responding with version $version" -ForegroundColor Green
                    Write-Host "  Time to healthy: $([math]::Round($timeToHealthy, 2)) seconds" -ForegroundColor Cyan
                    break
                } else {
                    Write-Host "  Waiting for correct version (got: $($healthResponse.version))..." -ForegroundColor Gray
                }
            } catch {
                # Service not ready yet
            }
            Start-Sleep -Seconds 1
        }

        if (-not $healthCheckSuccess) {
            Write-Warning "Health check did not return expected version within 30 seconds"
            $healthCheckDuration = 30
        }

        # Complete deployment tracking
        $totalDuration = (Get-Date) - $deployStart
        $completeScript = @"
import sys
import os
sys.path.insert(0, r'$currentJunction\src')
os.environ['DATABASE_PATH'] = r'$dbPath'

from db import complete_deployment

complete_deployment(
    $deploymentId,
    status='success' if $healthCheckSuccess else 'warning',
    total_duration=$($totalDuration.TotalSeconds),
    downtime_duration=$cutoverDuration,
    health_check_success=$($healthCheckSuccess.ToString().ToLower()),
    health_check_duration=$healthCheckDuration,
    time_to_healthy='$timeToHealthy' if $healthCheckSuccess else None
)
print('Deployment metrics recorded')
"@
        $completeScript | & $venvPython -c "exec(input())"
        Write-Host "Deployment metrics recorded successfully" -ForegroundColor Green
    }
} catch {
    Write-Warning "Failed to record deployment metrics: $_"
    Write-Host "Deployment succeeded but metrics recording failed" -ForegroundColor Yellow
}

# Also record in legacy table for backward compatibility
$legacyRecordScript = @"
import sys
import os
sys.path.insert(0, r'$currentJunction\src')
os.environ['DATABASE_PATH'] = r'$dbPath'
from db import record_deployment
record_deployment('$version', 'azure-arc', 'Deployed via Azure Arc run-command')
"@

try {
    $legacyRecordScript | & $venvPython -c "exec(input())"
} catch {
    # Ignore legacy table errors
}
