select
    strftime(cohort_month, '%Y-%m')  as cohort,
    cohort_month,
    months_since_first_sale,
    cohort_sellers,
    active_sellers,
    retention_rate
from marts.mart_seller_cohorts
