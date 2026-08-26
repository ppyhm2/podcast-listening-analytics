-- This script shows a summary of the overall data quality

select
    'total_raw_events' as metric, count(*) as value from {{ ref('event_logs') }}
union all
select
    'duplicate_events_removed',
    (select count(*) from {{ ref('event_logs') }})
    - (select count(*) from {{ ref('stg_event_logs') }})
union all
select
    'staged_events', count(*) from {{ ref('stg_event_logs') }}
union all
select
    'valid_events', count(*) from {{ ref('fct_listening_events') }}
union all
select
    'rejected_events', count(*) from {{ ref('rejected_event_logs') }}
union all
select
    'missing_event_type', count(*) from {{ ref('rejected_event_logs') }} where is_missing_event_type
union all
select
    'missing_user_id', count(*) from {{ ref('rejected_event_logs') }} where is_missing_user_id
union all
select
    'missing_episode_id', count(*) from {{ ref('rejected_event_logs') }} where is_missing_episode_id
union all
select
    'missing_timestamp', count(*) from {{ ref('rejected_event_logs') }} where is_missing_timestamp
union all
select
    'malformed_timestamp', count(*) from {{ ref('rejected_event_logs') }} where is_malformed_timestamp
union all
select
    'missing_duration', count(*) from {{ ref('rejected_event_logs') }} where is_missing_duration
union all
-- Not a rejection reason: these rows are valid and usable, but an event cannot
-- occur before its episode exists, so the count is reported here alongside the
-- rejection breakdown rather than buried.
select
    'valid_events_before_episode_release',
    count(*) from {{ ref('fct_listening_events') }} where is_before_episode_release


-- Finding: 1,374 of 39,998 staged events (3.4%) were rejected: 469 missing user_id,
-- 358 missing episode_id, 202 missing event_type, 218 missing timestamp, 143 malformed
-- timestamps, and 118 missing duration on play/complete events. These sum to 1,508
-- rather than 1,374 because 134 rows fail more than one check simultaneously (see
-- rejection_reason_count on rejected_event_logs).
--
-- A further 2 rows were removed before staging as exact duplicates. Both carried a
-- blank user_id AND a blank timestamp, and the missing_user_id and missing_timestamp
-- counts each fall by exactly 2 as a result. That is not coincidence: blanking a field
-- removes one of the values distinguishing one row from another, so rows with multiple
-- nulls collide on a content-derived hash far more readily than clean rows do.
--
-- Separately, 8,045 valid events (20.8%) are dated before their episode's
-- release_date, which is impossible in reality (remembering
-- that the dataset produced here is synthetic). These are flagged on the fact table
-- rather than rejected: unlike a missing identifier the row is still usable, and
-- excluding a fifth of the dataset would be a far larger intervention than the
-- anomaly warrants. Reported here so it is visible rather than buried.
--
-- Note what this rate does and does not tell you. 3.4% of staged events are excluded
-- from the analytical models. Whether that exclusion biases the results is a separate
-- question, depending on whether rejected rows cluster by country, event type, date or
-- episode. That is checkable against rejected_event_logs but is not analysed here.