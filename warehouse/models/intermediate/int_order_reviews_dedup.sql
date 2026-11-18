-- One review per order. 547 orders have 2-3 reviews (202 with different scores).
-- Rule: keep the review answered most recently, i.e. the customer's last word.
-- Rejected: earliest review (ignores updates) and averaging (gives non-integer scores, breaks "% 5-star").
select
    order_id,
    review_id,
    review_score,
    review_created_at,
    review_answered_at,
    count(*) over (partition by order_id) as reviews_for_order
from {{ ref('stg_order_reviews') }}
qualify row_number() over (
    partition by order_id
    order by review_answered_at desc, review_id  -- review_id breaks ties deterministically
) = 1
