with source as (

    select
        event_type,
        user_id,
        episode_id,
        "timestamp" as event_timestamp_raw,
        duration
    from {{ ref('event_logs') }}

    -- we use ref instead of source since we're using seeds instead of a table on a database

),

flagged as (

    select
        -- Hashed on the raw, unprocessed values, before try_cast runs on the
        -- timestamp. The reason is because a row's identity shouldn't depend on whether it happened to
        -- parse successfully — two rows with identical raw content always get the
        -- same event_id regardless of what downstream cleaning does to them.
        -- On the seed files, event_logs has no natural key of its own, unlike users/episodes.
        -- try_cast() is used since we have 'malformed-date' in the timestamp and a normal cast()
        -- would throw an error; in these cases we want to have it set up null instead or erroring.
        -- Where we know there are data issues e.g. non-standard data types present, we use try_cast()
        -- otherwise we use regular cast()
        {{ dbt_utils.generate_surrogate_key(['event_type', 'user_id', 'episode_id', 'event_timestamp_raw', 'duration']) }} as event_id,
        event_type,
        user_id,
        episode_id,
        event_timestamp_raw,
        try_cast(event_timestamp_raw as timestamp) as event_datetime,
        duration,
        (event_type is null) as is_missing_event_type,
        (user_id is null) as is_missing_user_id,
        (episode_id is null) as is_missing_episode_id,
        (event_timestamp_raw is null) as is_missing_timestamp,
        (event_timestamp_raw is not null and try_cast(event_timestamp_raw as timestamp) is null) as is_malformed_timestamp,
        coalesce(event_type in ('play', 'complete') and duration is null, false) as is_missing_duration
    from source

)

select
    *,

    -- boolean on any rejected rows so it can be easily filtered
    (
        is_missing_event_type or is_missing_user_id or is_missing_episode_id
        or is_missing_timestamp or is_malformed_timestamp or is_missing_duration
    ) as is_rejected,

    -- Counts how many checks failed, not just whether any did. 134 rows fail two
    -- checks simultaneously (e.g. blank user_id AND a malformed timestamp) — this
    -- keeps that visible rather than losing it behind a single reason label.
    (
        case when is_missing_event_type then 1 else 0 end
        + case when is_missing_user_id then 1 else 0 end
        + case when is_missing_episode_id then 1 else 0 end
        + case when is_missing_timestamp then 1 else 0 end
        + case when is_malformed_timestamp then 1 else 0 end
        + case when is_missing_duration then 1 else 0 end
    ) as rejection_reason_count,

    -- Human-readable summary derived FROM the boolean flags above, never entered
    -- independently, so the two can never disagree. Flags are for querying/testing
    -- (clean aggregation, e.g. count(*) where is_malformed_timestamp); this is for
    -- someone skimming the table directly without wanting to parse six booleans.
    concat_ws(', ',
        case when is_missing_event_type then 'missing_event_type' end,
        case when is_missing_user_id then 'missing_user_id' end,
        case when is_missing_episode_id then 'missing_episode_id' end,
        case when is_missing_timestamp then 'missing_timestamp' end,
        case when is_malformed_timestamp then 'malformed_timestamp' end,
        case when is_missing_duration then 'missing_duration' end
    ) as rejection_reason_summary
from flagged

-- Two raw rows can be identical in every field (same user, episode, event type,
-- timestamp to the second, and no duration on pause/seek/download). Hashing
-- content means they collapse to one event_id, so they are genuinely
-- indistinguishable rather than merely similar. Keeping one is the only
-- defensible choice here; the real fix is upstream, where the source system
-- should emit its own event identifier rather than identity being derived
-- from content.
-- The ordering is arbitrary by design: the rows within a partition are identical in
-- every column, so there is nothing to prefer between them.
qualify row_number() over (partition by event_id order by event_id) = 1