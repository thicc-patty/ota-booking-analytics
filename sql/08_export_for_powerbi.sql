-- 08_export_for_powerbi.sql
-- Writes the four views to CSV files that Power BI can read with "Get data > Text/CSV".
-- Run with psql from the repository root (\copy is a psql command):
--     psql -d ota -v ON_ERROR_STOP=1 -f sql/08_export_for_powerbi.sql
-- The exported files are already included in data/powerbi/, so this is only needed if the data changes.

\copy (SELECT * FROM vw_bookings ORDER BY booking_id)                    TO 'data/powerbi/bookings.csv'  WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM vw_payments ORDER BY payment_id)                    TO 'data/powerbi/payments.csv'  WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM vw_refunds ORDER BY refund_id)                      TO 'data/powerbi/refunds.csv'   WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM vw_funnel ORDER BY month_start, channel_name, stage_order) TO 'data/powerbi/funnel.csv' WITH (FORMAT csv, HEADER true)
