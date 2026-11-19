-- One row per seller x month with >= 1 delivered order. Month = purchase month.
-- An order with items from several sellers counts once for each of them, with only that seller's items in GMV.
with seller_orders as (
    select seller_id, order_id, purchase_month, sum(price) as gmv
    from {{ ref('fct_order_items') }}
    where is_delivered
      and purchase_month between '{{ var("metrics_start_month") }}' and '{{ var("metrics_end_month") }}'
    group by all
)

select
    so.seller_id,
    so.purchase_month                    as month,
    count(*)                             as orders,
    sum(so.gmv)                          as gmv,
    sum(so.gmv) / count(*)               as aov,
    avg((not o.is_late)::int)            as on_time_rate,
    avg(o.review_score)                  as avg_review_score,
    count(o.review_score)                as reviews
from seller_orders so
join {{ ref('fct_orders') }} o using (order_id)
group by all
