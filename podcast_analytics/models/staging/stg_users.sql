select
    user_id,
    cast(signup_date as date) as signup_date,
    country
from {{ ref('users') }}

-- we use ref instead of source since we're using seeds instead of a table on a database