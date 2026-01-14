"""
Database helper for SQLite persistence
Provides connection and query helpers
"""
import os
import sqlite3
from pathlib import Path
from contextlib import contextmanager


def get_database_path():
    """
    Get database path from environment or use default persistent location

    In production: C:/Apps/DicomGatewayMock/data/gateway.db
    In development: ./data/gateway.db
    """
    db_path = os.environ.get('DATABASE_PATH')
    if not db_path:
        # Default to data directory relative to project root
        data_dir = Path(__file__).parent.parent.parent / 'data'
        data_dir.mkdir(exist_ok=True)
        db_path = str(data_dir / 'gateway.db')
    return db_path


@contextmanager
def get_connection():
    """
    Context manager for database connections

    Usage:
        with get_connection() as conn:
            cursor = conn.execute("SELECT * FROM table")
            rows = cursor.fetchall()
    """
    conn = sqlite3.connect(get_database_path())
    conn.row_factory = sqlite3.Row  # Enable column access by name
    conn.execute("PRAGMA foreign_keys = ON")  # Enable foreign key constraints
    try:
        yield conn
    finally:
        conn.close()


def execute_query(query, params=None):
    """
    Execute a SELECT query and return results

    Args:
        query: SQL query string
        params: Query parameters (tuple or dict)

    Returns:
        List of sqlite3.Row objects
    """
    with get_connection() as conn:
        cursor = conn.execute(query, params or ())
        return cursor.fetchall()


def execute_write(query, params=None):
    """
    Execute an INSERT/UPDATE/DELETE query

    Args:
        query: SQL query string
        params: Query parameters (tuple or dict)

    Returns:
        Number of affected rows
    """
    with get_connection() as conn:
        cursor = conn.execute(query, params or ())
        conn.commit()
        return cursor.rowcount


def execute_many(query, params_list):
    """
    Execute a query with multiple parameter sets (batch insert/update)

    Args:
        query: SQL query string
        params_list: List of parameter tuples/dicts

    Returns:
        Number of affected rows
    """
    with get_connection() as conn:
        cursor = conn.executemany(query, params_list)
        conn.commit()
        return cursor.rowcount


# Example usage functions

def log_message(level, message, study_uid=None):
    """Log a message to the database"""
    query = """
        INSERT INTO gateway_logs (level, message, study_instance_uid)
        VALUES (?, ?, ?)
    """
    return execute_write(query, (level, message, study_uid))


def store_dicom_study(study_uid, patient_id, patient_name, study_date, study_description):
    """Store DICOM study metadata"""
    query = """
        INSERT OR REPLACE INTO dicom_studies
        (study_instance_uid, patient_id, patient_name, study_date, study_description)
        VALUES (?, ?, ?, ?, ?)
    """
    return execute_write(query, (study_uid, patient_id, patient_name, study_date, study_description))


def get_recent_studies(limit=10):
    """Get recent DICOM studies"""
    query = """
        SELECT * FROM dicom_studies
        ORDER BY received_at DESC
        LIMIT ?
    """
    return execute_query(query, (limit,))


def record_deployment(version, method='manual', notes=None):
    """Record a deployment in history (legacy table)"""
    query = """
        INSERT INTO deployment_history (version, deployment_method, notes)
        VALUES (?, ?, ?)
    """
    return execute_write(query, (version, method, notes))


def get_deployment_history(limit=10):
    """Get recent deployment history (legacy table)"""
    query = """
        SELECT * FROM deployment_history
        ORDER BY deployed_at DESC
        LIMIT ?
    """
    return execute_query(query, (limit,))


def get_current_deployment():
    """Get the most recent deployment (legacy table)"""
    query = """
        SELECT * FROM deployment_history
        ORDER BY deployed_at DESC
        LIMIT 1
    """
    rows = execute_query(query)
    return rows[0] if rows else None


# Enhanced deployment metrics functions

def start_deployment_tracking(version, previous_version=None, hostname=None, 
                             os_version=None, python_version=None, method='manual'):
    """Start tracking a new deployment - returns deployment_id"""
    from datetime import datetime
    
    query = """
        INSERT INTO deployment_metrics (
            version, previous_version, deployment_started_at,
            hostname, os_version, python_version,
            deployment_method, deployment_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'in-progress')
    """
    
    started_at = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.execute(query, (
            version, previous_version, started_at,
            hostname, os_version, python_version, method
        ))
        conn.commit()
        return cursor.lastrowid


def update_deployment_phase(deployment_id, **kwargs):
    """Update deployment phase timings and status"""
    # Build dynamic UPDATE query
    fields = []
    values = []
    
    for key, value in kwargs.items():
        fields.append(f"{key} = ?")
        values.append(value)
    
    if not fields:
        return
    
    values.append(deployment_id)
    query = f"UPDATE deployment_metrics SET {', '.join(fields)} WHERE id = ?"
    
    return execute_write(query, tuple(values))


def complete_deployment(deployment_id, status='success', error_message=None,
                       total_duration=None, downtime_duration=None,
                       health_check_success=False, health_check_duration=None,
                       time_to_healthy=None):
    """Mark deployment as complete with final metrics"""
    from datetime import datetime
    
    query = """
        UPDATE deployment_metrics
        SET deployment_completed_at = ?,
            deployment_status = ?,
            error_message = ?,
            total_duration = ?,
            downtime_duration = ?,
            health_check_success = ?,
            health_check_duration = ?,
            time_to_healthy = ?
        WHERE id = ?
    """
    
    completed_at = datetime.now().isoformat()
    return execute_write(query, (
        completed_at, status, error_message,
        total_duration, downtime_duration,
        1 if health_check_success else 0,
        health_check_duration, time_to_healthy,
        deployment_id
    ))


def get_deployment_metrics(limit=10):
    """Get recent deployment metrics"""
    query = """
        SELECT * FROM deployment_metrics
        ORDER BY deployment_started_at DESC
        LIMIT ?
    """
    return execute_query(query, (limit,))


def get_latest_deployment_metrics():
    """Get the most recent deployment metrics"""
    query = """
        SELECT * FROM deployment_metrics
        ORDER BY deployment_started_at DESC
        LIMIT 1
    """
    rows = execute_query(query)
    return rows[0] if rows else None


def get_deployment_statistics():
    """Get aggregate deployment statistics"""
    query = """
        SELECT 
            COUNT(*) as total_deployments,
            AVG(total_duration) as avg_duration,
            AVG(downtime_duration) as avg_downtime,
            MIN(total_duration) as min_duration,
            MAX(total_duration) as max_duration,
            SUM(CASE WHEN deployment_status = 'success' THEN 1 ELSE 0 END) as successful_deployments,
            SUM(CASE WHEN deployment_status = 'failed' THEN 1 ELSE 0 END) as failed_deployments,
            AVG(CASE WHEN health_check_success = 1 THEN health_check_duration END) as avg_health_check_time
        FROM deployment_metrics
        WHERE deployment_status != 'in-progress'
    """
    rows = execute_query(query)
    return rows[0] if rows else None


if __name__ == "__main__":
    # Test database connection
    print(f"Database path: {get_database_path()}")

    try:
        with get_connection() as conn:
            cursor = conn.execute("SELECT sqlite_version()")
            version = cursor.fetchone()[0]
            print(f"SQLite version: {version}")

            # Check if tables exist
            cursor = conn.execute("""
                SELECT name FROM sqlite_master
                WHERE type='table'
                ORDER BY name
            """)
            tables = [row[0] for row in cursor.fetchall()]
            if tables:
                print(f"Tables: {', '.join(tables)}")
            else:
                print("No tables found. Run migrations first: python src/migrations/migrate.py")
    except Exception as e:
        print(f"Database error: {e}")
