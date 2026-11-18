-- One row per PERSON (customer_unique_id), not per customer_id (which is issued per order).
-- Location is taken from the person's most recent order.
with orders as (
    select
        o.customer_unique_id,
        o.purchased_at,
        o.is_delivered,
        c.zip_code_prefix,
        c.city,
        c.state
    from {{ ref('fct_orders') }} o
    join {{ ref('stg_customers') }} c using (customer_id)
)

select
    customer_unique_id,
    arg_max(zip_code_prefix, purchased_at)  as zip_code_prefix,
    arg_max(city, purchased_at)             as city,
    arg_max(state, purchased_at)            as state,
    min(purchased_at)                       as first_order_at,
    count(*)                                as orders,
    count(*) filter (where is_delivered)    as delivered_orders
from orders
group by customer_unique_id
