-- Same logic as 05, grouped by the episode_length_bucket thresholds defined on
-- dim_episodes (short/medium/long, currently provisional pending business
-- sign-off, as already flagged on that model).

select
    ep.episode_length_bucket,
    avg(f.listen_through_rate) as avg_listen_through_rate
from {{ ref('fct_listening_events') }} f
join {{ ref('dim_episodes') }} ep on f.episode_id = ep.episode_id
where f.is_listen_event
group by 1

-- Ordered explicitly short/medium/long rather than alphabetically (which would give
-- long, medium, short), since the bucket has a natural logical order worth preserving.
order by
    case episode_length_bucket
        when 'short' then 1
        when 'medium' then 2
        when 'long' then 3
    end


-- Finding: a clear correlation between length and LTR. Short episodes average 0.95,
-- medium 0.83, long 0.61. Shorter content is more fully consumed. This directly
-- explains the podcast topping the podcast-level ranking in 06: its episodes are
-- the shortest in the catalogue by a wide margin.