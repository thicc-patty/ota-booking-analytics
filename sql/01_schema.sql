-- 01_schema.sql
-- Creates two groups of tables.
--   raw_*  : the files exactly as delivered. No keys, no checks, so messy rows can load.
--   dim_*, fact_* : the clean analytics tables, with primary keys, foreign keys and checks.
--
-- Grain (what one row means) is written next to every fact table.
-- Run with psql from the repository root:  psql -d ota -v ON_ERROR_STOP=1 -f sql/01_schema.sql

DROP TABLE IF EXISTS
    fact_funnel_daily, fact_refunds, fact_payments, fact_bookings,
    dim_date, dim_product, dim_promo, dim_payment_method, dim_channel, dim_customer,
    raw_funnel_daily, raw_refunds, raw_payments, raw_bookings, raw_customers,
    raw_products, raw_promos, raw_payment_methods, raw_channels
CASCADE;

-- ---------------------------------------------------------------- raw layer
CREATE TABLE raw_channels        (channel_id int, channel_name text, channel_type text);
CREATE TABLE raw_payment_methods (payment_method_id int, method_name text, method_type text);
CREATE TABLE raw_promos          (promo_id int, promo_code text, discount_type text, discount_value int,
                                  max_discount int, start_date date, end_date date);
CREATE TABLE raw_products        (product_id int, product_type text, origin text, destination text);
CREATE TABLE raw_customers       (customer_id int, signup_date date, city text, acquisition_channel_id int);
CREATE TABLE raw_bookings        (booking_id text, customer_id int, product_id int, channel_id int,
                                  promo_code text, booking_ts timestamp, travel_date date, status text,
                                  gross_amount int, discount_amount int, commission_amount int);
CREATE TABLE raw_payments        (payment_id text, booking_id text, payment_method_id int, amount int,
                                  payment_ts timestamp, payment_status text);
CREATE TABLE raw_refunds         (refund_id text, booking_id text, refund_amount int,
                                  requested_ts timestamp, completed_ts timestamp);
CREATE TABLE raw_funnel_daily    (session_date date, channel_id int, furthest_stage text, sessions int);

-- ---------------------------------------------------------- analytics layer
-- Dimensions: one row per thing being described.
CREATE TABLE dim_channel (
    channel_id   int  PRIMARY KEY,
    channel_name text NOT NULL,
    channel_type text NOT NULL
);

CREATE TABLE dim_payment_method (
    payment_method_id int  PRIMARY KEY,
    method_name       text NOT NULL,
    method_type       text NOT NULL
);

CREATE TABLE dim_promo (
    promo_id       int  PRIMARY KEY,
    promo_code     text NOT NULL UNIQUE,
    discount_type  text NOT NULL,
    discount_value int  NOT NULL,
    max_discount   int  NOT NULL,
    start_date     date NOT NULL,
    end_date       date NOT NULL
);

CREATE TABLE dim_product (
    product_id   int  PRIMARY KEY,
    product_type text NOT NULL,
    origin       text,
    destination  text NOT NULL
);

CREATE TABLE dim_customer (
    customer_id            int  PRIMARY KEY,
    signup_date            date NOT NULL,
    city                   text,
    acquisition_channel_id int  NOT NULL REFERENCES dim_channel (channel_id)
);

CREATE TABLE dim_date (
    date_key    date PRIMARY KEY,
    year        int  NOT NULL,
    month       int  NOT NULL,
    month_start date NOT NULL,
    week_start  date NOT NULL,
    day_name    text NOT NULL
);

-- Facts: one row per event.
-- Grain: ONE ROW PER BOOKING.
CREATE TABLE fact_bookings (
    booking_id        text PRIMARY KEY,
    customer_id       int  REFERENCES dim_customer (customer_id),   -- NULL = guest checkout
    product_id        int  NOT NULL REFERENCES dim_product (product_id),
    channel_id        int  NOT NULL REFERENCES dim_channel (channel_id),
    promo_id          int  REFERENCES dim_promo (promo_id),         -- NULL = no promo
    booking_ts        timestamp NOT NULL,
    booking_date      date NOT NULL REFERENCES dim_date (date_key),
    travel_date       date NOT NULL,
    status            text NOT NULL CHECK (status IN ('confirmed', 'completed', 'cancelled')),
    gross_amount      int  NOT NULL CHECK (gross_amount > 0),       -- list price, BDT
    discount_amount   int  NOT NULL CHECK (discount_amount >= 0),   -- promo cost paid by the company
    commission_amount int  NOT NULL                                  -- commission earned from the supplier
);

-- Grain: ONE ROW PER PAYMENT ATTEMPT. A booking can have failed attempts and one success.
CREATE TABLE fact_payments (
    payment_id        text PRIMARY KEY,
    booking_id        text NOT NULL REFERENCES fact_bookings (booking_id),
    payment_method_id int  NOT NULL REFERENCES dim_payment_method (payment_method_id),
    amount            int  NOT NULL,
    payment_ts        timestamp NOT NULL,
    payment_status    text NOT NULL CHECK (payment_status IN ('success', 'failed'))
);

-- Grain: ONE ROW PER REFUND REQUEST.
CREATE TABLE fact_refunds (
    refund_id          text PRIMARY KEY,
    booking_id         text NOT NULL REFERENCES fact_bookings (booking_id),
    refund_amount      int  NOT NULL,
    requested_ts       timestamp NOT NULL,
    completed_ts       timestamp,                 -- NULL = still pending
    is_timestamp_valid boolean NOT NULL           -- FALSE when completed_ts is before requested_ts
);

-- Grain: ONE ROW PER DAY, CHANNEL AND FURTHEST STAGE REACHED (a count of sessions, not single sessions).
CREATE TABLE fact_funnel_daily (
    session_date   date NOT NULL REFERENCES dim_date (date_key),
    channel_id     int  NOT NULL REFERENCES dim_channel (channel_id),
    furthest_stage text NOT NULL CHECK (furthest_stage IN ('search', 'select', 'checkout', 'payment', 'booked')),
    sessions       int  NOT NULL,
    PRIMARY KEY (session_date, channel_id, furthest_stage)
);
