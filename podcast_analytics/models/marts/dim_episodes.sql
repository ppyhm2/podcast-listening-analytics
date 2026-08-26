select
    episode_id,
    podcast_id,
    title,
    release_date,
    duration_seconds,
    round(duration_seconds / 60.0, 1) as duration_minutes,
    date_part('year', release_date) as release_year,
    date_part('month', release_date) as release_month,

    -- Thresholds are provisional, chosen by eyeballing the episode duration
    -- distribution (mean ~45 min, range 6-87 min across the 200 episodes), not
    -- derived from any business definition. The buckets should be confirmed
    -- with a business stakeholder before being treated as canonical (e.g. in production),
    -- different thresholds would shift which episodes fall into which bucket and could
    -- change the avg_listen_through_rate_by_episode_length_bucket result.
    case
        when duration_seconds < 1200 then 'short'
        when duration_seconds < 2700 then 'medium'
        else 'long'
    end as episode_length_bucket,

    current_timestamp as data_refreshed_on
from {{ ref('stg_episodes') }}