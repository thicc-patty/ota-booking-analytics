# Power BI dashboard spec

Power BI Desktop is free and runs on Windows. This spec was written without running Power BI, so check that each measure compiles when you paste it, and fix any column name that Power BI shows differently.

## Load the data

1. In Power BI Desktop choose Get data, then Text/CSV.
2. Load these four files from `data/powerbi/`. Keep the default table names.

| File | Table name | One row is |
| --- | --- | --- |
| bookings.csv | bookings | one booking |
| payments.csv | payments | one payment attempt |
| refunds.csv | refunds | one refund request |
| funnel.csv | funnel | one month, channel and funnel stage |

Each file is already flat, so no relationships are needed. Check that `month_start` and the other date columns have the Date type.

## Measures for the bookings table

```
Bookings = CALCULATE(COUNTROWS(bookings), bookings[status] <> "cancelled")
GBV = CALCULATE(SUM(bookings[gross_amount]), bookings[status] <> "cancelled")
Net revenue = CALCULATE(SUM(bookings[net_revenue]), bookings[status] <> "cancelled")
Discount cost = CALCULATE(SUM(bookings[discount_amount]), bookings[status] <> "cancelled")
Cancellation rate = DIVIDE(CALCULATE(COUNTROWS(bookings), bookings[status] = "cancelled"), COUNTROWS(bookings))
```

## Measures for the other tables

```
Payment failure rate = DIVIDE(CALCULATE(COUNTROWS(payments), payments[payment_status] = "failed"), COUNTROWS(payments))
Avg refund days = AVERAGE(refunds[days_to_complete])
Pending refunds = CALCULATE(COUNTROWS(refunds), refunds[is_pending] = "Yes")
Sessions reaching stage = SUM(funnel[sessions_reaching_stage])
```

## Page 1: Sales overview

- Four cards: GBV, Net revenue, Bookings, Cancellation rate.
- Line chart: GBV by `month_start`.
- Bar chart: GBV by `channel_name`.
- Slicer: `product_type`.
- Question this page answers: where does the money come from, and when?

## Page 2: Funnel and payments

- Funnel chart: Sessions reaching stage by `stage` (sort by `stage_order`).
- Bar chart: Payment failure rate by `payment_method`.
- Slicers: `month_start` and `channel_name` (they filter the funnel).
- Question this page answers: where do customers drop out, and which payment method loses sales?

## Page 3: Promos and refunds

- Matrix: rows `promo_code`, columns `payment_method`, values Discount cost.
- Bar chart: Net revenue by `promo_code`.
- Bar chart: Avg refund days by `payment_method` (refunds table).
- Card: Pending refunds.
- Question this page answers: which promos cost too much, and which payment method makes refunds slow?

## Design notes

- One message per page, stated in the page title.
- Same colour for the same thing on every page (for example one colour per payment method).
- Format money with thousands separators and label the unit (BDT).
- Add a text box on each page: "Synthetic data. See the GitHub README."
- Take a screenshot of each finished page and put the images in the repository. That shows the work without the viewer needing Power BI.
