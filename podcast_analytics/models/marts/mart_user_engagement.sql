-- Kept separate from dim_users despite both being one row per user. Putting a user-level total on a dimension
-- causes fan-out the moment it's joined to the fact, since the total repeats across
-- every one of that user's event rows.

with events as (

    select
        f.user_id,
        f.event_date,
        f.is_listen_event,
        f.duration_capped_seconds,
        f.listen_through_rate,
        f.episode_id,
        ep.podcast_id
    from {{ ref('fct_listening_events') }} f
    left join {{ ref('dim_episodes') }} ep on f.episode_id = ep.episode_id

),

user_agg as (

    select
        user_id,

        -- Valid interactions of any event type. Named total_valid_events rather than
        -- total_events because rejected rows are excluded: this counts what reached the
        -- fact table, not what the source emitted.
        count(*) as total_valid_events,

        sum(case when is_listen_event then 1 else 0 end) as total_listen_events,

        -- is_listen_event = play or complete (defined in fct_listening_events).
        -- pause/seek are excluded here as elsewhere, since without session data linking
        -- them to a play they can't independently confirm a listen took place.
        -- nullif because count() returns 0, not null, for a user with events but no
        -- listens. Without it such a user is indistinguishable from one who listened
        -- to exactly zero podcasts by chance, and any downstream "is null" check for
        -- no-listen users silently misses them.
        nullif(count(distinct case when is_listen_event then episode_id end), 0) as distinct_episodes_listened,
        nullif(count(distinct case when is_listen_event then podcast_id end), 0) as distinct_podcasts_listened,

        -- Uses duration_capped_seconds, not the raw value, for consistency with every
        -- other duration metric in this project. Using raw here would silently
        -- reintroduce the >100%-listened problem.
        -- No "else 0": a user with no listens should read null here, consistent with
        -- the nullif on the counts above, rather than being indistinguishable from
        -- someone who listened for zero seconds.
        --
        -- Named for what it is. This is the sum of capped durations on listen events,
        -- not time spent listening: without session boundaries, true listening time is
        -- not derivable from this data.
        sum(case when is_listen_event then duration_capped_seconds end) as total_capped_listen_seconds,

        -- Reads listen_through_rate straight off the fact rather than re-deriving it.
        -- Note this is an unweighted mean of event-level ratios, so every listen event
        -- counts equally regardless of episode length. A ratio of summed durations
        -- would answer a different question (what share of available content was
        -- consumed) and would weight long episodes more heavily.
        avg(listen_through_rate) as avg_listen_through_rate,

        min(event_date) as first_event_date,

        -- Separate from first_event_date, which spans every event type. A user whose
        -- first interaction was a download or a seek has a first *listen* later than
        -- their first event, so days_to_first_listen must be built from this column
        -- rather than from first_event_date.
        min(case when is_listen_event then event_date end) as first_listen_date,

        max(event_date) as last_event_date,
        count(distinct event_date) as distinct_days_active

    from events
    group by 1

)

select
    u.user_id,
    u.country,
    u.signup_date,
    a.total_valid_events,
    a.total_listen_events,
    a.distinct_episodes_listened,
    a.distinct_podcasts_listened,
    a.total_capped_listen_seconds,
    a.avg_listen_through_rate,
    a.first_event_date,
    a.first_listen_date,
    a.last_event_date,
    a.distinct_days_active,
    date_diff('day', u.signup_date, a.first_listen_date) as days_to_first_listen,
    current_timestamp as data_refreshed_on

-- left join, not inner: every one of the 400 users appears here even if all of their
-- raw events happened to be rejected in staging. They show nulls across the activity
-- columns rather than silently disappearing from the mart entirely.
from {{ ref('dim_users') }} u
left join user_agg a on u.user_id = a.user_id