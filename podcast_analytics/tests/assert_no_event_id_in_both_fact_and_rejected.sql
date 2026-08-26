-- Fails if the same event_id appears in both fct_listening_events and
-- rejected_event_logs. Every event should be classified as exactly one or the
-- other, never both.
select event_id
from {{ ref('fct_listening_events') }}
intersect
select event_id
from {{ ref('rejected_event_logs') }}