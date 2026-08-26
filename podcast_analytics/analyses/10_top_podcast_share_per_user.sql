-- Aim is to find out if users are listening to a particular podcast more
-- than others. This is a follow up of 09, which shows that almost everyone in the
-- dataset listens to multiple podcasts rather than only one.

-- More specifically, the aim is to find out what share of a user's listens went to their single
-- most-listened podcast. Even where every user touches multiple podcasts, this can still distinguish
-- someone who's 80% concentrated on one show from someone genuinely spread evenly across several.

with user_podcast_counts as (

    select
        f.user_id,
        ep.podcast_id,
        count(*) as listens
    from {{ ref('fct_listening_events') }} f
    join {{ ref('dim_episodes') }} ep on f.episode_id = ep.episode_id
    where f.is_listen_event
    group by 1, 2

),

ranked as (

    select
        *,
        row_number() over (partition by user_id order by listens desc) as rn,
        sum(listens) over (partition by user_id) as total_listens
    from user_podcast_counts

)

select
    round(avg(listens * 1.0 / total_listens), 2) as avg_top_podcast_concentration,
    round(min(listens * 1.0 / total_listens), 2) as min_concentration,
    round(max(listens * 1.0 / total_listens), 2) as max_concentration
from ranked
where rn = 1
-- rn = 1 to return the information for each user's most listened to podcast


-- Finding: average top-podcast concentration is 0.40 (40% of a user's listens go
-- to their single most-listened podcast), ranging from 0.07 to 1.00 across users.
-- The range is the useful part: unlike the binary split in 09, this distinguishes
-- someone spreading listening thinly across the catalogue from someone concentrated
-- almost entirely on one show. A soft loyalty signal worth developing further with
-- real usage data, and useful for product and content teams.