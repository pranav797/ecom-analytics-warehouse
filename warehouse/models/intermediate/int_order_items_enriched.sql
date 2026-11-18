-- Order items + product category (in English) + seller location.
select
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    s.state  as seller_state,
    -- 2 categories have no translation (fall back to Portuguese); 610 products have no category.
    coalesce(t.category_name_en, p.category_name_pt, 'unknown') as category,
    i.price,
    i.freight_value
from {{ ref('stg_order_items') }} i
left join {{ ref('stg_products') }} p using (product_id)
left join {{ ref('stg_product_category_translation') }} t using (category_name_pt)
left join {{ ref('stg_sellers') }} s using (seller_id)
