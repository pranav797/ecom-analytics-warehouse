-- One row per order: was it delivered, and how early/late vs the promised date.
with orders as (
    select
        *,
        -- 8 'delivered' orders have no delivery date and 6 'canceled' ones do; require both.
        order_status = 'delivered' and delivered_at is not null as is_delivered
    from {{ ref('stg_orders') }}
)

select
    order_id,
    is_delivered,
    case when is_delivered then delivered_at::date - purchased_at::date end      as days_to_deliver,
    -- Negative = early, 0 = on the promised day, positive = late. Whole days, because the estimate is a date.
    case when is_delivered then delivered_at::date - estimated_delivery_date end as days_vs_estimate,
    case when is_delivered then delivered_at::date > estimated_delivery_date end as is_late
from orders
