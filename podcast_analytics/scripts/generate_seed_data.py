"""
Generate synthetic podcast interaction data for the analytics project.

Produces three CSVs (users, episodes, event_logs) with deliberately injected
data quality problems, so the transformation and validation layers have
something real to handle.

Deterministic: the same SEED always produces the same dataset.

Usage:  python generate_seed_data.py [output_dir]
"""

import csv
import os
import random
import sys
from datetime import date, datetime, timedelta

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SEED = 20240421

N_USERS = 400
N_EPISODES = 200
N_PODCASTS = 30
N_EVENTS = 40000

# Users sign up across 2024-25; events run through 2025 into early 2026, so
# signup dates overlap the event window and cohort analysis is possible.
SIGNUP_START = date(2024, 6, 1)
SIGNUP_END = date(2025, 12, 31)
EVENT_START = datetime(2025, 1, 1)
EVENT_END = datetime(2026, 2, 28, 23, 59, 59)

COUNTRY_WEIGHTS = {
    "UK": 22,
    "IE": 14,
    "ES": 13,
    "NL": 12,
    "SE": 11,
    "PL": 10,
    "IT": 10,
    "BR": 8,
}

# "download" is an interaction but NOT a listen: it records intent to consume
# later, not consumption itself. It carries no duration, and is excluded from
# is_listen_event downstream.
EVENT_TYPES = ["play", "pause", "seek", "complete", "download"]
EVENT_TYPE_WEIGHTS = [24, 23, 23, 24, 6]

# Episode lengths, in seconds. Wide spread so the length buckets in
# dim_episodes (short <20min, medium 20-45min, long 45min+) are all populated.
EPISODE_DURATION_MIN = 348
EPISODE_DURATION_MAX = 5259

# --- Injected data quality problems ---------------------------------------
# Counts, not rates, so the totals are predictable.
N_MISSING_USER_ID = 471
N_MISSING_EPISODE_ID = 358
N_MISSING_EVENT_TYPE = 202
N_MISSING_TIMESTAMP = 154
N_MALFORMED_TIMESTAMP = 73
N_MISSING_DURATION = 118

# Rows deliberately given a second, overlapping problem, so rejection
# reasons are not mutually exclusive.
N_DOUBLE_FAULT = 136

MALFORMED_TIMESTAMP_VALUE = "malformed-date"

# --- Listening behaviour ---------------------------------------------------
# Probability a play/complete event records a duration longer than the
# episode itself. Higher for short episodes, which are easier to overrun.
EXCEED_PROB = {"short": 0.85, "medium": 0.52, "long": 0.24}

# Multiplier applied when a duration overruns the episode length.
EXCEED_MULTIPLIER_MIN = 1.02
EXCEED_MULTIPLIER_MAX = 15.4

# Every show carries at least this many episodes, so per-episode averages
# are not dominated by shows with a single lucky episode.
MIN_EPISODES_PER_PODCAST = 3

# Listener loyalty. Each user favours one or two shows and returns to them
# with probability drawn from this beta, so the population contains genuinely
# loyal listeners alongside people who graze across the catalogue.
LOYALTY_BETA = (1.5, 2.2)
P_TWO_FAVOURITES = 0.35

# Beta distribution shape for genuine (non-overrun) listen-through rates,
# per bucket. Tuned so average listen-through by bucket is monotonic.
LTR_BETA = {"short": (5.0, 2.6), "medium": (4.8, 2.6), "long": (2.7, 2.9)}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def opaque_id(rng, prefix, seen):
    """Non-sequential identifier. Sequential IDs leak creation order and
    approximate volume, and collide awkwardly if data is ever merged across
    systems, so identifiers here carry no information beyond identity."""
    while True:
        candidate = f"{prefix}_{rng.getrandbits(40):010x}"
        if candidate not in seen:
            seen.add(candidate)
            return candidate


def length_bucket(duration_seconds):
    if duration_seconds < 1200:
        return "short"
    if duration_seconds < 2700:
        return "medium"
    return "long"


def random_date(rng, start, end):
    return start + timedelta(days=rng.randint(0, (end - start).days))


def random_datetime(rng, start, end):
    delta = int((end - start).total_seconds())
    return start + timedelta(seconds=rng.randint(0, delta))


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

def generate_users(rng):
    countries = list(COUNTRY_WEIGHTS.keys())
    weights = list(COUNTRY_WEIGHTS.values())
    users = []
    seen = set()
    for _ in range(N_USERS):
        users.append(
            {
                "user_id": opaque_id(rng, "usr", seen),
                "signup_date": random_date(rng, SIGNUP_START, SIGNUP_END).isoformat(),
                "country": rng.choices(countries, weights=weights, k=1)[0],
            }
        )
    return users


def generate_episodes(rng):
    # Uneven catalogue sizes, so podcast-level averages differ from totals and
    # ranking by total episodes rewards catalogue size rather than quality.
    sizes = [MIN_EPISODES_PER_PODCAST] * N_PODCASTS
    for _ in range(N_EPISODES - MIN_EPISODES_PER_PODCAST * N_PODCASTS):
        sizes[int(rng.betavariate(1.4, 2.6) * N_PODCASTS)] += 1
    rng.shuffle(sizes)

    podcast_seen = set()
    assignments = []
    for size in sizes:
        podcast_id = opaque_id(rng, "pod", podcast_seen)
        assignments.extend([podcast_id] * size)
    rng.shuffle(assignments)

    episode_seen = set()
    episodes = []
    for i in range(1, N_EPISODES + 1):
        episodes.append(
            {
                "episode_id": opaque_id(rng, "epi", episode_seen),
                "podcast_id": assignments[i - 1],
                "title": f"Episode {i}",
                "release_date": random_date(rng, SIGNUP_START, SIGNUP_END).isoformat(),
                "duration_seconds": rng.randint(
                    EPISODE_DURATION_MIN, EPISODE_DURATION_MAX
                ),
            }
        )
    return episodes


def generate_events(rng, users, episodes):
    episode_lookup = {e["episode_id"]: e for e in episodes}
    user_ids = [u["user_id"] for u in users]
    users_by_id = {u["user_id"]: u for u in users}
    episode_ids = [e["episode_id"] for e in episodes]

    # Skew listening so some users and episodes are far more active than
    # others, rather than everything being uniform.
    # Lognormal rather than Pareto: gives a realistic long tail without a
    # single user or episode absorbing most of the dataset.
    # A user cannot listen before signing up, so their active window runs from
    # their signup date (or the start of the event period, whichever is later).
    # Weighting by window length means late joiners naturally have fewer events.
    windows = {}
    for u in users:
        signup = datetime.combine(date.fromisoformat(u["signup_date"]), datetime.min.time())
        windows[u["user_id"]] = max(signup, EVENT_START)

    total_span = (EVENT_END - EVENT_START).total_seconds()
    user_weights = [
        rng.lognormvariate(0, 0.7)
        * max(0.02, (EVENT_END - windows[u]).total_seconds() / total_span)
        for u in user_ids
    ]
    episode_weights = [rng.lognormvariate(0, 0.8) for _ in episode_ids]

    episodes_by_podcast = {}
    for e in episodes:
        episodes_by_podcast.setdefault(e["podcast_id"], []).append(e["episode_id"])
    podcast_ids = list(episodes_by_podcast)

    # Per-user affinity: favourite shows plus how often they return to them.
    affinity = {}
    for user_id in user_ids:
        n_favourites = 2 if rng.random() < P_TWO_FAVOURITES else 1
        favourites = rng.sample(podcast_ids, n_favourites)
        loyalty = rng.betavariate(*LOYALTY_BETA)
        pool = [ep for pod in favourites for ep in episodes_by_podcast[pod]]
        affinity[user_id] = (loyalty, pool)

    events = []
    for _ in range(N_EVENTS):
        user_id = rng.choices(user_ids, weights=user_weights, k=1)[0]

        loyalty, favourite_pool = affinity[user_id]
        if rng.random() < loyalty:
            episode_id = rng.choice(favourite_pool)
        else:
            episode_id = rng.choices(episode_ids, weights=episode_weights, k=1)[0]
        event_type = rng.choices(EVENT_TYPES, weights=EVENT_TYPE_WEIGHTS, k=1)[0]
        timestamp = random_datetime(rng, windows[user_id], EVENT_END)

        duration = None
        if event_type in ("play", "complete"):
            episode_length = episode_lookup[episode_id]["duration_seconds"]
            bucket = length_bucket(episode_length)

            if rng.random() < EXCEED_PROB[bucket]:
                multiplier = rng.uniform(
                    EXCEED_MULTIPLIER_MIN, EXCEED_MULTIPLIER_MAX
                )
                duration = int(episode_length * multiplier)
            else:
                alpha, beta = LTR_BETA[bucket]
                rate = rng.betavariate(alpha, beta)
                duration = max(1, int(episode_length * rate))

        events.append(
            {
                "event_type": event_type,
                "user_id": user_id,
                "episode_id": episode_id,
                "timestamp": timestamp.strftime("%Y-%m-%dT%H:%M:%S"),
                "duration": duration,
            }
        )

    return events


def inject_faults(rng, events):
    """Blank out or corrupt selected fields, in place."""
    indices = list(range(len(events)))
    rng.shuffle(indices)
    cursor = 0

    def take(n):
        nonlocal cursor
        chunk = indices[cursor : cursor + n]
        cursor += n
        return chunk

    # Primary faults, each on a distinct row.
    for i in take(N_MISSING_USER_ID):
        events[i]["user_id"] = None
    for i in take(N_MISSING_EPISODE_ID):
        events[i]["episode_id"] = None
    for i in take(N_MISSING_EVENT_TYPE):
        events[i]["event_type"] = None
    for i in take(N_MISSING_TIMESTAMP):
        events[i]["timestamp"] = None
    for i in take(N_MALFORMED_TIMESTAMP):
        events[i]["timestamp"] = MALFORMED_TIMESTAMP_VALUE

    # Rows that need a play/complete event type to have a missing duration
    # be meaningful at all.
    missing_duration_done = 0
    while missing_duration_done < N_MISSING_DURATION and cursor < len(indices):
        i = indices[cursor]
        cursor += 1
        if events[i]["event_type"] in ("play", "complete"):
            events[i]["duration"] = None
            missing_duration_done += 1

    # Secondary faults layered onto rows that already have one, so some
    # rows fail more than a single check.
    already_faulty = [
        i
        for i in indices[:cursor]
        if events[i]["user_id"] is None
        or events[i]["episode_id"] is None
        or events[i]["event_type"] is None
    ]
    rng.shuffle(already_faulty)
    for i in already_faulty[:N_DOUBLE_FAULT]:
        if rng.random() < 0.5:
            events[i]["timestamp"] = MALFORMED_TIMESTAMP_VALUE
        else:
            events[i]["timestamp"] = None

    return events


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def write_csv(path, fieldnames, rows, quote_all=False):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            quoting=csv.QUOTE_ALL if quote_all else csv.QUOTE_MINIMAL,
            lineterminator="\r\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow({k: ("" if v is None else v) for k, v in row.items()})


def summarise(events, episodes):
    episode_lookup = {e["episode_id"]: e for e in episodes}

    total = len(events)
    rejected = sum(
        1
        for e in events
        if e["user_id"] is None
        or e["episode_id"] is None
        or e["event_type"] is None
        or e["timestamp"] is None
        or e["timestamp"] == MALFORMED_TIMESTAMP_VALUE
        or (e["event_type"] in ("play", "complete") and e["duration"] is None)
    )

    listens = [
        e
        for e in events
        if e["event_type"] in ("play", "complete")
        and e["duration"] is not None
        and e["episode_id"] is not None
    ]
    exceeded = [
        e
        for e in listens
        if e["duration"] > episode_lookup[e["episode_id"]]["duration_seconds"]
    ]

    by_bucket = {}
    for e in listens:
        length = episode_lookup[e["episode_id"]]["duration_seconds"]
        bucket = length_bucket(length)
        capped = min(e["duration"], length)
        by_bucket.setdefault(bucket, []).append(capped / length)

    overall = [
        min(e["duration"], episode_lookup[e["episode_id"]]["duration_seconds"])
        / episode_lookup[e["episode_id"]]["duration_seconds"]
        for e in listens
    ]

    print(f"  events                {total}")
    print(f"  rejected              {rejected} ({rejected / total:.1%})")
    print(
        f"  duration overruns     {len(exceeded)} of {len(listens)} listens "
        f"({len(exceeded) / len(listens):.1%})"
    )
    print(f"  avg listen-through    {sum(overall) / len(overall):.3f}")
    for bucket in ("short", "medium", "long"):
        rates = by_bucket.get(bucket, [])
        if rates:
            print(
                f"    {bucket:<8} {sum(rates) / len(rates):.3f}  ({len(rates)} listens)"
            )


def main():
    output_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(output_dir, exist_ok=True)

    rng = random.Random(SEED)

    users = generate_users(rng)
    episodes = generate_episodes(rng)
    events = inject_faults(rng, generate_events(rng, users, episodes))

    write_csv(
        os.path.join(output_dir, "users.csv"),
        ["user_id", "signup_date", "country"],
        users,
    )
    write_csv(
        os.path.join(output_dir, "episodes.csv"),
        ["episode_id", "podcast_id", "title", "release_date", "duration_seconds"],
        episodes,
    )
    write_csv(
        os.path.join(output_dir, "event_logs.csv"),
        ["event_type", "user_id", "episode_id", "timestamp", "duration"],
        events,
        quote_all=True,
    )

    print(f"Written to {os.path.abspath(output_dir)}")
    summarise(events, episodes)


if __name__ == "__main__":
    main()
