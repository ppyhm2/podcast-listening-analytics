-- For each user_id and each event_date: how many distinct episodes they listened to,
-- and how many listen events they generated. Both are scoped to listen events only
-- (play or complete, per is_listen_event), hence total_listen_events rather than
-- total_events, which in mart_user_engagement counts every event type.

select
    user_id,
    event_date,
    count(distinct episode_id) as distinct_episodes,
    count(*) as total_listen_events,
    current_timestamp as data_refreshed_on
from {{ ref('fct_listening_events') }}
where is_listen_event
group by 1, 2