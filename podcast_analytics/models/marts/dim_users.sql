select
    user_id,
    signup_date,
    country,
    date_part('year', signup_date) as signup_year,
    date_part('month', signup_date) as signup_month,
    current_timestamp as data_refreshed_on
from {{ ref('stg_users') }}