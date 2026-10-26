# Setup on Windows

## What you need

| Tool | Used for | Cost |
| --- | --- | --- |
| PostgreSQL 16 | the database that stores the tables and runs the SQL | free |
| DBeaver Community | a window to browse tables and run queries | free |
| Power BI Desktop | the dashboard (Windows only) | free to build reports. Sharing reports online needs a paid licence, which this project does not need |
| Python 3 (optional) | only to regenerate the raw data or the charts | free |

## Steps

1. **Install PostgreSQL** from postgresql.org (Download, then Windows). Keep the defaults. When the installer asks for a password for the `postgres` user, choose one and keep it private. Keep port 5432 and keep "Command Line Tools" ticked. Screen names can differ between versions.
2. **Put the project in a simple folder**, for example `C:\ota-booking-analytics`. Avoid OneDrive folders.
3. **Run `run_all.bat`.** Double-click it, type the PostgreSQL password when asked and wait for the word Done. It creates a database called `ota`, then loads and cleans the data and runs the data-quality checks. If it stops with an error, read the message above the prompt. A common cause is an open DBeaver connection to `ota` (see below).
4. **Install DBeaver Community** from dbeaver.io. Choose New Database Connection, then PostgreSQL. Use host `localhost`, port `5432`, database `ota`, user `postgres` and the password. If it offers to download a driver, accept. Press Test Connection, then Finish.
5. **Run the queries.** In DBeaver use File, then Open File, and open `sql\05_metrics.sql`. Click inside one query and press Ctrl+Enter to run just that query. Alt+X runs the whole file.
6. **Build the dashboard.** Install Power BI Desktop from the Microsoft Store and follow [dashboard_spec.md](dashboard_spec.md).

## Re-running `run_all.bat`

Close the DBeaver connection to `ota` first. PostgreSQL will not drop a database that is open somewhere else.

## If `run_all.bat` does not work

The same result can be reached by hand. In DBeaver, run `sql\01_schema.sql`, load each CSV in `data\raw` into the matching `raw_` table with DBeaver's Import Data, then run `03_clean.sql`, `04_data_quality_checks.sql` and `07_views_for_powerbi.sql`.

## What was tested

The SQL scripts and `run_all.sh` were run in order on PostgreSQL 16 on Linux, from an empty database to the final queries. `run_all.bat` follows the same steps but has not been run on Windows yet.
