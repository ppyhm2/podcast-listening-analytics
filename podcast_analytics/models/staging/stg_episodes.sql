select
    episode_id,
    podcast_id,
    title,
    cast(release_date as date) as release_date,
    duration_seconds
from {{ ref('episodes') }}

-- we use ref instead of source since we're using seeds instead of a table on a database