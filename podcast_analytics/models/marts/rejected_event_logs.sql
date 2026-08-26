-- Deliberately a pure filter: every flag, count, and summary column here was already
-- computed once in stg_event_logs (see that file for the reasoning behind each one).
-- This file is for audit, keeping the rejection information centralised in a single place rather than duplicated.

select
    event_id,
    event_type,
    user_id,
    episode_id,
    event_timestamp_raw,
    duration,
    is_missing_event_type,
    is_missing_user_id,
    is_missing_episode_id,
    is_missing_timestamp,
    is_malformed_timestamp,
    is_missing_duration,
    rejection_reason_count,
    rejection_reason_summary
from {{ ref('stg_event_logs') }}
where is_rejected