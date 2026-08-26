-- Fails if the valid and rejected row counts don't sum to the staged row count,
-- proof that no row is silently lost or duplicated between staging and the
-- fact/rejected split. Staging is the denominator rather than the raw seed
-- because deduplication happens there by design: raw rows that are identical
-- in every field collapse to a single event_id, and that difference is
-- reported in the data quality summary rather than hidden here.
with counts as (
    select
        (select count(*) from {{ ref('stg_event_logs') }}) as total_staged,
        (select count(*) from {{ ref('fct_listening_events') }}) as total_valid,
        (select count(*) from {{ ref('rejected_event_logs') }}) as total_rejected
)
select *
from counts
where total_staged != total_valid + total_rejected