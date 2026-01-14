#!/usr/bin/env python3
"""
Database migration script for SQLite
Handles schema initialization and version upgrades
"""
import os
import sqlite3
import sys
from pathlib import Path


def get_database_path():
    """Get database path from environment or use default"""
    db_path = os.environ.get('DATABASE_PATH')
    if not db_path:
        # Default to data directory relative to script
        data_dir = Path(__file__).parent.parent.parent / 'data'
        data_dir.mkdir(exist_ok=True)
        db_path = str(data_dir / 'gateway.db')
    return db_path


def get_schema_version(conn):
    """Get current schema version from database"""
    try:
        cursor = conn.execute("SELECT version FROM schema_version ORDER BY applied_at DESC LIMIT 1")
        row = cursor.fetchone()
        return row[0] if row else 0
    except sqlite3.OperationalError:
        # Table doesn't exist yet
        return 0


def create_schema_version_table(conn):
    """Create schema version tracking table"""
    conn.execute("""
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY,
            description TEXT NOT NULL,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()


def apply_migration_v1(conn):
    """Initial schema - create gateway tables"""
    print("  Applying migration v1: Initial schema")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS dicom_studies (
            study_instance_uid TEXT PRIMARY KEY,
            patient_id TEXT,
            patient_name TEXT,
            study_date TEXT,
            study_description TEXT,
            received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS gateway_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            level TEXT NOT NULL,
            message TEXT NOT NULL,
            study_instance_uid TEXT,
            FOREIGN KEY (study_instance_uid) REFERENCES dicom_studies(study_instance_uid)
        )
    """)

    conn.execute("""
        INSERT OR IGNORE INTO schema_version (version, description)
        VALUES (1, 'Initial schema - DICOM studies and logs')
    """)

    conn.commit()
    print("  [OK] Migration v1 completed")


def apply_migration_v2(conn):
    """Add performance metrics table"""
    print("  Applying migration v2: Performance metrics")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS performance_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            metric_name TEXT NOT NULL,
            metric_value REAL NOT NULL,
            study_instance_uid TEXT,
            FOREIGN KEY (study_instance_uid) REFERENCES dicom_studies(study_instance_uid)
        )
    """)

    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_metrics_timestamp
        ON performance_metrics(timestamp)
    """)

    conn.execute("""
        INSERT OR IGNORE INTO schema_version (version, description)
        VALUES (2, 'Added performance metrics table')
    """)

    conn.commit()
    print("  [OK] Migration v2 completed")


def apply_migration_v3(conn):
    """Add deployment history tracking"""
    print("  Applying migration v3: Deployment history")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS deployment_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version TEXT NOT NULL,
            deployed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            deployment_method TEXT DEFAULT 'manual',
            notes TEXT
        )
    """)

    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_deployment_version
        ON deployment_history(version)
    """)

    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_deployment_date
        ON deployment_history(deployed_at)
    """)

    conn.execute("""
        INSERT OR IGNORE INTO schema_version (version, description)
        VALUES (3, 'Added deployment history tracking')
    """)

    conn.commit()
    print("  [OK] Migration v3 completed")


# Migration registry - add new migrations here in order
MIGRATIONS = {
    1: apply_migration_v1,
    2: apply_migration_v2,
    3: apply_migration_v3,

def main():
    """Run database migrations"""
    db_path = get_database_path()
    print(f"Database path: {db_path}")

    # Create parent directory if needed
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)

    # Connect to database
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")  # Enable foreign key constraints

    try:
        # Ensure schema version table exists
        create_schema_version_table(conn)

        # Get current version
        current_version = get_schema_version(conn)
        print(f"Current schema version: {current_version}")
        print(f"Target schema version: {TARGET_VERSION}")

        if current_version >= TARGET_VERSION:
            print("[OK] Database is up to date")
            return 0

        # Apply pending migrations
        print(f"Applying {TARGET_VERSION - current_version} migration(s)...")

        for version in range(current_version + 1, TARGET_VERSION + 1):
            if version in MIGRATIONS:
                MIGRATIONS[version](conn)
            else:
                print(f"  WARNING: Migration v{version} not found")

        print(f"[OK] Database migrated to version {TARGET_VERSION}")
        return 0

    except Exception as e:
        print(f"[ERROR] Migration failed: {e}", file=sys.stderr)
        conn.rollback()
        return 1

    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
