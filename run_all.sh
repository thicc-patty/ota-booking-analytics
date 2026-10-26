#!/usr/bin/env bash
# Linux/macOS version of run_all.bat. Rebuilds the database "ota" and runs steps 1 to 4 and 7.
# Usage: PGUSER=postgres PGHOST=localhost ./run_all.sh
set -euo pipefail
cd "$(dirname "$0")"
psql -d postgres -c "DROP DATABASE IF EXISTS ota;"
psql -d postgres -c "CREATE DATABASE ota;"
for f in 01_schema 02_load 03_clean 04_data_quality_checks 07_views_for_powerbi; do
  echo "Running $f ..."
  psql -d ota -v ON_ERROR_STOP=1 -q -f "sql/$f.sql"
done
echo "Done. Run sql/05_metrics.sql next."
