-- One row per day offset from the promised delivery date (delivered, reviewed orders).
-- Aggregated view for the dashboard's RD plot; the RD estimate itself uses order-level rows in analysis/.
select
    days_vs_estimate,
    days_vs_estimate > 0                        as is_late,
    count(*)                                    as orders,
    avg(review_score)                           as avg_review_score,
    avg((review_score = 1)::int)                as share_1_star,
    avg((review_score = 5)::int)                as share_5_star,
    avg(is_review_before_delivery::int)         as share_review_before_delivery,
    avg(items_value)                            as avg_items_value,
    avg(freight_value)                          as avg_freight_value
from {{ ref('fct_orders') }}
where is_delivered and review_score is not null
group by all
