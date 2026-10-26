# Metric definitions

These definitions are chosen for this project. Real companies define the same words differently, so in a real job the first step is to agree on each definition with the people who use the number.

All amounts are in BDT. "Active booking" means a booking whose status is not `cancelled`.

| # | Metric | Definition | Where |
| --- | --- | --- | --- |
| 1 | Gross booking value (GBV) | Sum of `gross_amount` over active bookings. This is the list price before any discount. | sql/05_metrics.sql, query 1 |
| 2 | Net revenue | Sum of `commission_amount - discount_amount` over active bookings. Commission is what the company earns from the supplier. The discount is the promo cost the company pays. Negative net revenue means a promo cost more than the commission. | query 2 |
| 3 | Booking conversion by stage | Sessions that reached a stage divided by all sessions (and by the previous stage). A session that reached `checkout` also reached `search` and `select`, so each stage counts every session whose furthest stage is that stage or later. | query 3 |
| 4 | Cancellation rate | Cancelled bookings divided by all bookings, for each product type and promo code. | query 4 |
| 5 | Refund time | Days from `requested_ts` to `completed_ts`, by the payment method that paid for the booking. Only completed refunds with a valid timestamp count. Pending refunds are left out, so the figure describes finished refunds only. | query 5 |
| 6 | Repeat booking rate | Customers with at least 2 active bookings divided by customers with at least 1, grouped by the channel that acquired them. Guest checkouts have no customer and are left out. | query 6 |
| 7 | Revenue by channel | GBV, GBV share and net revenue of active bookings, grouped by the channel the booking came through. | query 7 |
| 8 | Discount cost | Sum of `discount_amount` by promo code and payment method for active bookings. Also shown as a percentage of commission. | query 8 |

## Edge cases the SQL handles

- **Failed payments.** A booking can have several payment rows. Metrics that need the payment method join to the successful attempt only. Joining to every attempt counts bookings more than once (see question 1 in `06_analysis_questions.sql`).
- **Cancelled bookings.** GBV, net revenue, repeat rate and revenue by channel leave them out. The cancellation rate puts them back in, because it needs the full count.
- **Division by zero.** Percentages use `NULLIF` or filters that cannot reach zero in this data.
- **Time.** The dataset ends on 30 September 2026. The snapshot date for pending refunds is 1 October 2026.
