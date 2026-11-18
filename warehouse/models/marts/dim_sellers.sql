-- One row per seller. GMV = sum of item price on delivered orders (freight excluded).
with sales as (
    select
        seller_id,
        min(purchased_at)                                   as first_sale_at,
        max(purchased_at)                                   as last_sale_at,
        count(distinct order_id) filter (where is_delivered) as delivered_orders,
        coalesce(sum(price) filter (where is_delivered), 0)  as lifetime_gmv
    from {{ ref('fct_order_items') }}
    group by seller_id
)

select
    s.seller_id,
    s.zip_code_prefix,
    s.city,
    s.state,
    sales.first_sale_at,
    sales.last_sale_at,
    coalesce(sales.delivered_orders, 0)  as delivered_orders,
    coalesce(sales.lifetime_gmv, 0)      as lifetime_gmv
from {{ ref('stg_sellers') }} s
left join sales using (seller_id)
