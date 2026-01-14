#!/usr/bin/env python3
"""
Database diagnostic script
Checks database schema, tables, and data
"""
import os
import sys
import sqlite3
from pathlib import Path

# Set DATABASE_PATH if not already set
if 'DATABASE_PATH' not in os.environ:
    os.environ['DATABASE_PATH'] = r'C:\Apps\DicomGatewayMock\data\gateway.db'

# Add src to path
script_dir = Path(__file__).parent.parent
sys.path.insert(0, str(script_dir / 'src'))

from db import get_database_path

def main():
    db_path = get_database_path()
    print(f"Database path: {db_path}")
    print(f"Database exists: {os.path.exists(db_path)}")

    if not os.path.exists(db_path):
        print("\n[ERROR] Database file does not exist!")
        print(f"Expected location: {db_path}")
        return 1

    # Get file size
    db_size = os.path.getsize(db_path)
    print(f"Database size: {db_size:,} bytes ({db_size/1024:.2f} KB)")

    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # Check SQLite version
        cursor.execute("SELECT sqlite_version()")
        sqlite_version = cursor.fetchone()[0]
        print(f"\nSQLite version: {sqlite_version}")

        # List all tables
        cursor.execute("""
            SELECT name, sql FROM sqlite_master
            WHERE type='table'
            ORDER BY name
        """)
        tables = cursor.fetchall()

        print(f"\nTables found: {len(tables)}")
        print("=" * 60)

        for table in tables:
            table_name = table['name']
            print(f"\n[TABLE] {table_name}")

            # Count rows
            cursor.execute(f"SELECT COUNT(*) as count FROM {table_name}")
            row_count = cursor.fetchone()['count']
            print(f"  Rows: {row_count}")

            # Show schema
            cursor.execute(f"PRAGMA table_info({table_name})")
            columns = cursor.fetchall()
            print(f"  Columns: {len(columns)}")
            for col in columns:
                print(f"    - {col['name']} ({col['type']}){' PRIMARY KEY' if col['pk'] else ''}{' NOT NULL' if col['notnull'] else ''}")

        # Check schema version
        print("\n" + "=" * 60)
        print("\n[SCHEMA VERSION]")
        try:
            cursor.execute("SELECT * FROM schema_version ORDER BY applied_at DESC")
            versions = cursor.fetchall()
            if versions:
                print(f"Current schema version: {versions[0]['version']}")
                print(f"Applied at: {versions[0]['applied_at']}")
                print(f"\nAll migrations:")
                for v in reversed(versions):
                    print(f"  v{v['version']}: {v['description']} (applied: {v['applied_at']})")
            else:
                print("No schema versions found!")
        except sqlite3.OperationalError as e:
            print(f"[ERROR] Could not read schema_version table: {e}")

        # Check deployment history
        print("\n" + "=" * 60)
        print("\n[DEPLOYMENT HISTORY]")
        try:
            cursor.execute("SELECT * FROM deployment_history ORDER BY deployed_at DESC LIMIT 5")
            deployments = cursor.fetchall()
            if deployments:
                print(f"Recent deployments: {len(deployments)}")
                for d in deployments:
                    print(f"  - {d['version']} at {d['deployed_at']} via {d['deployment_method']}")
            else:
                print("No deployment history records found.")
        except sqlite3.OperationalError as e:
            print(f"[WARNING] deployment_history table doesn't exist or is inaccessible: {e}")

        # Check deployment metrics
        print("\n" + "=" * 60)
        print("\n[DEPLOYMENT METRICS]")
        try:
            cursor.execute("SELECT * FROM deployment_metrics ORDER BY deployment_started_at DESC LIMIT 5")
            metrics = cursor.fetchall()
            if metrics:
                print(f"Recent deployments with metrics: {len(metrics)}")
                for m in metrics:
                    print(f"  - {m['version']} (ID: {m['id']})")
                    print(f"    Started: {m['deployment_started_at']}")
                    print(f"    Status: {m['deployment_status']}")
                    if m['total_duration']:
                        print(f"    Duration: {m['total_duration']:.2f}s (downtime: {m['downtime_duration']:.2f}s)")
                    if m['health_check_success']:
                        print(f"    Health check: PASSED (time to healthy: {m['time_to_healthy']}s)")
                    else:
                        print(f"    Health check: FAILED")
                    print()
            else:
                print("No deployment metrics records found.")
        except sqlite3.OperationalError as e:
            print(f"[WARNING] deployment_metrics table doesn't exist or is inaccessible: {e}")

        # Check indexes
        print("=" * 60)
        print("\n[INDEXES]")
        cursor.execute("""
            SELECT name, tbl_name FROM sqlite_master
            WHERE type='index' AND sql IS NOT NULL
            ORDER BY tbl_name, name
        """)
        indexes = cursor.fetchall()
        if indexes:
            current_table = None
            for idx in indexes:
                if idx['tbl_name'] != current_table:
                    current_table = idx['tbl_name']
                    print(f"\n  {current_table}:")
                print(f"    - {idx['name']}")
        else:
            print("No indexes found.")

        conn.close()

        print("\n" + "=" * 60)
        print("[DIAGNOSTIC COMPLETE]")
        return 0

    except Exception as e:
        print(f"\n[ERROR] Failed to analyze database: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
