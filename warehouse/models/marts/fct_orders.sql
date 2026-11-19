-- One row per order (all statuses). Filter on is_delivered for revenue / delivery metrics.
with items as (
    select
        order_id,
        count(*)                   as item_count,
        count(distinct seller_id)  as seller_count,
        sum(price)                 as items_value,
        sum(freight_value)         as freight_value
    from {{ ref('stg_order_items') }}
    group by order_id
),

payments as (
    select order_id, sum(payment_value) as payment_value
    from {{ ref('stg_order_payments') }}
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.state  as customer_state,  -- where this order was shipped
    o.order_status,
    o.purchased_at,
    date_trunc('month', o.purchased_at)::date  as purchase_month,
    o.delivered_at,
    o.estimated_delivery_date,

    -- 775 orders have no items (almost all unavailable/canceled): counts are 0, values null.
    coalesce(i.item_count, 0)    as item_count,
    coalesce(i.seller_count, 0)  as seller_count,
    i.items_value,       -- sum of item prices: the basis for GMV
    i.freight_value,
    p.payment_value,     -- what the customer paid; differs from items + freight on ~260 orders

    d.is_delivered,
    d.days_to_deliver,
    d.days_vs_estimate,
    d.is_late,

    r.review_score,      -- null for 768 orders with no review
    r.review_created_at,
    -- ~5% of reviews were written before the delivery date; the RD analysis should flag or drop these.
    r.review_created_at::date < o.delivered_at::date  as is_review_before_delivery

from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c using (customer_id)
join {{ ref('int_order_delivery') }} d using (order_id)
left join items i using (order_id)
left join payments p using (order_id)
left join {{ ref('int_order_reviews_dedup') }} r using (order_id)
