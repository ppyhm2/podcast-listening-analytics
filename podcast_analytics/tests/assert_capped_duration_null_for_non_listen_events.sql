-- Fails if duration_capped_seconds is populated for an event that is not a listen,
-- or null for one that is.
--
-- This guards a specific trap: least() ignores nulls in DuckDB, so least(null, 1800)
-- returns 1800 rather than null. Without the explicit guard in fct_listening_events,
-- every pause, seek and download row would silently claim a full-episode listen.
-- assert_capped_duration_never_exceeds_episode_length cannot catch that, because the
-- episode's own length does not exceed itself.
select event_id
from {{ ref('fct_listening_events') }}
where (is_listen_event and duration_capped_seconds is null)
   or (not is_listen_event and duration_capped_seconds is not null)
