-- Category stays in Portuguese here; the English name is joined in the intermediate layer.
select
    product_id,
    product_category_name               as category_name_pt,
    product_name_lenght::integer        as name_length,         -- source column is misspelled
    product_description_lenght::integer as description_length, -- source column is misspelled
    product_photos_qty::integer         as photos_qty,
    product_weight_g::integer           as weight_g,
    product_length_cm::integer          as length_cm,
    product_height_cm::integer          as height_cm,
    product_width_cm::integer           as width_cm
from {{ source('raw', 'products') }}
