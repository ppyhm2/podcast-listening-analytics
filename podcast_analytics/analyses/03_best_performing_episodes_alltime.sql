-- All-time version of the completion-event logic in 02, without the 7-day window.
-- Kept as its own file rather than editing 02 directly. Same caveat applies: this
-- counts completion events, not distinct listeners who completed.

select
    ep.episode_id,
    ep.title,
    count(*) as completion_events
from {{ ref('fct_listening_events') }} f
join {{ ref('dim_episodes') }} ep on f.episode_id = ep.episode_id
where f.event_type = 'complete'
group by 1, 2
order by completion_events desc, ep.episode_id asc
limit 10


-- Finding: Episode 84 tops the all-time ranking with 204 completions, followed by
-- Episode 95 (197) and Episode 71 (178). Episode 19, which leads the most recent
-- 7-day window, ranks only 7th here with 137 completions. Rather than indicating a
-- recent surge, this is consistent with the 7-day window simply being too small to
-- rank on: its leader has 8 completions against 204 across the full period.