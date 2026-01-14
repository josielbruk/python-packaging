# Database Management Guide

## Overview

The application uses SQLite for local data persistence. The database is stored **outside the versioned releases** to ensure data persists across deployments.

## Directory Structure

```
C:\Apps\DicomGatewayMock\
├── data\                      # Persistent data (NEVER DELETED)
│   ├── gateway.db            # SQLite database
│   └── gateway.db.backup-*   # Automatic backups
├── releases\                  # Versioned application releases
│   ├── e6148dc\
│   ├── 67a79b1\
│   └── d0e45a6\
├── current -> releases\d0e45a6  # Junction to active version
└── previous -> releases\67a79b1 # Junction to previous version
```

## Database Location

- **Production**: `C:\Apps\DicomGatewayMock\data\gateway.db`
- **Development**: `./data/gateway.db`
- **Override**: Set `DATABASE_PATH` environment variable

## Automatic Migration on Deployment

During deployment, the script automatically:

1. ✅ **Creates data directory** if it doesn't exist
2. ✅ **Backs up database** before running migrations
3. ✅ **Runs migration script** (`src/migrations/migrate.py`)
4. ✅ **Keeps last 5 backups** (auto-cleanup older backups)
5. ✅ **Continues deployment** even if migrations fail (with warning)

## Schema Migrations

### Adding a New Migration

1. Edit `src/migrations/migrate.py`
2. Add new migration function:

```python
def apply_migration_v3(conn):
    """Add new table or column"""
    print("  Applying migration v3: Description")

    conn.execute("""
        CREATE TABLE new_table (
            id INTEGER PRIMARY KEY,
            data TEXT
        )
    """)

    conn.execute("""
        INSERT INTO schema_version (version, description)
        VALUES (3, 'Added new_table')
    """)

    conn.commit()
    print("  ✓ Migration v3 completed")
```

3. Register in `MIGRATIONS` dict:

```python
MIGRATIONS = {
    1: apply_migration_v1,
    2: apply_migration_v2,
    3: apply_migration_v3,  # Add this
}
```

4. Deploy - migrations run automatically!

### Manual Migration

Run migrations manually:

```powershell
# Set database path
$env:DATABASE_PATH = "C:\Apps\DicomGatewayMock\data\gateway.db"

# Run migrations
python src/migrations/migrate.py
```

## Using Database in Application

Import the database helper:

```python
from src.db import get_connection, execute_query, execute_write

# Example: Store DICOM study
from src.db import store_dicom_study
store_dicom_study(
    study_uid="1.2.3.4.5",
    patient_id="P12345",
    patient_name="Doe^John",
    study_date="20260114",
    study_description="CT Chest"
)

# Example: Query recent studies
from src.db import get_recent_studies
studies = get_recent_studies(limit=10)
for study in studies:
    print(f"{study['patient_name']} - {study['study_date']}")

# Example: Custom query
from src.db import execute_query
rows = execute_query(
    "SELECT * FROM dicom_studies WHERE patient_id = ?",
    ("P12345",)
)
```

## Database Backups

### Automatic Backups (During Deployment)

- Created before migrations run
- Format: `gateway.db.backup-20260114-163022`
- Keeps last 5 backups
- Location: `C:\Apps\DicomGatewayMock\data\`

### Manual Backup

```powershell
# Copy database
Copy-Item "C:\Apps\DicomGatewayMock\data\gateway.db" `
          "C:\Apps\DicomGatewayMock\data\gateway.db.backup-manual"
```

### Restore from Backup

```powershell
# Stop service
Stop-Service DicomGatewayMock

# Restore backup
Copy-Item "C:\Apps\DicomGatewayMock\data\gateway.db.backup-20260114-163022" `
          "C:\Apps\DicomGatewayMock\data\gateway.db" -Force

# Start service
Start-Service DicomGatewayMock
```

## Troubleshooting

### Database Locked

If you get "database is locked" errors:

```powershell
# Stop the service
Stop-Service DicomGatewayMock

# Check for locks
lsof C:\Apps\DicomGatewayMock\data\gateway.db  # Linux/Mac
# or use Process Explorer on Windows

# Start service
Start-Service DicomGatewayMock
```

### Migration Failed

If migration fails during deployment:

1. Check deployment output for error details
2. Restore from automatic backup:
   ```powershell
   $latestBackup = Get-ChildItem "C:\Apps\DicomGatewayMock\data\gateway.db.backup-*" |
                   Sort-Object CreationTime -Descending |
                   Select-Object -First 1
   Copy-Item $latestBackup.FullName "C:\Apps\DicomGatewayMock\data\gateway.db" -Force
   ```
3. Roll back deployment if needed
4. Fix migration script and redeploy

### Database Corruption

If database is corrupted:

```powershell
# Stop service
Stop-Service DicomGatewayMock

# Check integrity
sqlite3 gateway.db "PRAGMA integrity_check;"

# If corrupted, restore from backup
Copy-Item gateway.db.backup-YYYYMMDD-HHMMSS gateway.db -Force

# Start service
Start-Service DicomGatewayMock
```

## Current Schema (v2)

### Tables

**dicom_studies**
- `study_instance_uid` (TEXT PRIMARY KEY)
- `patient_id` (TEXT)
- `patient_name` (TEXT)
- `study_date` (TEXT)
- `study_description` (TEXT)
- `received_at` (TIMESTAMP)

**gateway_logs**
- `id` (INTEGER PRIMARY KEY)
- `timestamp` (TIMESTAMP)
- `level` (TEXT)
- `message` (TEXT)
- `study_instance_uid` (TEXT, FK)

**performance_metrics**
- `id` (INTEGER PRIMARY KEY)
- `timestamp` (TIMESTAMP)
- `metric_name` (TEXT)
- `metric_value` (REAL)
- `study_instance_uid` (TEXT, FK)

**schema_version**
- `version` (INTEGER PRIMARY KEY)
- `description` (TEXT)
- `applied_at` (TIMESTAMP)

## Best Practices

1. ✅ **Always test migrations** in development first
2. ✅ **Use transactions** for data consistency
3. ✅ **Keep migrations small** and focused
4. ✅ **Never edit old migrations** - always create new ones
5. ✅ **Document schema changes** in migration descriptions
6. ✅ **Monitor database size** and archive old data if needed
7. ✅ **Test rollback** scenarios with database backups
