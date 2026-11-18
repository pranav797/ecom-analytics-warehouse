select
    customer_id,         -- one per ORDER: a new id is issued for every order
    customer_unique_id,  -- one per PERSON: use this for repeat-purchase metrics
    customer_zip_code_prefix  as zip_code_prefix,
    customer_city             as city,
    customer_state            as state
from {{ source('raw', 'customers') }}
