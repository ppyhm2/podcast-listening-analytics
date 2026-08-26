-- Analysis question:
-- Number of distinct users who listened to 3+ different episodes in one day

select count(distinct user_id) as users_3plus_episodes_in_a_day
from {{ ref('int_user_daily_activity') }}
where distinct_episodes >= 3


-- Finding: 72 of 400 users listened to 3+ distinct episodes on at least one day in
-- the dataset. This result is highly sensitive to how "listened" is defined (see
-- is_listen_event on fct_listening_events: play or complete only, excluding
-- pause/seek/download). Testing looser definitions during development showed this
-- figure ranges from 25 (play events only) to 173 (any event type counted), so it
-- should be read alongside that definition rather than as an absolute, objective
-- count.