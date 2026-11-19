{% docs metric_gmv %}
**GMV (gross merchandise value)**: sum of item `price` on **delivered** orders. Freight is excluded.

- Freight is excluded because it goes to the carrier, not the merchant. Including it would make
  sellers who ship heavy items look bigger than they are.
- Only delivered orders count. Canceled or unavailable orders never generated revenue for the
  merchant.
- Rejected: `payment_value`. It includes freight, and it differs from items + freight on ~260
  orders (vouchers, installment interest).
{% enddocs %}

{% docs metric_aov %}
**AOV (average order value)**: GMV ÷ number of delivered orders. At seller level it uses only
that seller's items in each order, so a multi-seller order adds just this seller's share.
{% enddocs %}

{% docs metric_on_time_rate %}
**On-time delivery rate**: share of delivered orders with delivered **date** ≤ estimated delivery
date.

- Dates, not timestamps: the promise is a date, so arriving at 9pm on the promised day is on time.
- Undelivered orders are excluded instead of counted as late, because many of them were canceled
  before they shipped.
{% enddocs %}

{% docs metric_avg_review %}
**Average review score**: mean 1–5 score using **one review per order** (see
`int_order_reviews_dedup`). Orders without a review are excluded, not counted as zero.
{% enddocs %}

{% docs metric_repeat_purchase %}
**Repeat purchase (180 days)**: true if the person (`customer_unique_id`) has another delivered
order placed **more than 24 hours and at most 180 days** after their first delivered order.
Repeat purchase rate = average of this flag over non-null rows.

- `customer_unique_id`, not `customer_id`: `customer_id` is new on every order, so using it would
  make the repeat rate 0%.
- More than 24 hours: about 28% of "second orders" are placed within an hour of the first. That's
  one cart split by seller, not a return visit.
- 180 days: the data covers ~20 complete months. A longer window would censor most customers.
- Null (excluded) when the 180-day window runs past the end of the data. Counting those customers
  as "not repeat" would push the rate down for recent customers.
- Rejected: "≥ 2 orders ever". It isn't comparable across customers who joined at different times.
{% enddocs %}

{% docs metric_seller_retention %}
**Seller retention (month k)**: of sellers whose first delivered sale was in month *m*, the share
with ≥ 1 delivered sale in month *m + k*.

- Measures activity in month m + k exactly, not "any time up to m + k". A seller can skip a month
  and come back, so the curve can go up as well as down.
- Rejected: "still active (any sale after month k)". It depends on how much later data exists, so
  recent cohorts would look worse.
- Only (cohort, k) pairs inside the data window are included. Recent cohorts have shorter rows.
{% enddocs %}
