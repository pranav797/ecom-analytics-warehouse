-- Platform KPIs per purchase month (delivered orders), over the same complete-month window as the marts.
select
    purchase_month                                        as month,
    count(*)                                              as delivered_orders,
    sum(items_value)                                      as gmv,
    sum(items_value) / count(*)                           as aov,
    avg((not is_late)::int)                               as on_time_rate,
    avg(review_score)                                     as avg_review_score
from marts.fct_orders
where is_delivered
  and purchase_month between (select min(month) from marts.mart_seller_monthly)
                         and (select max(month) from marts.mart_seller_monthly)
group by 1
order by 1
