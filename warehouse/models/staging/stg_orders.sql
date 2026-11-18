select
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp::timestamp       as purchased_at,
    order_approved_at::timestamp              as approved_at,
    order_delivered_carrier_date::timestamp   as delivered_to_carrier_at,
    order_delivered_customer_date::timestamp  as delivered_at,
    -- Always midnight in the source, so it's really a date.
    order_estimated_delivery_date::date       as estimated_delivery_date
from {{ source('raw', 'orders') }}
