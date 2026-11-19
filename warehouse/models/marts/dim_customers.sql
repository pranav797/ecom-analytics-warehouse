-- One row per PERSON (customer_unique_id), not per customer_id (which is issued per order).
-- Location is taken from the person's most recent order.
with orders as (
    select
        o.customer_unique_id,
        o.purchased_at,
        o.is_delivered,
        c.zip_code_prefix,
        c.city,
        c.state,
        min(o.purchased_at) filter (where o.is_delivered)
            over (partition by o.customer_unique_id)  as first_delivered_at
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
    count(*) filter (where is_delivered)    as delivered_orders,
    any_value(first_delivered_at)           as first_delivered_order_at,

    -- Repeat purchase: another delivered order placed > 24h and <= 180 days after the first delivered one.
    -- > 24h because ~28% of "second orders" are placed within an hour of the first: one cart split by
    -- seller, not a return visit. Null when not observable: no delivered order, or the 180-day window
    -- runs past the end of the data (censored).
    case
        when any_value(first_delivered_at) is null then null
        when any_value(first_delivered_at) + interval 180 day
             >= date '{{ var("metrics_end_month") }}' + interval 1 month then null
        else count(*) filter (
            where is_delivered
              and purchased_at >  first_delivered_at + interval 1 day
              and purchased_at <= first_delivered_at + interval 180 day
        ) > 0
    end                                     as is_repeat_within_180d
from orders
group by customer_unique_id
