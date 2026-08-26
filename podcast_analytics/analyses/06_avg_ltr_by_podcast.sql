-- Same logic as 05 (avg listen-through rate, using the capped duration for
-- consistency), grouped by podcast instead of country.

select
    ep.podcast_id,
    avg(f.listen_through_rate) as avg_listen_through_rate
from {{ ref('fct_listening_events') }} f
join {{ ref('dim_episodes') }} ep on f.episode_id = ep.episode_id
where f.is_listen_event
group by 1
order by 2 desc


-- Finding: the top podcast averages 0.908, clear of the next at 0.869. This is
-- likely explained by episode length rather than content quality alone (see 07):
-- its episodes average 13.7 minutes against a catalogue-wide mean of 45.1 minutes,
-- making it by far the shortest in the catalogue.
--
-- Caveat: the length/listen-through link this leans on is largely an artefact of the
-- capping rule (see 11). The honest reading is that this podcast's short episodes
-- trigger capping more often, not that they are more completely consumed.