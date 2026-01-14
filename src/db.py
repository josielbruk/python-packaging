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
    """Record a deployment in history"""
    query = """
        INSERT INTO deployment_history (version, deployment_method, notes)
        VALUES (?, ?, ?)
    """
    return execute_write(query, (version, method, notes))


def get_deployment_history(limit=10):
    """Get recent deployment history"""
    query = """
        SELECT * FROM deployment_history
        ORDER BY deployed_at DESC
        LIMIT ?
    """
    return execute_query(query, (limit,))


def get_current_deployment():
    """Get the most recent deployment"""
    query = """
        SELECT * FROM deployment_history
        ORDER BY deployed_at DESC
        LIMIT 1
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
