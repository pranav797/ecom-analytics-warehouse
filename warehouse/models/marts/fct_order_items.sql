-- One row per order item: the grain for seller and category revenue.
select
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    i.seller_state,
    i.category,
    o.purchased_at,
    o.purchase_month,
    o.is_delivered,
    i.price,
    i.freight_value
from {{ ref('int_order_items_enriched') }} i
join {{ ref('fct_orders') }} o using (order_id)
