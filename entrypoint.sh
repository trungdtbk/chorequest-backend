#!/bin/bash
set -e

DATA_DIR="/app/data"
mkdir -p "$DATA_DIR/uploads"

export PYTHONPATH="$PYTHONPATH:."
PORT=8000
# 1. Clean up any leftover SQLite batch migration temp tables
# Define data directory

echo "Cleaning up SQLite temp tables..."
python - <<EOF
import sqlite3
import os
 
db_url = os.getenv("DATABASE_URL", "sqlite:////app/data/chores_os.db")
db_path = db_url.replace("sqlite:///", "")
 
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
 
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '_alembic_tmp_%'")
    temp_tables = cursor.fetchall()
 
    if temp_tables:
        for (table,) in temp_tables:
            print(f"Dropping temp table: {table}")
            cursor.execute(f"DROP TABLE IF EXISTS [{table}]")
        conn.commit()
        print(f"Dropped {len(temp_tables)} temp table(s).")
    else:
        print("No temp tables found.")
 
    conn.close()
except Exception as e:
    print(f"Warning: Temp table cleanup failed: {e}")
    # Non-fatal — continue to migration
EOF

# 2. Run Migrations
# This ensures the DB schema matches your models before the app starts
echo "Checking for database migrations..."
# If alembic_version table doesn't exist but tables do, stamp as initial
python - <<EOF
import sqlite3
import os
db_path = os.getenv("DATABASE_URL", "sqlite:////app/data/chores_os.db").replace("sqlite+aiosqlite://", "").replace("sqlite://", "")
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='alembic_version'")
    has_alembic = cursor.fetchone()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='chores'")
    has_tables = cursor.fetchone()
    conn.close()
    if has_tables and not has_alembic:
        print("Existing DB found without alembic tracking. Stamping as initial...")
        os.system("alembic stamp head")
    elif not has_tables:
        print("Fresh DB detected. Will run full migrations.")
except Exception as e:
    print(f"Warning: {e}")
EOF
alembic upgrade head

# 2. Check permissions and start the app
# We check if appuser (UID 1000) can write to the data directory
if su -s /bin/sh appuser -c "test -w $DATA_DIR" 2>/dev/null; then
    echo "Permissions OK. Running as appuser (UID 1000)"
    exec su -s /bin/sh appuser -c "python -m uvicorn main:app --host 0.0.0.0 --port $PORT"
else
    echo "WARNING: $DATA_DIR is not writable by appuser. Falling back to root."
    echo "To fix this permanently, run 'chown -R 1000:1000 ./data' on your host."
    exec python -m uvicorn main:app --host 0.0.0.0 --port $PORT
fi