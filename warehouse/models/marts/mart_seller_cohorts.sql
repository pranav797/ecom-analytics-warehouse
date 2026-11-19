-- Seller retention: of sellers whose first delivered sale was in cohort_month,
-- the share with >= 1 delivered sale k months later. Only k values already observable are included.
with activity as (
    select distinct seller_id, purchase_month as month
    from {{ ref('fct_order_items') }}
    where is_delivered
      and purchase_month between '{{ var("metrics_start_month") }}' and '{{ var("metrics_end_month") }}'
),

first_sale as (
    select seller_id, min(month) as cohort_month
    from activity
    group by seller_id
),

-- Every (cohort, k) pair up to the last month, so months with 0 active sellers still appear as 0%.
grid as (
    select cohort_month, k
    from (select distinct cohort_month from first_sale),
         range(0, 24) as t(k)
    where (cohort_month + to_months(k))::date <= '{{ var("metrics_end_month") }}'
)

select
    g.cohort_month,
    g.k                                                    as months_since_first_sale,
    count(distinct f.seller_id)                            as cohort_sellers,
    count(distinct a.seller_id)                            as active_sellers,
    count(distinct a.seller_id) / count(distinct f.seller_id) as retention_rate
from grid g
join first_sale f on f.cohort_month = g.cohort_month
left join activity a
    on a.seller_id = f.seller_id
   and a.month = (g.cohort_month + to_months(g.k))::date
group by all
