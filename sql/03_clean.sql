-- 03_clean.sql
-- Turns the messy raw_* tables into the clean dim_* and fact_* tables.
-- Every cleaning rule is documented in a comment next to the code that applies it.
--     psql -d ota -v ON_ERROR_STOP=1 -f sql/03_clean.sql

-- Dimensions: copied across. The raw lookup files were already clean.
INSERT INTO dim_channel        SELECT channel_id, channel_name, channel_type FROM raw_channels;
INSERT INTO dim_payment_method SELECT payment_method_id, method_name, method_type FROM raw_payment_methods;
INSERT INTO dim_promo          SELECT promo_id, promo_code, discount_type, discount_value, max_discount,
                                      start_date, end_date FROM raw_promos;
INSERT INTO dim_product        SELECT product_id, product_type, NULLIF(origin, ''), destination FROM raw_products;
INSERT INTO dim_customer       SELECT customer_id, signup_date, city, acquisition_channel_id FROM raw_customers;

-- A calendar table: one row per day.
INSERT INTO dim_date
SELECT d::date,
       EXTRACT(YEAR FROM d)::int,
       EXTRACT(MONTH FROM d)::int,
       DATE_TRUNC('month', d)::date,
       DATE_TRUNC('week', d)::date,
       TO_CHAR(d, 'Dy')
FROM GENERATE_SERIES(DATE '2025-06-01', DATE '2026-12-31', INTERVAL '1 day') AS g(d);

-- Bookings. Rules:
--   1. Drop internal test rows (gross_amount of 0 or less).
--   2. Keep one row per booking_id (the raw file has exact duplicate rows).
--   3. Make status lower case and trim spaces ('Completed', 'COMPLETED ' become 'completed').
--   4. Turn the free-text promo_code ('', 'NONE', ' welcome10') into a promo_id, or NULL for no promo.
INSERT INTO fact_bookings
    (booking_id, customer_id, product_id, channel_id, promo_id, booking_ts, booking_date,
     travel_date, status, gross_amount, discount_amount, commission_amount)
WITH ranked AS (
    SELECT b.*,
           ROW_NUMBER() OVER (PARTITION BY b.booking_id ORDER BY b.booking_ts) AS rn
    FROM raw_bookings b
    WHERE b.gross_amount > 0
)
SELECT r.booking_id, r.customer_id, r.product_id, r.channel_id, p.promo_id,
       r.booking_ts, r.booking_ts::date, r.travel_date,
       LOWER(TRIM(r.status)),
       r.gross_amount, r.discount_amount, r.commission_amount
FROM ranked r
LEFT JOIN dim_promo p
       ON p.promo_code = NULLIF(NULLIF(UPPER(TRIM(r.promo_code)), ''), 'NONE')
WHERE r.rn = 1;

-- Payments: keep only attempts that belong to a kept booking.
INSERT INTO fact_payments
SELECT payment_id, booking_id, payment_method_id, amount, payment_ts, LOWER(TRIM(payment_status))
FROM raw_payments
WHERE booking_id IN (SELECT booking_id FROM fact_bookings);

-- Refunds: keep them all, but flag rows where the refund finished before it was requested.
INSERT INTO fact_refunds
SELECT refund_id, booking_id, refund_amount, requested_ts, completed_ts,
       (completed_ts IS NULL OR completed_ts >= requested_ts)
FROM raw_refunds
WHERE booking_id IN (SELECT booking_id FROM fact_bookings);

INSERT INTO fact_funnel_daily
SELECT session_date, channel_id, furthest_stage, sessions FROM raw_funnel_daily;

SELECT 'fact_bookings' AS table_name, COUNT(*) AS row_count FROM fact_bookings
UNION ALL SELECT 'fact_payments',     COUNT(*) FROM fact_payments
UNION ALL SELECT 'fact_refunds',      COUNT(*) FROM fact_refunds
UNION ALL SELECT 'fact_funnel_daily', COUNT(*) FROM fact_funnel_daily;
