-- Delivery performance by the customer's state (delivered orders in the metric window).
select
    customer_state                     as state,
    count(*)                           as delivered_orders,
    avg((not is_late)::int)            as on_time_rate,
    avg(days_to_deliver)               as avg_days_to_deliver,
    avg(review_score)                  as avg_review_score
from marts.fct_orders
where is_delivered
  and purchase_month between (select min(month) from marts.mart_seller_monthly)
                         and (select max(month) from marts.mart_seller_monthly)
group by 1
