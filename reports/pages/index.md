---
title: Overview
---

```sql monthly_kpis
select * from warehouse.monthly_kpis
```

How the Olist marketplace performed, Jan 2017 – Aug 2018 (complete months, delivered orders).
Olist is a marketplace of small sellers, so every metric here is something a merchant would track.

```sql totals
select
    sum(delivered_orders)                                            as orders,
    sum(gmv)                                                         as gmv,
    sum(gmv) / sum(delivered_orders)                                 as aov,
    sum(on_time_rate * delivered_orders) / sum(delivered_orders)     as on_time_rate,
    sum(avg_review_score * delivered_orders) / sum(delivered_orders) as avg_review_score
from warehouse.monthly_kpis
```

<BigValue data={totals} value=gmv title="GMV (R$)" fmt='#,##0.0,,"M"'/>
<BigValue data={totals} value=orders title="Delivered orders" fmt=num0/>
<BigValue data={totals} value=aov title="AOV (R$)" fmt=num2/>
<BigValue data={totals} value=on_time_rate title="On-time rate" fmt=pct1/>
<BigValue data={totals} value=avg_review_score title="Avg review" fmt=num2/>

## GMV by month

<BarChart data={monthly_kpis} x=month y=gmv yFmt='#,##0,"K"' xFmt='mmm yy' yAxisTitle="GMV (R$)"/>

## Orders and average order value

<LineChart data={monthly_kpis} x=month y=delivered_orders y2=aov y2Fmt=num0 xFmt='mmm yy' yAxisTitle="Delivered orders" y2AxisTitle="AOV (R$)"/>

## On-time rate and review score

<LineChart data={monthly_kpis} x=month y=on_time_rate y2=avg_review_score yFmt=pct0 y2Fmt=num1 xFmt='mmm yy' yAxisTitle="On-time rate" y2AxisTitle="Avg review"/>

The two lines move together: months with worse delivery have worse reviews. [Findings](/findings)
tests whether lateness actually *causes* this.

## Definitions

- **GMV**: sum of item prices on delivered orders. Freight is excluded, because it goes to the carrier.
- **AOV**: GMV ÷ delivered orders.
- **On-time**: delivered on or before the promised date.
- **Avg review**: one review per order (the most recently answered one).

---
<small>Data: <a href="https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce">Brazilian E-Commerce Public Dataset by Olist</a>, CC BY-NC-SA 4.0. Derived data shared under the same license.</small>
