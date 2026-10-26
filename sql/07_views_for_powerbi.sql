-- 07_views_for_powerbi.sql
-- Four flat views, one per dashboard page. A flat view joins the star schema back together so
-- Power BI can use one table per page without building relationships.
--     psql -d ota -v ON_ERROR_STOP=1 -f sql/07_views_for_powerbi.sql

-- One row per booking, with the names filled in.
CREATE OR REPLACE VIEW vw_bookings AS
SELECT b.booking_id,
       b.booking_date,
       d.month_start,
       b.travel_date,
       b.status,
       pr.product_type,
       COALESCE(pr.origin || ' to ', '') || pr.destination AS route_or_city,
       ch.channel_name,
       COALESCE(pm.method_name, 'Unknown')                 AS payment_method,
       COALESCE(pro.promo_code, 'No promo')                AS promo_code,
       b.customer_id,
       b.gross_amount,
       b.discount_amount,
       b.commission_amount,
       b.commission_amount - b.discount_amount             AS net_revenue
FROM fact_bookings b
JOIN dim_date d     ON d.date_key = b.booking_date
JOIN dim_product pr ON pr.product_id = b.product_id
JOIN dim_channel ch ON ch.channel_id = b.channel_id
LEFT JOIN dim_promo pro ON pro.promo_id = b.promo_id
LEFT JOIN fact_payments sp ON sp.booking_id = b.booking_id AND sp.payment_status = 'success'
LEFT JOIN dim_payment_method pm ON pm.payment_method_id = sp.payment_method_id;

-- One row per payment attempt.
CREATE OR REPLACE VIEW vw_payments AS
SELECT p.payment_id,
       p.booking_id,
       p.payment_ts::date                      AS payment_date,
       DATE_TRUNC('month', p.payment_ts)::date AS month_start,
       pm.method_name                          AS payment_method,
       p.payment_status,
       p.amount
FROM fact_payments p
JOIN dim_payment_method pm ON pm.payment_method_id = p.payment_method_id;

-- One row per refund request. days_to_complete is empty while the refund is pending.
CREATE OR REPLACE VIEW vw_refunds AS
SELECT r.refund_id,
       r.booking_id,
       r.requested_ts::date                      AS requested_date,
       DATE_TRUNC('month', r.requested_ts)::date AS month_start,
       pm.method_name                            AS payment_method,
       r.refund_amount,
       CASE WHEN r.completed_ts IS NULL THEN 'Yes' ELSE 'No' END AS is_pending,
       CASE WHEN r.is_timestamp_valid THEN 'Yes' ELSE 'No' END   AS is_timestamp_valid,
       CASE WHEN r.completed_ts IS NOT NULL AND r.is_timestamp_valid
            THEN ROUND((EXTRACT(EPOCH FROM (r.completed_ts - r.requested_ts)) / 86400)::numeric, 2)
       END                                       AS days_to_complete
FROM fact_refunds r
JOIN fact_payments p ON p.booking_id = r.booking_id AND p.payment_status = 'success'
JOIN dim_payment_method pm ON pm.payment_method_id = p.payment_method_id;

-- Funnel: for each month, channel and stage, how many sessions reached that stage or went further.
CREATE OR REPLACE VIEW vw_funnel AS
WITH stage_order AS (
    SELECT * FROM (VALUES ('search', 1), ('select', 2), ('checkout', 3), ('payment', 4), ('booked', 5))
           AS s (stage, stage_order)
)
SELECT DATE_TRUNC('month', f.session_date)::date AS month_start,
       ch.channel_name,
       so.stage,
       so.stage_order,
       SUM(f.sessions)                           AS sessions_reaching_stage
FROM stage_order so
JOIN stage_order later ON later.stage_order >= so.stage_order
JOIN fact_funnel_daily f ON f.furthest_stage = later.stage
JOIN dim_channel ch ON ch.channel_id = f.channel_id
GROUP BY DATE_TRUNC('month', f.session_date)::date, ch.channel_name, so.stage, so.stage_order;
