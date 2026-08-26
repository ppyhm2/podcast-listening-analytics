-- Fails if any row landed in rejected_event_logs without at least one rejection
-- flag set to true. This would mean a row was rejected for a reason the current
-- checks don't capture.
select *
from {{ ref('rejected_event_logs') }}
where rejection_reason_count = 0