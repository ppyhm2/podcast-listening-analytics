-- Analysis question:
-- The 10 episodes with the most completion events in the most recent 7 days
--
-- Note the metric is completion EVENTS, not distinct listeners who completed. A
-- user-episode pair can carry more than one 'complete', and without session data
-- there is no way to tell a genuine re-listen from a duplicate. Counting
-- events is the honest reading of what the source records; counting distinct users
-- would answer a different and arguably more useful question, and is a one-line
-- change if that is what a stakeholder wants.

with max_date as (

    -- Anchored to the data's own max date rather than a hardcoded date, so this
    -- stays correct if re-run against a different or growing dataset.
    select max(event_date) as max_event_date
    from {{ ref('fct_listening_events') }}

),

recent_events as (

    -- 6 days back from the max date = 7 days inclusive.
    select f.*
    from {{ ref('fct_listening_events') }} f, max_date m
    where f.event_date >= m.max_event_date - interval '6 days'

),

completions as (

    select
        episode_id,
        count(*) as completion_events
    from recent_events
    where event_type = 'complete'
    group by 1

)

select
    ep.episode_id,
    ep.title,
    c.completion_events
from completions c
join {{ ref('dim_episodes') }} ep on c.episode_id = ep.episode_id

-- episode_id as a secondary sort key makes ties deterministic. Without it, which
-- episode lands in the final spot(s) can change between runs even though the data
-- hasn't changed (confirmed firsthand, before this was added).
order by c.completion_events desc, ep.episode_id asc
limit 10


-- Finding: Episode 19 leads with 8 completions. Ties matter more here than they
-- might appear: positions 5 through 10 are all tied at 4 completions, so which six
-- episodes occupy those places is arbitrary beyond the sort key. The counts in a
-- 7-day window over this dataset are too small to rank confidently below the top
-- few, and this episode ranks only 7th all-time (see 03), so the two windows
-- disagree. The all-time view is the more reliable signal.