-- 05_metrics.sql
-- The eight metrics, one query each. Definitions are in docs/metric_definitions.md.
-- Run the whole file, or highlight one query at a time in DBeaver and press Ctrl+Enter.
-- All amounts are BDT. All data is synthetic.

-- ---------------------------------------------------------------------------
-- 1. Gross booking value (GBV) by month
--    GBV = sum of gross_amount for bookings that are not cancelled.
-- ---------------------------------------------------------------------------
SELECT d.month_start,
       COUNT(*)            AS bookings,
       SUM(b.gross_amount) AS gbv
FROM fact_bookings b
JOIN dim_date d ON d.date_key = b.booking_date
WHERE b.status <> 'cancelled'
GROUP BY d.month_start
ORDER BY d.month_start;

-- ---------------------------------------------------------------------------
-- 2. Net revenue by product type
--    Net revenue = commission_amount minus discount_amount, for bookings that are not cancelled.
--    Negative net revenue means the promo cost more than the commission earned.
-- ---------------------------------------------------------------------------
SELECT pr.product_type,
       COUNT(*)                                          AS bookings,
       SUM(b.commission_amount)                          AS commission,
       SUM(b.discount_amount)                            AS discount_cost,
       SUM(b.commission_amount - b.discount_amount)      AS net_revenue,
       ROUND(AVG(b.commission_amount - b.discount_amount), 0) AS net_revenue_per_booking
FROM fact_bookings b
JOIN dim_product pr ON pr.product_id = b.product_id
WHERE b.status <> 'cancelled'
GROUP BY pr.product_type
ORDER BY net_revenue DESC;

-- ---------------------------------------------------------------------------
-- 3. Booking conversion by funnel stage
--    A session that reached 'checkout' also reached 'search' and 'select',
--    so "sessions reaching a stage" adds up every session whose furthest stage is that stage or later.
-- ---------------------------------------------------------------------------
WITH stage_order AS (
    SELECT * FROM (VALUES ('search', 1), ('select', 2), ('checkout', 3), ('payment', 4), ('booked', 5))
           AS s (stage, ord)
),
reached AS (
    SELECT so.stage, so.ord, SUM(f.sessions) AS sessions_reaching
    FROM stage_order so
    JOIN stage_order later ON later.ord >= so.ord
    JOIN fact_funnel_daily f ON f.furthest_stage = later.stage
    GROUP BY so.stage, so.ord
)
SELECT stage,
       sessions_reaching,
       ROUND(100.0 * sessions_reaching / FIRST_VALUE(sessions_reaching) OVER (ORDER BY ord), 2) AS pct_of_all_sessions,
       ROUND(100.0 * sessions_reaching / LAG(sessions_reaching) OVER (ORDER BY ord), 1)         AS pct_of_previous_stage
FROM reached
ORDER BY ord;

-- 3b. Overall conversion (search to booked) by channel
SELECT ch.channel_name,
       SUM(f.sessions)                                              AS sessions,
       SUM(f.sessions) FILTER (WHERE f.furthest_stage = 'booked')   AS booked_sessions,
       ROUND(100.0 * SUM(f.sessions) FILTER (WHERE f.furthest_stage = 'booked') / SUM(f.sessions), 2) AS conversion_pct
FROM fact_funnel_daily f
JOIN dim_channel ch ON ch.channel_id = f.channel_id
GROUP BY ch.channel_name
ORDER BY conversion_pct DESC;

-- ---------------------------------------------------------------------------
-- 4. Cancellation rate = cancelled bookings divided by all bookings
-- ---------------------------------------------------------------------------
-- 4a. by product type
SELECT pr.product_type,
       COUNT(*)                                          AS bookings,
       COUNT(*) FILTER (WHERE b.status = 'cancelled')    AS cancelled,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.status = 'cancelled') / COUNT(*), 1) AS cancellation_rate_pct
FROM fact_bookings b
JOIN dim_product pr ON pr.product_id = b.product_id
GROUP BY pr.product_type
ORDER BY cancellation_rate_pct DESC;

-- 4b. by promo code (look at the highest rate, then ask why)
SELECT COALESCE(p.promo_code, 'No promo')                AS promo_code,
       COUNT(*)                                          AS bookings,
       COUNT(*) FILTER (WHERE b.status = 'cancelled')    AS cancelled,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.status = 'cancelled') / COUNT(*), 1) AS cancellation_rate_pct
FROM fact_bookings b
LEFT JOIN dim_promo p ON p.promo_id = b.promo_id
GROUP BY COALESCE(p.promo_code, 'No promo')
ORDER BY cancellation_rate_pct DESC;

-- ---------------------------------------------------------------------------
-- 5. Refund time in days, by the payment method used for the booking
--    Only completed refunds with a valid timestamp. Pending refunds are left out,
--    so these averages describe finished refunds only.
-- ---------------------------------------------------------------------------
SELECT pm.method_name,
       COUNT(*) AS completed_refunds,
       ROUND(AVG(EXTRACT(EPOCH FROM (r.completed_ts - r.requested_ts)) / 86400)::numeric, 1) AS avg_days,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP
              (ORDER BY EXTRACT(EPOCH FROM (r.completed_ts - r.requested_ts)) / 86400))::numeric, 1) AS median_days
FROM fact_refunds r
JOIN fact_payments p ON p.booking_id = r.booking_id AND p.payment_status = 'success'
JOIN dim_payment_method pm ON pm.payment_method_id = p.payment_method_id
WHERE r.completed_ts IS NOT NULL
  AND r.is_timestamp_valid
GROUP BY pm.method_name
ORDER BY avg_days DESC;

-- ---------------------------------------------------------------------------
-- 6. Repeat booking rate by the channel that first acquired the customer
--    Customers with at least 2 non-cancelled bookings, divided by customers with at least 1.
--    Guest bookings (no customer_id) drop out at the join.
--    Caution: customers who signed up recently have had less time to book again.
-- ---------------------------------------------------------------------------
WITH per_customer AS (
    SELECT c.customer_id, c.acquisition_channel_id, COUNT(*) AS bookings
    FROM fact_bookings b
    JOIN dim_customer c ON c.customer_id = b.customer_id
    WHERE b.status <> 'cancelled'
    GROUP BY c.customer_id, c.acquisition_channel_id
)
SELECT ch.channel_name                                      AS acquisition_channel,
       COUNT(*)                                             AS customers_with_a_booking,
       COUNT(*) FILTER (WHERE pc.bookings >= 2)             AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE pc.bookings >= 2) / COUNT(*), 1) AS repeat_rate_pct
FROM per_customer pc
JOIN dim_channel ch ON ch.channel_id = pc.acquisition_channel_id
GROUP BY ch.channel_name
ORDER BY repeat_rate_pct DESC;

-- ---------------------------------------------------------------------------
-- 7. Revenue by booking channel, with each channel's share of GBV
-- ---------------------------------------------------------------------------
SELECT ch.channel_name,
       COUNT(*)                                        AS bookings,
       SUM(b.gross_amount)                             AS gbv,
       ROUND(100.0 * SUM(b.gross_amount) / SUM(SUM(b.gross_amount)) OVER (), 1) AS gbv_share_pct,
       SUM(b.commission_amount - b.discount_amount)    AS net_revenue
FROM fact_bookings b
JOIN dim_channel ch ON ch.channel_id = b.channel_id
WHERE b.status <> 'cancelled'
GROUP BY ch.channel_name
ORDER BY gbv DESC;

-- ---------------------------------------------------------------------------
-- 8. Discount cost by promo code and payment method
--    Joins to the SUCCESSFUL payment only. Joining to every attempt would count
--    some bookings twice (see sql/06_analysis_questions.sql, question 1).
-- ---------------------------------------------------------------------------
SELECT COALESCE(pro.promo_code, 'No promo')            AS promo_code,
       pm.method_name                                  AS payment_method,
       COUNT(*)                                        AS bookings,
       SUM(b.discount_amount)                          AS discount_cost,
       SUM(b.commission_amount)                        AS commission,
       SUM(b.commission_amount - b.discount_amount)    AS net_revenue,
       ROUND(100.0 * SUM(b.discount_amount) / NULLIF(SUM(b.commission_amount), 0), 0) AS discount_pct_of_commission
FROM fact_bookings b
JOIN fact_payments p ON p.booking_id = b.booking_id AND p.payment_status = 'success'
JOIN dim_payment_method pm ON pm.payment_method_id = p.payment_method_id
LEFT JOIN dim_promo pro ON pro.promo_id = b.promo_id
WHERE b.status <> 'cancelled'
  AND b.promo_id IS NOT NULL
GROUP BY COALESCE(pro.promo_code, 'No promo'), pm.method_name
ORDER BY discount_cost DESC;
