-- 06_analysis_questions.sql
-- Eight questions a BI analyst gets asked, each answered with a query.
-- The comment above each query says what to look for. Try to predict the result before you run it.

-- ---------------------------------------------------------------------------
-- Q1. Why does joining bookings to payments inflate revenue?
--     fact_payments has one row per payment ATTEMPT. A booking with one failed attempt
--     and one success has two payment rows, so a plain join repeats the booking.
-- ---------------------------------------------------------------------------
SELECT
    (SELECT SUM(gross_amount) FROM fact_bookings WHERE status <> 'cancelled') AS gbv_correct,
    (SELECT SUM(b.gross_amount)
     FROM fact_bookings b
     JOIN fact_payments p ON p.booking_id = b.booking_id
     WHERE b.status <> 'cancelled')                                          AS gbv_after_unsafe_join,
    (SELECT SUM(b.gross_amount)
     FROM fact_bookings b
     JOIN fact_payments p ON p.booking_id = b.booking_id AND p.payment_status = 'success'
     WHERE b.status <> 'cancelled')                                          AS gbv_after_safe_join;
-- Fix: filter the many-side to one row per booking before you join, or aggregate it first.

-- ---------------------------------------------------------------------------
-- Q2. Which payment method fails most often?
--     Failure rate = failed attempts divided by all attempts.
-- ---------------------------------------------------------------------------
SELECT pm.method_name,
       COUNT(*)                                          AS attempts,
       COUNT(*) FILTER (WHERE p.payment_status = 'failed') AS failed,
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'failed') / COUNT(*), 1) AS failure_rate_pct
FROM fact_payments p
JOIN dim_payment_method pm ON pm.payment_method_id = p.payment_method_id
GROUP BY pm.method_name
ORDER BY failure_rate_pct DESC;

-- ---------------------------------------------------------------------------
-- Q3. How many days pass between a customer's first and second booking?
--     ROW_NUMBER numbers each customer's bookings in time order. LAG reads the previous row.
-- ---------------------------------------------------------------------------
WITH seq AS (
    SELECT customer_id,
           booking_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY booking_ts) AS booking_number,
           LAG(booking_date) OVER (PARTITION BY customer_id ORDER BY booking_ts) AS previous_booking_date
    FROM fact_bookings
    WHERE customer_id IS NOT NULL
      AND status <> 'cancelled'
)
SELECT COUNT(*)                                                         AS second_bookings,
       ROUND(AVG(booking_date - previous_booking_date), 1)              AS avg_days_between,
       MIN(booking_date - previous_booking_date)                        AS min_days,
       MAX(booking_date - previous_booking_date)                        AS max_days
FROM seq
WHERE booking_number = 2;

-- ---------------------------------------------------------------------------
-- Q4. Within each product type, which promo earns the most net revenue per booking?
--     RANK() restarts for every product type because of PARTITION BY.
-- ---------------------------------------------------------------------------
WITH promo_results AS (
    SELECT pr.product_type,
           COALESCE(p.promo_code, 'No promo')                     AS promo_code,
           COUNT(*)                                               AS bookings,
           ROUND(AVG(b.commission_amount - b.discount_amount), 0) AS net_revenue_per_booking
    FROM fact_bookings b
    JOIN dim_product pr ON pr.product_id = b.product_id
    LEFT JOIN dim_promo p ON p.promo_id = b.promo_id
    WHERE b.status <> 'cancelled'
    GROUP BY pr.product_type, COALESCE(p.promo_code, 'No promo')
)
SELECT product_type, promo_code, bookings, net_revenue_per_booking,
       RANK() OVER (PARTITION BY product_type ORDER BY net_revenue_per_booking DESC) AS rank_in_type
FROM promo_results
ORDER BY product_type, rank_in_type;

-- ---------------------------------------------------------------------------
-- Q5. Month-over-month change in GBV
-- ---------------------------------------------------------------------------
WITH monthly AS (
    SELECT d.month_start, SUM(b.gross_amount) AS gbv
    FROM fact_bookings b
    JOIN dim_date d ON d.date_key = b.booking_date
    WHERE b.status <> 'cancelled'
    GROUP BY d.month_start
)
SELECT month_start, gbv,
       LAG(gbv) OVER (ORDER BY month_start) AS previous_month_gbv,
       ROUND(100.0 * (gbv - LAG(gbv) OVER (ORDER BY month_start)) / LAG(gbv) OVER (ORDER BY month_start), 1) AS change_pct
FROM monthly
ORDER BY month_start;

-- ---------------------------------------------------------------------------
-- Q6. Does a promo booking earn less than a booking with no promo?
-- ---------------------------------------------------------------------------
SELECT CASE WHEN promo_id IS NULL THEN 'No promo' ELSE 'With promo' END AS booking_type,
       COUNT(*)                                                         AS bookings,
       ROUND(AVG(gross_amount), 0)                                      AS avg_gross,
       ROUND(AVG(commission_amount), 0)                                 AS avg_commission,
       ROUND(AVG(discount_amount), 0)                                   AS avg_discount,
       ROUND(AVG(commission_amount - discount_amount), 0)               AS avg_net_revenue
FROM fact_bookings
WHERE status <> 'cancelled'
GROUP BY CASE WHEN promo_id IS NULL THEN 'No promo' ELSE 'With promo' END;

-- ---------------------------------------------------------------------------
-- Q7. How many refunds are still pending, and for how long? (snapshot date: 2026-10-01)
-- ---------------------------------------------------------------------------
SELECT CASE WHEN TIMESTAMP '2026-10-01' - requested_ts > INTERVAL '14 days' THEN 'older than 14 days'
            WHEN TIMESTAMP '2026-10-01' - requested_ts > INTERVAL '7 days'  THEN '8 to 14 days'
            ELSE '7 days or less' END AS pending_age,
       COUNT(*)                       AS pending_refunds,
       SUM(refund_amount)             AS amount_owed
FROM fact_refunds
WHERE completed_ts IS NULL
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- Q8. Which routes and cities bring in the most GBV?
-- ---------------------------------------------------------------------------
SELECT pr.product_type,
       COALESCE(pr.origin || ' to ', '') || pr.destination AS route_or_city,
       COUNT(*)                                            AS bookings,
       SUM(b.gross_amount)                                 AS gbv
FROM fact_bookings b
JOIN dim_product pr ON pr.product_id = b.product_id
WHERE b.status <> 'cancelled'
GROUP BY pr.product_type, COALESCE(pr.origin || ' to ', '') || pr.destination
ORDER BY gbv DESC
LIMIT 10;
