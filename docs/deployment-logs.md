# Deployment Logging

## Overview
Every deployment creates a detailed log file with timestamps for each step, allowing you to audit deployments and troubleshoot issues.

## Log Location
Deployment logs are stored at:
```
C:\Apps\DicomGatewayMock\logs\deployments\deployment-YYYYMMDD-HHMMSS.log
```

Example: `deployment-20260114-170534.log`

## Log Format
Each log entry includes:
- **Timestamp**: `yyyy-MM-dd HH:mm:ss.fff` (millisecond precision)
- **Level**: `INFO`, `SUCCESS`, `WARNING`, or `ERROR`
- **Message**: Detailed description of the event

Example entry:
```
[2026-01-14 17:05:34.123] [INFO] STEP 2: Extracting package
[2026-01-14 17:05:42.456] [SUCCESS] STEP 2 COMPLETED: Package extracted (took 8.33s)
```

## Logged Events

### Deployment Start
- Script path and parameters
- User and computer information
- Base installation path
- Service name
- Package URL and size

### Download Phase (if applicable)
- Package URL
- Download start
- Download completion with duration

### Step 1: Directory Structure
- Directory creation events
- Completion timestamp

### Step 2: Package Extraction
- Version detection
- Extraction target path
- Extraction duration
- Completion with timing

### Step 3: Virtual Environment Rebuild
- Python location found
- Virtual environment creation
- Dependency installation
- Total rebuild duration

### Step 4: Database Migrations
- Migration script execution
- Database backup location
- Migration success/failure
- Migration duration

### Step 5-7: Critical Section (Service Cutover)
- Critical section start marker
- Service stop event
- Junction switch to new version
- Service start event
- Critical section completion with downtime measurement

### Step 8: Deployment Metrics Recording
- Metrics initialization with deployment ID
- Health check result (PASSED/FAILED)
- Time to healthy measurement
- Metrics recording success

### Step 9: Version Cleanup
- Old versions removed
- Number of versions retained
- Cleanup completion

### Step 10-12: NSSM Configuration
- NSSM location found
- Service logging configuration
- Service configuration updates
- Service restart events

### Deployment Completion
- Final summary with all timing metrics
- Extract, venv, migration, and cutover durations
- Total deployment duration
- Service downtime
- Log file location

## Example Log File

```
[2026-01-14 17:05:30.001] [INFO] ========================================
[2026-01-14 17:05:30.002] [INFO] Deployment Started
[2026-01-14 17:05:30.003] [INFO] ========================================
[2026-01-14 17:05:30.004] [INFO] Script: C:\Packages\...\deploy.ps1
[2026-01-14 17:05:30.005] [INFO] User: aetip3
[2026-01-14 17:05:30.006] [INFO] Computer: VM-QZUM-VM1
[2026-01-14 17:05:30.007] [INFO] Base Path: C:\Apps\DicomGatewayMock
[2026-01-14 17:05:30.008] [INFO] Service: DicomGatewayMock
[2026-01-14 17:05:30.100] [INFO] Package URL: https://github.com/...
[2026-01-14 17:05:30.101] [INFO] Starting package download...
[2026-01-14 17:05:38.456] [SUCCESS] Package downloaded successfully (took 8.36s)
[2026-01-14 17:05:38.500] [INFO] ZIP Path: C:\Windows\TEMP\...
[2026-01-14 17:05:38.501] [INFO] ZIP file size: 15.3 MB
[2026-01-14 17:05:38.600] [INFO] STEP 1: Preparing directory structure
[2026-01-14 17:05:38.650] [INFO]   Created directory: C:\Apps\...\releases
[2026-01-14 17:05:38.700] [SUCCESS] STEP 1 COMPLETED: Directory structure ready
[2026-01-14 17:05:38.800] [INFO] STEP 2: Extracting package
[2026-01-14 17:05:39.000] [INFO]   Detected version: fa4a475
[2026-01-14 17:05:39.100] [INFO]   Extracting to: C:\Apps\...\releases\fa4a475
[2026-01-14 17:05:47.234] [SUCCESS] STEP 2 COMPLETED: Package extracted (took 8.43s)
[2026-01-14 17:05:47.300] [INFO] STEP 3: Rebuilding virtual environment
[2026-01-14 17:05:50.500] [INFO]   Found Python: C:\Users\...\Python314\python.exe
[2026-01-14 17:06:32.789] [SUCCESS] STEP 3 COMPLETED: Virtual environment rebuilt (took 45.49s)
[2026-01-14 17:06:32.900] [INFO] STEP 4: Running database migrations
[2026-01-14 17:06:35.123] [SUCCESS]   Database migrations completed successfully
[2026-01-14 17:06:44.567] [SUCCESS] STEP 4 COMPLETED: Database management (took 11.67s)
[2026-01-14 17:06:44.600] [INFO] ========================================
[2026-01-14 17:06:44.601] [INFO] CRITICAL SECTION: Service Cutover Starting
[2026-01-14 17:06:44.602] [INFO] ========================================
[2026-01-14 17:06:44.700] [INFO] STEP 5: Stopping service
[2026-01-14 17:06:46.234] [SUCCESS]   Service stopped successfully
[2026-01-14 17:06:46.300] [INFO] STEP 6: Switching junction
[2026-01-14 17:06:46.456] [SUCCESS]   Junction switched to version: fa4a475
[2026-01-14 17:06:46.500] [INFO] STEP 7: Starting service
[2026-01-14 17:06:58.123] [SUCCESS]   Service started successfully
[2026-01-14 17:06:58.200] [SUCCESS] ========================================
[2026-01-14 17:06:58.201] [SUCCESS] CRITICAL SECTION COMPLETED: Downtime 13.50 seconds
[2026-01-14 17:06:58.202] [SUCCESS] ========================================
[2026-01-14 17:06:58.300] [INFO] STEP 8: Recording deployment metrics
[2026-01-14 17:07:05.678] [SUCCESS]   Deployment metrics recorded (ID: 42)
[2026-01-14 17:07:05.679] [INFO]   Health check: PASSED
[2026-01-14 17:07:05.680] [INFO]   Time to healthy: 15.48 seconds
[2026-01-14 17:07:05.800] [INFO] STEP 9: Cleaning up old versions
[2026-01-14 17:07:06.123] [INFO]   Removing old version: 1c0c6fc
[2026-01-14 17:07:08.456] [SUCCESS] STEP 9 COMPLETED: Cleanup complete - 3 version(s) retained
[2026-01-14 17:07:08.500] [INFO] STEP 10: Locating NSSM
[2026-01-14 17:07:08.600] [SUCCESS]   Found NSSM in PATH: C:\ProgramData\chocolatey\bin\nssm.exe
[2026-01-14 17:07:08.700] [INFO] STEP 11: Configuring service logging
[2026-01-14 17:07:08.800] [SUCCESS] STEP 11 COMPLETED: Log directory configured
[2026-01-14 17:07:08.900] [INFO] STEP 12: Configuring Windows Service
[2026-01-14 17:07:10.123] [SUCCESS]   Service configuration updated
[2026-01-14 17:07:18.456] [SUCCESS] STEP 12 COMPLETED: Service configured and running
[2026-01-14 17:07:18.500] [INFO] ========================================
[2026-01-14 17:07:18.501] [SUCCESS] DEPLOYMENT COMPLETED SUCCESSFULLY
[2026-01-14 17:07:18.502] [INFO] ========================================
[2026-01-14 17:07:18.503] [INFO] Version: fa4a475
[2026-01-14 17:07:18.504] [INFO] Total Duration: 108.50 seconds
[2026-01-14 17:07:18.505] [INFO] Service Downtime: 13.50 seconds
[2026-01-14 17:07:18.506] [INFO] Extract: 8.43s | venv: 45.49s | Migration: 11.67s | Cutover: 13.50s
[2026-01-14 17:07:18.507] [INFO] Deployment log saved to: C:\Apps\...\deployment-20260114-170530.log
[2026-01-14 17:07:18.508] [INFO] ========================================
```

## Viewing Logs

### View Most Recent Deployment
```powershell
# Get the most recent deployment log
$latestLog = Get-ChildItem "C:\Apps\DicomGatewayMock\logs\deployments\" -Filter "*.log" | 
    Sort-Object CreationTime -Descending | 
    Select-Object -First 1

Get-Content $latestLog.FullName
```

### View Last 50 Lines
```powershell
Get-Content "C:\Apps\DicomGatewayMock\logs\deployments\deployment-*.log" -Tail 50
```

### Search for Errors
```powershell
Get-ChildItem "C:\Apps\DicomGatewayMock\logs\deployments\" -Filter "*.log" |
    Select-String -Pattern "\[ERROR\]" |
    Format-Table Line, Filename -AutoSize
```

### View Only Critical Section
```powershell
$log = Get-Content "C:\Apps\DicomGatewayMock\logs\deployments\deployment-*.log"
$log | Where-Object { $_ -match "CRITICAL SECTION|STEP 5|STEP 6|STEP 7|Downtime" }
```

### Calculate Average Deployment Time
```powershell
$logs = Get-ChildItem "C:\Apps\DicomGatewayMock\logs\deployments\" -Filter "*.log"
$durations = @()

foreach ($log in $logs) {
    $content = Get-Content $log.FullName | Out-String
    if ($content -match "Total Duration: ([\d.]+) seconds") {
        $durations += [double]$matches[1]
    }
}

if ($durations.Count -gt 0) {
    $avg = ($durations | Measure-Object -Average).Average
    Write-Host "Average deployment time: $([math]::Round($avg, 2)) seconds"
    Write-Host "Min: $([math]::Round(($durations | Measure-Object -Minimum).Minimum, 2))s"
    Write-Host "Max: $([math]::Round(($durations | Measure-Object -Maximum).Maximum, 2))s"
}
```

## Log Retention

Deployment logs are kept indefinitely by default. To manage log retention:

### Delete Logs Older Than 90 Days
```powershell
$cutoffDate = (Get-Date).AddDays(-90)
Get-ChildItem "C:\Apps\DicomGatewayMock\logs\deployments\" -Filter "*.log" |
    Where-Object { $_.CreationTime -lt $cutoffDate } |
    Remove-Item -Force
```

### Keep Only Last 20 Deployments
```powershell
$logsDir = "C:\Apps\DicomGatewayMock\logs\deployments\"
$logsToKeep = 20

$allLogs = Get-ChildItem $logsDir -Filter "*.log" | 
    Sort-Object CreationTime -Descending

if ($allLogs.Count -gt $logsToKeep) {
    $logsToDelete = $allLogs | Select-Object -Skip $logsToKeep
    $logsToDelete | Remove-Item -Force
    Write-Host "Deleted $($logsToDelete.Count) old deployment logs"
}
```

## Integration with Monitoring

You can integrate deployment logs with monitoring systems:

### Send Summary to Monitoring System
```powershell
$log = Get-Content "C:\Apps\DicomGatewayMock\logs\deployments\deployment-*.log" -Tail 100
$errors = $log | Where-Object { $_ -match "\[ERROR\]" }
$warnings = $log | Where-Object { $_ -match "\[WARNING\]" }

if ($errors.Count -gt 0) {
    # Send alert to monitoring system
    Write-Host "Deployment had $($errors.Count) errors!"
}
```

### Export to JSON for Analysis
```powershell
function Parse-DeploymentLog {
    param([string]$LogPath)
    
    $content = Get-Content $LogPath
    $deployment = @{
        LogFile = Split-Path $LogPath -Leaf
        Events = @()
    }
    
    foreach ($line in $content) {
        if ($line -match '^\[(.+?)\] \[(.+?)\] (.+)$') {
            $deployment.Events += @{
                Timestamp = $matches[1]
                Level = $matches[2]
                Message = $matches[3]
            }
        }
    }
    
    return $deployment | ConvertTo-Json -Depth 5
}

# Use it
$json = Parse-DeploymentLog "C:\Apps\DicomGatewayMock\logs\deployments\deployment-20260114-170530.log"
$json | Out-File "deployment-analysis.json"
```

## Troubleshooting

### Deployment Failed - Check Log
1. Find the most recent deployment log
2. Search for `[ERROR]` entries
3. Look at the last few lines before the error
4. Check which STEP failed

### Slow Deployment - Analyze Phases
1. Open the deployment log
2. Look for "STEP X COMPLETED" messages
3. Compare phase durations:
   - Extract should be < 15s
   - venv rebuild should be < 60s
   - Migrations should be < 20s
   - Cutover (downtime) should be < 20s

### Service Didn't Start - Check Cutover Section
1. Search for "CRITICAL SECTION" in the log
2. Verify all three steps (5, 6, 7) completed
3. Check if service start was successful
4. Look for NSSM-related errors

## Best Practices

1. **Always check the deployment log** after deployment
2. **Archive old logs** to external storage for long-term analysis
3. **Monitor log size** - each deployment log is typically 5-15 KB
4. **Integrate with CI/CD** - Parse logs for automated validation
5. **Set up alerts** for ERROR or WARNING entries
6. **Compare logs** between successful and failed deployments
7. **Track trends** - Are deployments getting slower over time?
