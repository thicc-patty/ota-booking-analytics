#!/usr/bin/env python3
"""Generate the synthetic travel-booking dataset used in this project.

Everything produced here is invented. No real company, customer or payment
data is used. The script uses only the Python standard library and is seeded,
so the same seed always produces the same files.

Usage (from the repository root):
    python generator/generate_data.py --out data/raw --seed 42

The raw files are messy on purpose (duplicates, mixed-case statuses, free-text
promo codes, test rows, bad refund timestamps). The SQL in /sql cleans them.
"""
import argparse
import bisect
import csv
import os
import random
from datetime import date, datetime, timedelta

WINDOW_START = date(2026, 1, 1)
WINDOW_END = date(2026, 9, 30)
SNAPSHOT = datetime(2026, 10, 1, 0, 0, 0)  # the dataset's "today"

CHANNELS = [
    (1, "Mobile app", "owned"),
    (2, "Website", "owned"),
    (3, "Call center", "assisted"),
    (4, "Agent partner", "partner"),
    (5, "Facebook ads", "paid"),
    (6, "Google ads", "paid"),
]
# who a brand-new customer is acquired through
ACQUISITION_WEIGHTS = {1: 20, 2: 22, 3: 3, 4: 8, 5: 30, 6: 17}
# channel used by a returning customer
REPEAT_CHANNEL_WEIGHTS = {1: 46, 2: 40, 3: 4, 4: 10}
# share of sessions that end in a booking, by channel
CONVERSION = {1: 0.032, 2: 0.024, 3: 0.12, 4: 0.08, 5: 0.013, 6: 0.018}

PAYMENT_METHODS = [
    (1, "bKash", "mobile wallet"),
    (2, "Nagad", "mobile wallet"),
    (3, "Visa card", "card"),
    (4, "Mastercard", "card"),
    (5, "Internet banking", "bank"),
]
METHOD_WEIGHTS = {1: 38, 2: 14, 3: 22, 4: 12, 5: 14}
FAIL_PROB = {1: 0.04, 2: 0.06, 3: 0.05, 4: 0.05, 5: 0.13}
# refund processing time in days (low, high) by the method that paid
REFUND_DAYS = {1: (0.5, 3), 2: (0.5, 3), 3: (4, 10), 4: (4, 10), 5: (7, 16)}

# id, code, type, value, max discount, start, end
PROMOS = [
    (1, "WELCOME10", "percent", 10, 500, "2026-01-01", "2026-09-30"),
    (2, "EID15", "percent", 15, 1500, "2026-03-10", "2026-03-31"),
    (3, "SUMMER500", "flat", 500, 500, "2026-06-01", "2026-07-31"),
    (4, "BKASH5", "percent", 5, 300, "2026-01-01", "2026-09-30"),
]

# id, type, origin, destination, typical price in BDT
PRODUCTS = [
    (1, "domestic_flight", "DAC", "CXB", 6200),
    (2, "domestic_flight", "DAC", "CGP", 4800),
    (3, "domestic_flight", "DAC", "ZYL", 5200),
    (4, "domestic_flight", "DAC", "JSR", 5000),
    (5, "domestic_flight", "DAC", "RJH", 5400),
    (6, "domestic_flight", "CGP", "DAC", 4900),
    (7, "international_flight", "DAC", "DXB", 38000),
    (8, "international_flight", "DAC", "KUL", 32000),
    (9, "international_flight", "DAC", "BKK", 27000),
    (10, "international_flight", "DAC", "DEL", 18000),
    (11, "international_flight", "DAC", "SIN", 36000),
    (12, "international_flight", "DAC", "JED", 52000),
    (13, "hotel", "", "Cox's Bazar", 7500),
    (14, "hotel", "", "Sylhet", 5200),
    (15, "hotel", "", "Dhaka", 6800),
    (16, "hotel", "", "Bandarban", 4600),
    (17, "hotel", "", "Chattogram", 5600),
    (18, "bus", "Dhaka", "Chattogram", 1300),
    (19, "bus", "Dhaka", "Sylhet", 1500),
    (20, "bus", "Dhaka", "Cox's Bazar", 1900),
]
TYPE_WEIGHTS = {"domestic_flight": 40, "international_flight": 20, "hotel": 28, "bus": 12}
COMMISSION = {"domestic_flight": 0.04, "international_flight": 0.05, "hotel": 0.15, "bus": 0.08}
CANCEL_PROB = {"domestic_flight": 0.07, "international_flight": 0.10, "hotel": 0.12, "bus": 0.05}
REFUND_SHARE = {"domestic_flight": 0.90, "international_flight": 0.85, "hotel": 0.90, "bus": 1.00}
LEAD_DAYS = {"domestic_flight": (3, 45), "international_flight": (10, 90), "hotel": (5, 60), "bus": (1, 14)}

CITIES = [("Dhaka", 55), ("Chattogram", 15), ("Sylhet", 8), ("Rajshahi", 5), ("Khulna", 5), ("Other", 12)]
HOUR_WEIGHTS = [1, 1, 1, 1, 1, 2, 3, 5, 7, 9, 10, 10, 9, 8, 8, 8, 8, 9, 10, 11, 11, 10, 6, 3]


def wchoice(rng, weights):
    """Pick a key from {key: weight}."""
    keys = list(weights)
    return rng.choices(keys, weights=[weights[k] for k in keys], k=1)[0]


def daily_weights(days):
    out = []
    for d in days:
        w = 1.0
        if d.month == 1:
            w = 0.9
        if date(2026, 3, 10) <= d <= date(2026, 3, 31):
            w = 2.0
        if d.month in (6, 7):
            w = 1.35
        if d.month == 8:
            w = 1.1
        if d.weekday() in (3, 4):  # Thursday, Friday
            w *= 1.15
        out.append(w)
    return out


def make_customers(rng, n):
    start = date(2025, 6, 1)
    span = (WINDOW_END - start).days
    rows = []
    for i in range(1, n + 1):
        signup = start + timedelta(days=rng.randint(0, span))
        city = wchoice(rng, dict(CITIES))
        acq = wchoice(rng, ACQUISITION_WEIGHTS)
        # Facebook-acquired customers are less likely to book again (planted pattern)
        propensity = rng.paretovariate(4.0) * (0.4 if acq == 5 else 1.0)
        rows.append({"id": i, "signup": signup, "city": city, "acq": acq, "w": propensity})
    rows.sort(key=lambda r: (r["signup"], r["id"]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/raw")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--customers", type=int, default=20000)
    ap.add_argument("--bookings", type=int, default=9000)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    customers = make_customers(rng, args.customers)
    signups = [c["signup"] for c in customers]
    cum, total = [], 0.0
    for c in customers:
        total += c["w"]
        cum.append(total)

    days = [WINDOW_START + timedelta(days=i) for i in range((WINDOW_END - WINDOW_START).days + 1)]
    dweights = daily_weights(days)
    booking_days = sorted(rng.choices(days, weights=dweights, k=args.bookings))

    type_to_products = {}
    for p in PRODUCTS:
        type_to_products.setdefault(p[1], []).append(p)

    bookings, payments, refunds = [], [], []
    bookings_per_customer = {}
    pay_seq = 0
    refund_seq = 0

    for n, d in enumerate(booking_days, start=1):
        booking_id = f"BK{100000 + n}"
        ts = datetime(d.year, d.month, d.day, wchoice(rng, dict(enumerate(HOUR_WEIGHTS))),
                      rng.randint(0, 59), rng.randint(0, 59))

        guest = rng.random() < 0.004
        customer = None
        first_booking = False
        if not guest:
            k = bisect.bisect_right(signups, d)
            r = rng.random() * cum[k - 1]
            idx = bisect.bisect_left(cum, r, 0, k)
            customer = customers[idx]
            first_booking = customer["id"] not in bookings_per_customer
            bookings_per_customer[customer["id"]] = bookings_per_customer.get(customer["id"], 0) + 1

        if customer is not None and first_booking and rng.random() < 0.9:
            channel_id = customer["acq"]
        elif customer is not None and not first_booking and rng.random() < 0.8:
            channel_id = wchoice(rng, REPEAT_CHANNEL_WEIGHTS)
        else:
            channel_id = wchoice(rng, ACQUISITION_WEIGHTS)

        ptype = wchoice(rng, TYPE_WEIGHTS)
        product = rng.choice(type_to_products[ptype])
        gross = int(round(product[4] * rng.lognormvariate(0, 0.15), -1))

        final_method = wchoice(rng, METHOD_WEIGHTS)

        # promo: at most one per booking
        promo = None
        if customer is not None and first_booking and rng.random() < 0.5:
            promo = PROMOS[0]
        elif date(2026, 3, 10) <= d <= date(2026, 3, 31) and rng.random() < 0.45:
            promo = PROMOS[1]
        elif date(2026, 6, 1) <= d <= date(2026, 7, 31) and ptype in ("domestic_flight", "hotel") \
                and rng.random() < 0.30:
            promo = PROMOS[2]
        elif final_method == 1 and rng.random() < 0.40:
            promo = PROMOS[3]

        discount = 0
        if promo is not None:
            _, _, dtype, value, cap, _, _ = promo
            discount = min(int(round(gross * value / 100.0)), cap) if dtype == "percent" else min(value, gross)

        rate = COMMISSION[ptype] + rng.uniform(-0.005, 0.005)
        commission = int(round(gross * rate))

        lo, hi = LEAD_DAYS[ptype]
        travel = d + timedelta(days=rng.randint(lo, hi))

        cancel_p = CANCEL_PROB[ptype]
        if promo is not None and promo[1] == "EID15":
            cancel_p *= 2.0  # planted pattern: the Eid promo attracts bookings that get cancelled
        cancelled = rng.random() < cancel_p
        if cancelled:
            status = "cancelled"
        elif datetime(travel.year, travel.month, travel.day) < SNAPSHOT:
            status = "completed"
        else:
            status = "confirmed"

        paid = gross - discount

        # payment attempts: failed ones first, then one success at booking time
        n_fail = 0
        while n_fail < 3 and rng.random() < FAIL_PROB[final_method]:
            n_fail += 1
        attempts = []
        for j in range(n_fail):
            m = final_method if rng.random() < 0.65 else rng.choice([x for x in METHOD_WEIGHTS if x != final_method])
            attempts.append((m, "failed", ts - timedelta(minutes=(n_fail - j) * rng.randint(2, 9))))
        attempts.append((final_method, "success", ts))
        for m, st, pts in attempts:
            pay_seq += 1
            payments.append({
                "payment_id": f"PY{200000 + pay_seq}", "booking_id": booking_id,
                "payment_method_id": m, "amount": paid, "payment_ts": pts, "payment_status": st,
            })

        if cancelled and rng.random() < 0.92:  # 8% of cancellations have no refund record
            refund_seq += 1
            hours_available = max(2, min(480, (travel - d).days * 24))
            requested = ts + timedelta(hours=rng.uniform(1, hours_available))
            dlo, dhi = REFUND_DAYS[final_method]
            completed = requested + timedelta(days=rng.uniform(dlo, dhi))
            if completed > SNAPSHOT:
                completed = None  # still pending at the snapshot
            elif rng.random() < 0.006:
                completed = requested - timedelta(hours=rng.uniform(1, 48))  # bad timestamp, on purpose
            refunds.append({
                "refund_id": f"RF{300000 + refund_seq}", "booking_id": booking_id,
                "refund_amount": int(round(paid * REFUND_SHARE[ptype])),
                "requested_ts": requested, "completed_ts": completed,
            })

        bookings.append({
            "booking_id": booking_id, "customer_id": None if customer is None else customer["id"],
            "product_id": product[0], "channel_id": channel_id,
            "promo_code": promo[1] if promo else None,
            "booking_ts": ts, "travel_date": travel, "status": status,
            "gross_amount": gross, "discount_amount": discount, "commission_amount": commission,
        })

    # funnel: sessions counted per day, channel and furthest stage reached
    funnel = {}
    by_channel_days = {}
    for b in bookings:
        day = b["booking_ts"].date()
        by_channel_days.setdefault(b["channel_id"], []).append(day)
        key = (day, b["channel_id"], "booked")
        funnel[key] = funnel.get(key, 0) + 1
    stop_stage = {"search": 64, "select": 25, "checkout": 8, "payment": 3}
    for ch, ds in by_channel_days.items():
        booked = len(ds)
        extra = int(round(booked / CONVERSION[ch])) - booked
        for _ in range(extra):
            key = (rng.choice(ds), ch, wchoice(rng, stop_stage))
            funnel[key] = funnel.get(key, 0) + 1
    funnel_rows = sorted(funnel.items(), key=lambda kv: (kv[0][0], kv[0][1], kv[0][2]))

    # ---- raw (messy) outputs -------------------------------------------------
    def messy_status(s):
        r = rng.random()
        if r < 0.05:
            return s.capitalize()
        if r < 0.08:
            return s.upper() + " "
        return s

    def messy_promo(code):
        if code is None:
            return rng.choice(["", "NONE"])
        r = rng.random()
        if r < 0.05:
            return code.lower()
        if r < 0.08:
            return " " + code
        return code

    raw_rows = []
    for b in bookings:
        cust = b["customer_id"]
        raw_rows.append([
            b["booking_id"], "" if cust is None else cust, b["product_id"], b["channel_id"],
            messy_promo(b["promo_code"]), b["booking_ts"].strftime("%Y-%m-%d %H:%M:%S"),
            b["travel_date"].isoformat(), messy_status(b["status"]),
            b["gross_amount"], b["discount_amount"], b["commission_amount"],
        ])
    # exact duplicate rows (about 1.2%), inserted at random places
    for row in rng.sample(raw_rows, int(len(raw_rows) * 0.012)):
        raw_rows.insert(rng.randint(0, len(raw_rows)), list(row))
    # internal test rows with zero amounts
    for i in range(1, 13):
        raw_rows.insert(rng.randint(0, len(raw_rows)), [
            f"BKTEST{i:02d}", "", 1, 2, "NONE", "2026-04-15 10:00:00", "2026-04-20", "confirmed", 0, 0, 0])

    def write(name, header, rows):
        with open(os.path.join(args.out, name), "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)

    write("channels.csv", ["channel_id", "channel_name", "channel_type"], CHANNELS)
    write("payment_methods.csv", ["payment_method_id", "method_name", "method_type"], PAYMENT_METHODS)
    write("promos.csv", ["promo_id", "promo_code", "discount_type", "discount_value", "max_discount",
                         "start_date", "end_date"], PROMOS)
    write("products.csv", ["product_id", "product_type", "origin", "destination"],
          [(p[0], p[1], p[2], p[3]) for p in PRODUCTS])
    write("customers.csv", ["customer_id", "signup_date", "city", "acquisition_channel_id"],
          [(c["id"], c["signup"].isoformat(), c["city"], c["acq"]) for c in sorted(customers, key=lambda c: c["id"])])
    write("bookings.csv", ["booking_id", "customer_id", "product_id", "channel_id", "promo_code", "booking_ts",
                           "travel_date", "status", "gross_amount", "discount_amount", "commission_amount"],
          raw_rows)
    write("payments.csv", ["payment_id", "booking_id", "payment_method_id", "amount", "payment_ts", "payment_status"],
          [(p["payment_id"], p["booking_id"], p["payment_method_id"], p["amount"],
            p["payment_ts"].strftime("%Y-%m-%d %H:%M:%S"), p["payment_status"]) for p in payments])
    write("refunds.csv", ["refund_id", "booking_id", "refund_amount", "requested_ts", "completed_ts"],
          [(r["refund_id"], r["booking_id"], r["refund_amount"], r["requested_ts"].strftime("%Y-%m-%d %H:%M:%S"),
            "" if r["completed_ts"] is None else r["completed_ts"].strftime("%Y-%m-%d %H:%M:%S")) for r in refunds])
    write("funnel_daily.csv", ["session_date", "channel_id", "furthest_stage", "sessions"],
          [(k[0].isoformat(), k[1], k[2], v) for k, v in funnel_rows])

    n_cust_booked = len(bookings_per_customer)
    n_repeat = sum(1 for v in bookings_per_customer.values() if v >= 2)
    print(f"customers: {len(customers)}  bookings (before duplicates): {len(bookings)}  raw booking rows: {len(raw_rows)}")
    print(f"payments: {len(payments)}  refunds: {len(refunds)}  funnel rows: {len(funnel_rows)}  sessions in funnel: {sum(funnel.values())}")
    print(f"customers with a booking: {n_cust_booked}  with 2+ bookings: {n_repeat} ({n_repeat / n_cust_booked:.1%})")


if __name__ == "__main__":
    main()
