-- 04_data_quality_checks.sql
-- Two sets of checks. Run the first set after 02_load.sql and the second after 03_clean.sql.
-- "expected" is what a healthy table should show.

-- ===================================================== A. Problems in the raw files
SELECT check_name, rows_found, note FROM (
    SELECT 1 AS ord, 'raw: duplicate booking rows' AS check_name,
           COUNT(*) - COUNT(DISTINCT booking_id) AS rows_found,
           'same booking_id loaded more than once' AS note
    FROM raw_bookings
    UNION ALL
    SELECT 2, 'raw: spellings of status',
           COUNT(DISTINCT status), 'a clean table has 3 (confirmed, completed, cancelled)'
    FROM raw_bookings
    UNION ALL
    SELECT 3, 'raw: test rows with amount 0 or less',
           COUNT(*) FILTER (WHERE gross_amount <= 0), 'internal test bookings, not real sales'
    FROM raw_bookings
    UNION ALL
    SELECT 4, 'raw: spellings of promo_code',
           COUNT(DISTINCT promo_code), 'clean data has 4 codes plus "no promo"'
    FROM raw_bookings
    UNION ALL
    SELECT 5, 'raw: bookings with no customer_id',
           COUNT(DISTINCT booking_id) FILTER (WHERE customer_id IS NULL AND gross_amount > 0),
           'guest checkout: not an error, but excluded from repeat-customer metrics'
    FROM raw_bookings
    UNION ALL
    SELECT 6, 'raw: refunds finished before they were requested',
           COUNT(*) FILTER (WHERE completed_ts < requested_ts), 'impossible, so the timestamp is wrong'
    FROM raw_refunds
) t
ORDER BY ord;

-- ============================================ B. Checks on the clean analytics tables
SELECT check_name, rows_found, expected FROM (
    SELECT 1 AS ord, 'duplicate booking_id' AS check_name,
           COUNT(*) - COUNT(DISTINCT booking_id) AS rows_found, '0' AS expected
    FROM fact_bookings
    UNION ALL
    SELECT 2, 'raw promo text that did not match a promo_id',
           COUNT(*), '0'
    FROM raw_bookings r
    WHERE r.gross_amount > 0
      AND NULLIF(NULLIF(UPPER(TRIM(r.promo_code)), ''), 'NONE') IS NOT NULL
      AND NULLIF(NULLIF(UPPER(TRIM(r.promo_code)), ''), 'NONE') NOT IN (SELECT promo_code FROM dim_promo)
    UNION ALL
    SELECT 3, 'bookings without exactly one successful payment',
           COUNT(*), '0'
    FROM (
        SELECT b.booking_id
        FROM fact_bookings b
        LEFT JOIN fact_payments p ON p.booking_id = b.booking_id AND p.payment_status = 'success'
        GROUP BY b.booking_id
        HAVING COUNT(p.payment_id) <> 1
    ) x
    UNION ALL
    SELECT 4, 'bookings where gross minus discount is not the amount paid',
           COUNT(*), '0'
    FROM fact_bookings b
    JOIN fact_payments p ON p.booking_id = b.booking_id AND p.payment_status = 'success'
    WHERE b.gross_amount - b.discount_amount <> p.amount
    UNION ALL
    SELECT 5, 'refunds larger than the amount paid',
           COUNT(*), '0'
    FROM fact_refunds r
    JOIN fact_payments p ON p.booking_id = r.booking_id AND p.payment_status = 'success'
    WHERE r.refund_amount > p.amount
    UNION ALL
    SELECT 6, 'refunds on bookings that are not cancelled',
           COUNT(*), '0'
    FROM fact_refunds r
    JOIN fact_bookings b ON b.booking_id = r.booking_id
    WHERE b.status <> 'cancelled'
    UNION ALL
    SELECT 7, 'cancelled bookings with no refund record',
           COUNT(*), 'not 0: a reconciliation gap to raise with the finance team'
    FROM fact_bookings b
    WHERE b.status = 'cancelled'
      AND NOT EXISTS (SELECT 1 FROM fact_refunds r WHERE r.booking_id = b.booking_id)
    UNION ALL
    SELECT 8, 'refunds flagged with a bad timestamp',
           COUNT(*) FILTER (WHERE NOT is_timestamp_valid), 'a few: excluded from refund-time metrics'
    FROM fact_refunds
    UNION ALL
    SELECT 9, 'discount larger than commission (promo loses money)',
           COUNT(*), 'informational: a business finding, not a data error'
    FROM fact_bookings
    WHERE discount_amount > commission_amount
) t
ORDER BY ord;
