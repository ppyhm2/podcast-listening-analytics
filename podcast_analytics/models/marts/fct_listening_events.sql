with valid_events as (

    -- Only rows that passed every validity check in stg_event_logs. Rejected rows
    -- live separately in rejected_event_logs rather than being silently dropped.
    select *
    from {{ ref('stg_event_logs') }}
    where not is_rejected

),

joined as (

    select
        e.event_id,
        e.user_id,
        e.episode_id,
        e.event_type,
        e.event_datetime,
        cast(e.event_datetime as date) as event_date,
        date_part('year', e.event_datetime) as event_year,
        date_part('month', e.event_datetime) as event_month,
        date_part('hour', e.event_datetime) as event_hour_of_day,
        dayname(e.event_datetime) as event_day_of_week,

        -- Original, untouched listen duration. Retained for audit purposes only,
        -- never used directly in any calculation. See duration_capped_seconds below.
        e.duration as duration_raw_seconds,

        -- 47% of play/complete rows have a raw duration exceeding the episode's own
        -- length (up to 15.4x over), possible reasons could be due to ad insertion, replays being
        -- counted cumulatively. The synthetic data can't confirm which.
        -- least() caps the value at the episode's length so
        -- downstream metrics (e.g. listen-through rate) never exceed 100%. This is
        -- the ONLY duration field that should feed any aggregate or rate calculation.
        --
        -- The explicit null guard matters: least() IGNORES nulls in DuckDB, so
        -- least(null, 1800) returns 1800, not null. Without it, every pause, seek and
        -- download row (which carry no duration) would silently claim a full-episode
        -- listen. Same three-valued-logic trap described for
        -- duration_exceeds_episode_length below, and it bites here too.
        case
            when e.duration is null then null
            else least(e.duration, ep.duration_seconds)
        end as duration_capped_seconds,

        -- pause/seek events have no duration recorded (duration is null for them).
        -- In SQL, comparing null to a number (e.g. null > 1800) doesn't give false,
        -- it gives null, meaning "unknown", not a real answer. So without the
        -- "duration is not null" check below, every pause/seek row would end up
        -- with null in this column instead of a proper true or false. That's a
        -- problem because a null can quietly slip through filters later on, e.g.
        -- "where not duration_exceeds_episode_length" would NOT catch these rows,
        -- since "not null" is still null, not true. Checking "duration is not
        -- null" first guarantees this column is always a real true/false, never
        -- null, so nothing can silently disappear from a filter downstream.
        (e.duration is not null and e.duration > ep.duration_seconds) as duration_exceeds_episode_length,

        -- "Listened" = play or complete. pause/seek/download are excluded: without session
        -- data linking them to a play, a lone pause or seek can't independently
        -- confirm a listen happened (events here are independent and may be not reflective of a session.
        -- Defined once here so every downstream model references
        -- this column rather than re-implementing the definition and risking two
        -- definitions silently diverging.
        -- download is excluded since it signals intent to download rather than a listen/consumption
        (e.event_type in ('play', 'complete')) as is_listen_event,

        -- An event cannot happen before the episode exists, yet ~21% of valid events
        -- are dated before their episode's release_date. Flagged rather than rejected.
        (e.event_datetime is not null
            and ep.release_date is not null
            and cast(e.event_datetime as date) < ep.release_date) as is_before_episode_release,

        -- The denominator is carried onto the fact so listen-through rate can be
        -- computed here once, rather than every consumer re-joining dim_episodes and
        -- re-deriving the ratio. Four hand-written copies is how the divide-by-zero
        -- guard ends up in one of them and not the other three.
        ep.duration_seconds as episode_duration_seconds,

        current_timestamp as data_refreshed_on
    from valid_events e
    left join {{ ref('dim_episodes') }} ep on e.episode_id = ep.episode_id

)

select
    *,

    -- Listen-through rate, derived from the columns above rather than recomputing
    -- least() and the play/complete predicate. Referencing them is the point: an
    -- earlier version of this file recomputed both here, which is precisely the
    -- duplication the staging-to-marts structure exists to prevent, just at a
    -- smaller scale than doing it in four separate analyses.
    --
    -- nullif guards against a future episode loaded with a zero-second duration.
    -- Null for non-listen events, which carry no duration.
    case
        when is_listen_event
        then duration_capped_seconds * 1.0 / nullif(episode_duration_seconds, 0)
    end as listen_through_rate
from joined