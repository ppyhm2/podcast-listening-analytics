-- This query gives a summary of the podcasts and episodes (i.e. number of distinct episodes per podcast_id)
-- as well as the respective total number of episode completions and average completions per episode

with episode_completions as (

    select
        episode_id,
        count(*) as completion_events
    from {{ ref('fct_listening_events') }}
    where event_type = 'complete'
    group by 1

)

select
    ep.podcast_id,
    count(distinct ep.episode_id) as episode_count,

    -- coalesce so a podcast with zero completed episodes shows 0, not a missing row
    coalesce(sum(ec.completion_events), 0) as total_completions,

    -- Ranked on the AVERAGE per episode, not the raw total. Podcasts here range from
    -- 3 to 13 episodes — a raw sum would just reward podcasts with more episodes
    -- rather than genuinely higher-performing content, which isn't the same question.
    round(coalesce(sum(ec.completion_events), 0) * 1.0 / count(distinct ep.episode_id), 2) as avg_completions_per_episode

-- left join from dim_episodes (not from episode_completions) so every podcast
-- appears even if none of its episodes were ever completed.
from {{ ref('dim_episodes') }} ep
left join episode_completions ec on ep.episode_id = ec.episode_id
group by 1
order by avg_completions_per_episode desc

-- Finding: this proved material. The podcast with the highest raw total (615
-- completions across 13 episodes) ranks 13th by average, at 47.3 per episode.
-- The leader by average manages 97.0 per episode from a catalogue of just 3.
-- Ranking by total would have inverted the picture entirely.
--
-- The reverse bias is worth naming: ranking by average rewards small catalogues,
-- since a strong episode is not diluted across a large back catalogue. Neither
-- measure is fair alone, and a production version would likely apply a
-- minimum-episode threshold before ranking.