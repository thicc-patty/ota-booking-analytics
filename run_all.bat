@echo off
rem Windows launcher. Rebuilds a database called ota on your local PostgreSQL and runs steps 1 to 4 and 7.
rem Before you run it: close any DBeaver connection to the ota database (it blocks the rebuild).
rem Double-click this file, or run it from Command Prompt inside the project folder.
setlocal
set "PSQL="
for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%D\bin\psql.exe" set "PSQL=%%D\bin\psql.exe"
if not defined PSQL (
  echo Could not find psql.exe under C:\Program Files\PostgreSQL.
  echo Open this file in Notepad, set PSQL to the full path of psql.exe, and run it again.
  pause
  exit /b 1
)
cd /d "%~dp0"
set /p PGPASSWORD=Type your PostgreSQL password and press Enter: 
set PGUSER=postgres
set PGHOST=localhost
"%PSQL%" -d postgres -c "DROP DATABASE IF EXISTS ota;"
if errorlevel 1 goto fail
"%PSQL%" -d postgres -c "CREATE DATABASE ota;"
if errorlevel 1 goto fail
for %%F in (01_schema 02_load 03_clean 04_data_quality_checks 07_views_for_powerbi) do (
  echo Running %%F ...
  "%PSQL%" -d ota -v ON_ERROR_STOP=1 -q -f "sql\%%F.sql"
  if errorlevel 1 goto fail
)
echo.
echo Done. Open DBeaver, connect to the database named ota, and run sql\05_metrics.sql.
pause
exit /b 0
:fail
echo.
echo Something failed. Read the error text above, then see docs\SETUP_WINDOWS.md.
pause
exit /b 1
