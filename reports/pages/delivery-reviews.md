---
title: Delivery & Reviews
---

Each order has a promised delivery date. How do reviews change with how early or late the order arrives?

## Review score by days vs the promised date

```sql curve
select
    days_vs_estimate,
    avg_review_score,
    share_1_star,
    share_5_star,
    orders,
    case when is_late then 'Late' else 'On time' end as delivery
from warehouse.delivery_reviews
order by days_vs_estimate
```

<ScatterPlot data={curve} x=days_vs_estimate y=avg_review_score series=delivery xAxisTitle="Days vs promised date (negative = early)" yAxisTitle="Average review" yMin=1 yMax=5>
    <ReferenceLine x=0.5 label="Promised date" hideValue=true/>
</ScatterPlot>

Before the promised date, scores are flat at around 4.1–4.3. After it they fall about half a star
for each day late, then level off near 1.7. The damage comes from *how late* an order is, not from
missing the date by itself.

<LineChart data={curve} x=days_vs_estimate y={['share_5_star','share_1_star']} yFmt=pct0 xAxisTitle="Days vs promised date" yAxisTitle="Share of reviews">
    <ReferenceLine x=0.5 label="Promised date" hideValue=true/>
</LineChart>

<BarChart data={curve} x=days_vs_estimate y=orders xAxisTitle="Days vs promised date" yAxisTitle="Orders" title="Orders per day offset">
    <ReferenceLine x=0.5 label="Promised date" hideValue=true/>
</BarChart>

Orders drop sharply just after the promised date. Some of that is carriers rushing to hit the
date (called "bunching"), and it's the main caveat in [Findings](/findings).

## On-time rate by customer state

```sql states
select * from warehouse.ontime_by_state order by on_time_rate
```

<BarChart data={states} x=state y=on_time_rate yFmt=pct0 swapXY=true sort=false yAxisTitle="On-time rate"/>

<DataTable data={states} rows=all>
    <Column id=state title="State"/>
    <Column id=delivered_orders title="Orders" fmt=num0/>
    <Column id=on_time_rate title="On-time" fmt=pct1 contentType=colorscale/>
    <Column id=avg_days_to_deliver title="Avg days to deliver" fmt=num1/>
    <Column id=avg_review_score title="Avg review" fmt=num2/>
</DataTable>

---
<small>Data: <a href="https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce">Brazilian E-Commerce Public Dataset by Olist</a>, CC BY-NC-SA 4.0. Derived data shared under the same license.</small>
