-- Aim is to find out if users listen to just a single podcast or multiple
-- Reuses mart_user_engagement rather than recomputing from fct_listening_events,
-- since distinct_podcasts_listened already exists there. Users with zero valid
-- listen events (distinct_podcasts_listened is null, from the left join in that
-- mart) are grouped separately rather than silently excluded.

select
    case
        when distinct_podcasts_listened is null then 'no_listens'
        when distinct_podcasts_listened = 1 then 'single_podcast'
        else 'multi_podcast'
    end as listener_type,
    count(*) as user_count,
    round(avg(distinct_episodes_listened), 1) as avg_episodes_listened
from {{ ref('mart_user_engagement') }}
group by 1
order by user_count desc


-- Finding: 395 of 400 users fall into multi_podcast (avg 26.7 distinct episodes
-- listened each), against 4 single_podcast users (avg 5.0 episodes) and 1 with no
-- listens at all. Those 4 look less like loyal listeners than like users with too
-- little activity to have branched out, so the binary split has almost no
-- discriminating power here: across 200 episodes and 30 podcasts, touching more than
-- one is close to inevitable for anyone active. See 10 for a continuous concentration
-- measure that does show real variation.
--
-- The no_listens branch is worth keeping even though it catches a single user. It
-- only fires because mart_user_engagement wraps its distinct counts in nullif:
-- count() returns 0, not null, for a user with events but no listens, so without that
-- the user would fall through to multi_podcast having listened to nothing.