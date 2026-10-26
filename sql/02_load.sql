-- 02_load.sql
-- Loads the CSV files into the raw_* tables.
-- \copy is a psql command, not SQL, so run this file with psql from the repository root:
--     psql -d ota -v ON_ERROR_STOP=1 -f sql/02_load.sql
-- It will not run inside the DBeaver SQL editor. In DBeaver, right-click each raw_* table and use
-- "Import Data" instead (choose the CSV file, header row on).
-- Empty CSV fields load as NULL.

\copy raw_channels        FROM 'data/raw/channels.csv'        WITH (FORMAT csv, HEADER true)
\copy raw_payment_methods FROM 'data/raw/payment_methods.csv' WITH (FORMAT csv, HEADER true)
\copy raw_promos          FROM 'data/raw/promos.csv'          WITH (FORMAT csv, HEADER true)
\copy raw_products        FROM 'data/raw/products.csv'        WITH (FORMAT csv, HEADER true)
\copy raw_customers       FROM 'data/raw/customers.csv'       WITH (FORMAT csv, HEADER true)
\copy raw_bookings        FROM 'data/raw/bookings.csv'        WITH (FORMAT csv, HEADER true)
\copy raw_payments        FROM 'data/raw/payments.csv'        WITH (FORMAT csv, HEADER true)
\copy raw_refunds         FROM 'data/raw/refunds.csv'         WITH (FORMAT csv, HEADER true)
\copy raw_funnel_daily    FROM 'data/raw/funnel_daily.csv'    WITH (FORMAT csv, HEADER true)

SELECT 'raw_bookings' AS table_name, COUNT(*) AS row_count FROM raw_bookings
UNION ALL SELECT 'raw_payments',     COUNT(*) FROM raw_payments
UNION ALL SELECT 'raw_refunds',      COUNT(*) FROM raw_refunds
UNION ALL SELECT 'raw_customers',    COUNT(*) FROM raw_customers
UNION ALL SELECT 'raw_funnel_daily', COUNT(*) FROM raw_funnel_daily;
