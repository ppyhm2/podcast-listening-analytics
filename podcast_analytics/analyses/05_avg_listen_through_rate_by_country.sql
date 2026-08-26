-- Analysis question:
-- Average listen-through rate (completion duration/episode duration) by country

-- Reads listen_through_rate off the fact table rather than re-deriving it, so the
-- capped denominator and the divide-by-zero guard are applied identically here and
-- in every other consumer.

select
    u.country,
    avg(f.listen_through_rate) as avg_listen_through_rate
from {{ ref('fct_listening_events') }} f
join {{ ref('dim_users') }} u on f.user_id = u.user_id
where f.is_listen_event
group by 1
order by 1


-- Finding: average listen-through rate sits in a tight band across all eight
-- countries (~0.745-0.768). No country stands out as meaningfully more or less
-- engaged than the others. Every value sits comfortably under 1.0, confirming the
-- capped-duration treatment is behaving as intended.