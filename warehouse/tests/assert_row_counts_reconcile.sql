-- Singular test: staging must not gain or lose rows vs raw, and fct_orders must have every order.
-- Returns one row per table whose counts don't match.
with counts as (
    select 'orders' as tbl,         (select count(*) from {{ source('raw', 'orders') }})         as raw_rows, (select count(*) from {{ ref('stg_orders') }})         as model_rows
    union all select 'order_items',    (select count(*) from {{ source('raw', 'order_items') }}),    (select count(*) from {{ ref('stg_order_items') }})
    union all select 'order_payments', (select count(*) from {{ source('raw', 'order_payments') }}), (select count(*) from {{ ref('stg_order_payments') }})
    union all select 'order_reviews',  (select count(*) from {{ source('raw', 'order_reviews') }}),  (select count(*) from {{ ref('stg_order_reviews') }})
    union all select 'customers',      (select count(*) from {{ source('raw', 'customers') }}),      (select count(*) from {{ ref('stg_customers') }})
    union all select 'sellers',        (select count(*) from {{ source('raw', 'sellers') }}),        (select count(*) from {{ ref('stg_sellers') }})
    union all select 'products',       (select count(*) from {{ source('raw', 'products') }}),       (select count(*) from {{ ref('stg_products') }})
    union all select 'geolocation',    (select count(*) from {{ source('raw', 'geolocation') }}),    (select count(*) from {{ ref('stg_geolocation') }})
    union all select 'fct_orders',     (select count(*) from {{ source('raw', 'orders') }}),         (select count(*) from {{ ref('fct_orders') }})
    union all select 'fct_order_items',(select count(*) from {{ source('raw', 'order_items') }}),    (select count(*) from {{ ref('fct_order_items') }})
)
select * from counts where raw_rows <> model_rows
