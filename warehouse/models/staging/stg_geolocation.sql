-- Several rows per zip prefix (and a few points outside Brazil); aggregate before joining.
select
    geolocation_zip_code_prefix  as zip_code_prefix,
    geolocation_lat::double      as lat,
    geolocation_lng::double      as lng,
    geolocation_city             as city,
    geolocation_state            as state
from {{ source('raw', 'geolocation') }}
