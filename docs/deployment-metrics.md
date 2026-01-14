# Deployment Metrics Tracking

## Overview
The deployment system tracks comprehensive metrics for every deployment, giving you full visibility into deployment performance, reliability, and system health.

## Collected Metrics

### Basic Information
- **version**: Git commit SHA or tag being deployed
- **previous_version**: Version being replaced (for tracking upgrade paths)
- **deployment_started_at**: ISO timestamp when deployment began
- **deployment_completed_at**: ISO timestamp when deployment finished
- **deployment_status**: `success`, `warning`, or `failed`

### VM Information
- **hostname**: Computer name where service is running
- **os_version**: Windows OS version (e.g., "Microsoft Windows Server 2019")
- **python_version**: Python version used for the deployment

### Deployment Phase Timings (in seconds)
- **extract_duration**: Time to extract ZIP package
- **venv_rebuild_duration**: Time to rebuild virtual environment
- **migration_duration**: Time to run database migrations
- **cutover_duration**: Service downtime (stop→switch junction→start)
- **total_duration**: End-to-end deployment time

### Health Verification
- **health_check_success**: Boolean - did health endpoint return correct version?
- **health_check_duration**: How long health verification took
- **time_to_healthy**: Seconds from service start until health endpoint responds with correct version

### Additional Context
- **deployment_method**: How it was deployed (`azure-arc`, `manual`, etc.)
- **error_message**: Error details if deployment failed
- **notes**: Free-form notes about the deployment

## Deployment Statistics

The system also calculates aggregate statistics across all deployments:

- **total_deployments**: Total number of deployments
- **successful_deployments**: Count of successful deployments
- **failed_deployments**: Count of failed deployments
- **avg_duration**: Average total deployment time
- **avg_downtime**: Average service downtime
- **min_duration**: Fastest deployment time
- **max_duration**: Slowest deployment time
- **avg_health_check_time**: Average time for health verification

## Health Endpoint

The `/health` endpoint returns all metrics in JSON format:

```bash
curl http://vm-qzum-vm1:8080/health
```

### Response Structure

```json
{
  "status": "healthy",
  "service": "DicomGatewayMock",
  "version": "b0c2642",
  "python_version": "3.14.2",
  
  "deployment_metrics": [
    {
      "version": "b0c2642",
      "previous_version": "1c0c6fc",
      "hostname": "VM-QZUM-VM1",
      "deployment_started_at": "2026-01-14T18:45:00",
      "deployment_completed_at": "2026-01-14T18:47:15",
      "total_duration": 135.4,
      "downtime_duration": 13.2,
      "extract_duration": 8.5,
      "venv_rebuild_duration": 45.3,
      "migration_duration": 12.1,
      "cutover_duration": 13.2,
      "health_check_success": true,
      "time_to_healthy": "15.8",
      "status": "success"
    }
  ],
  
  "deployment_statistics": {
    "total_deployments": 15,
    "successful_deployments": 14,
    "failed_deployments": 1,
    "avg_duration": 142.3,
    "avg_downtime": 13.5,
    "min_duration": 125.7,
    "max_duration": 180.2,
    "avg_health_check_time": 2.3
  },
  
  "deployment_history": [
    {
      "version": "b0c2642",
      "deployed_at": "2026-01-14 18:47:15",
      "method": "azure-arc",
      "notes": "Deployed via Azure Arc run-command"
    }
  ]
}
```

## Database Schema

### deployment_metrics Table

```sql
CREATE TABLE deployment_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    -- Version and timing
    version TEXT NOT NULL,
    previous_version TEXT,
    deployment_started_at TEXT NOT NULL,
    deployment_completed_at TEXT,
    
    -- VM Information
    hostname TEXT,
    os_version TEXT,
    python_version TEXT,
    
    -- Deployment phases (seconds)
    extract_duration REAL,
    venv_rebuild_duration REAL,
    migration_duration REAL,
    cutover_duration REAL,
    total_duration REAL,
    downtime_duration REAL,
    
    -- Health verification
    health_check_success INTEGER DEFAULT 0,
    health_check_duration REAL,
    time_to_healthy TEXT,
    
    -- Deployment info
    deployment_method TEXT DEFAULT 'manual',
    deployment_status TEXT DEFAULT 'in-progress',
    error_message TEXT,
    notes TEXT,
    
    UNIQUE(version, deployment_started_at)
);
```

## Use Cases

### 1. Monitor Deployment Performance
Track how long each phase takes to identify bottlenecks:
- If `venv_rebuild_duration` is high → Consider caching dependencies
- If `migration_duration` is high → Review database migration efficiency
- If `cutover_duration` is high → Check service startup time

### 2. Track Service Health
Monitor `time_to_healthy` to understand:
- How quickly service becomes operational after deployment
- If there are issues with service initialization
- Regression in startup performance

### 3. Deployment Reliability
Use `deployment_statistics` to:
- Calculate success rate
- Identify trends in deployment duration
- Set SLAs for deployment time and downtime

### 4. Upgrade Impact Analysis
Compare `previous_version` and `version` to:
- Track which upgrades are more risky
- Identify versions that cause issues
- Plan rollback strategies

### 5. Infrastructure Planning
Use VM information to:
- Identify which servers have which versions
- Plan infrastructure upgrades (Python, OS)
- Correlate performance with VM configuration

## Querying Metrics

### Python Example

```python
from db import get_deployment_metrics, get_deployment_statistics, get_latest_deployment_metrics

# Get last 10 deployments
metrics = get_deployment_metrics(limit=10)
for m in metrics:
    print(f"{m['version']}: {m['total_duration']}s total, {m['downtime_duration']}s downtime")

# Get aggregate statistics
stats = get_deployment_statistics()
print(f"Success rate: {stats['successful_deployments'] / stats['total_deployments'] * 100}%")
print(f"Average downtime: {stats['avg_downtime']}s")

# Get latest deployment
latest = get_latest_deployment_metrics()
print(f"Current version: {latest['version']} deployed at {latest['deployment_completed_at']}")
```

### SQL Query Examples

```sql
-- Find slowest deployments
SELECT version, total_duration, downtime_duration
FROM deployment_metrics
WHERE deployment_status = 'success'
ORDER BY total_duration DESC
LIMIT 10;

-- Average deployment time by month
SELECT 
    strftime('%Y-%m', deployment_started_at) as month,
    AVG(total_duration) as avg_duration,
    AVG(downtime_duration) as avg_downtime,
    COUNT(*) as deployments
FROM deployment_metrics
WHERE deployment_status = 'success'
GROUP BY month
ORDER BY month DESC;

-- Deployments that took longer than average
SELECT version, total_duration, downtime_duration
FROM deployment_metrics
WHERE total_duration > (
    SELECT AVG(total_duration) 
    FROM deployment_metrics 
    WHERE deployment_status = 'success'
);

-- Health check failures
SELECT version, deployment_started_at, error_message
FROM deployment_metrics
WHERE health_check_success = 0
ORDER BY deployment_started_at DESC;
```

## Alerting Recommendations

Set up alerts for:

1. **High Downtime**: `downtime_duration > 30` seconds
2. **Long Deployments**: `total_duration > 300` seconds (5 minutes)
3. **Failed Health Checks**: `health_check_success = 0`
4. **Failed Deployments**: `deployment_status = 'failed'`
5. **Slow Health Recovery**: `time_to_healthy > 60` seconds

## Troubleshooting

### Metrics Not Being Recorded

1. Check database exists: `C:\Apps\DicomGatewayMock\data\gateway.db`
2. Verify DATABASE_PATH environment variable is set in startup script
3. Check deployment logs for Python errors during metrics recording
4. Verify migrations completed: `SELECT version FROM schema_version ORDER BY version DESC LIMIT 1` should return `4`

### Health Endpoint Not Responding

1. Check service is running: `Get-Service DicomGatewayMock`
2. Verify port 8080 is accessible: `Test-NetConnection -ComputerName localhost -Port 8080`
3. Check service logs: `C:\Apps\DicomGatewayMock\logs\DicomGatewayMock-*.log`

### Empty deployment_metrics Table

1. Ensure you're deploying with version b0c2642 or later
2. Check if legacy `deployment_history` table has data (old format)
3. Verify Step 8 in deployment script completes without errors

## Future Enhancements

Potential additions to consider:

- **Resource utilization**: CPU, memory during deployment
- **Network metrics**: Download speed, package size
- **Database size**: Track database growth over time
- **Rollback tracking**: Record when rollbacks occur
- **Deployment triggers**: Who initiated deployment
- **Configuration changes**: Track config file modifications
- **Dependency versions**: Track package versions installed
