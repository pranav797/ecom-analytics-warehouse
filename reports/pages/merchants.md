---
title: Merchants
---

```sql sellers
select * from warehouse.sellers
```

```sql seller_cohorts
select * from warehouse.seller_cohorts
```

Seller performance and retention, Jan 2017 – Aug 2018.

## Seller leaderboard

<Dropdown data={sellers} name=state value=state title="Seller state" order=state>
    <DropdownOption value="%" valueLabel="All states"/>
</Dropdown>

<Dropdown data={sellers} name=category value=main_category title="Main category" order=main_category>
    <DropdownOption value="%" valueLabel="All categories"/>
</Dropdown>

```sql filtered_sellers
select *
from warehouse.sellers
where state like '${inputs.state.value}'
  and main_category like '${inputs.category.value}'
order by gmv desc
```

```sql filtered_totals
select
    count(*)                                  as sellers,
    sum(gmv)                                  as gmv,
    median(gmv)                               as median_gmv,
    sum(on_time_rate * orders) / sum(orders)  as on_time_rate
from ${filtered_sellers}
```

<BigValue data={filtered_totals} value=sellers title="Sellers" fmt=num0/>
<BigValue data={filtered_totals} value=gmv title="GMV (R$)" fmt='#,##0.0,,"M"'/>
<BigValue data={filtered_totals} value=median_gmv title="Median seller GMV (R$)" fmt=num0/>
<BigValue data={filtered_totals} value=on_time_rate title="On-time rate" fmt=pct1/>

<DataTable data={filtered_sellers} search=true rows=15>
    <Column id=seller title="Seller"/>
    <Column id=state title="State"/>
    <Column id=main_category title="Main category"/>
    <Column id=gmv title="GMV (R$)" fmt=num0 contentType=bar/>
    <Column id=orders fmt=num0/>
    <Column id=aov title="AOV (R$)" fmt=num0/>
    <Column id=on_time_rate title="On-time" fmt=pct0/>
    <Column id=avg_review_score title="Avg review" fmt=num2 contentType=colorscale/>
    <Column id=active_months title="Active months"/>
</DataTable>

Seller IDs are shortened to their first 8 characters. Sellers are anonymised in the source data.

## Seller retention by first-sale cohort

The share of sellers who made a sale in month *k* after their first sale. Each row is a cohort
(the month of first sale), and recent cohorts have shorter rows because later months haven't
happened yet.

<Heatmap data={seller_cohorts} x=months_since_first_sale y=cohort value=retention_rate valueFmt=pct0 xSort=months_since_first_sale ySort=cohort_month/>

```sql retention_curve
select
    months_since_first_sale,
    sum(active_sellers) / sum(cohort_sellers) as retention_rate
from warehouse.seller_cohorts
group by 1
order by 1
```

<LineChart data={retention_curve} x=months_since_first_sale y=retention_rate yFmt=pct0 xAxisTitle="Months since first sale" yAxisTitle="Sellers active" title="All cohorts combined"/>

About 60% of new sellers sell again the next month, and just under half are still selling six months later.

---
<small>Data: <a href="https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce">Brazilian E-Commerce Public Dataset by Olist</a>, CC BY-NC-SA 4.0. Derived data shared under the same license.</small>
