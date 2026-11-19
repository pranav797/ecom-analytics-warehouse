-- One row per seller over the metric window: leaderboard + filters.
with category_gmv as (
    select seller_id, category, sum(price) as gmv
    from marts.fct_order_items
    where is_delivered
    group by all
),
main_category as (  -- the category that brings the seller the most GMV
    select seller_id, arg_max(category, gmv) as main_category
    from category_gmv
    group by 1
)
select
    m.seller_id,
    left(m.seller_id, 8)                                                as seller,
    s.state,
    c.main_category,
    sum(m.gmv)                                                          as gmv,
    sum(m.orders)                                                       as orders,
    sum(m.gmv) / sum(m.orders)                                          as aov,
    sum(m.on_time_rate * m.orders) / sum(m.orders)                      as on_time_rate,
    sum(m.avg_review_score * m.reviews) / nullif(sum(m.reviews), 0)     as avg_review_score,
    count(*)                                                            as active_months
from marts.mart_seller_monthly m
join marts.dim_sellers s using (seller_id)
left join main_category c using (seller_id)
group by all
