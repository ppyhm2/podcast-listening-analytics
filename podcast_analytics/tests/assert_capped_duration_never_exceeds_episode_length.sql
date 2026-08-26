-- Fails if any row's capped duration exceeds the episode's actual length, which
-- would mean the least() logic in fct_listening_events was applied incorrectly.
select
    f.event_id,
    f.duration_capped_seconds,
    ep.duration_seconds as episode_duration_seconds
from {{ ref('fct_listening_events') }} f
join {{ ref('dim_episodes') }} ep on f.episode_id = ep.episode_id
where f.duration_capped_seconds > ep.duration_seconds