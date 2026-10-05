"""Public API: generate a synthetic SOC event stream (normal baseline traffic
plus injected attack scenarios) as a single pandas DataFrame, ready to hand
to storage.db.write_events() or detection/.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

from . import scenarios as _scenarios
from .entities import COUNTRY_GEO, random_external_ip, random_user
from .events import business_hours_weight, emit_auth_event, emit_dns_event, emit_network_event, emit_process_event

EVENT_TYPE_WEIGHTS = {"auth": 0.22, "network": 0.45, "dns": 0.27, "process": 0.06}

# Each user has exactly one "home country" for the whole dataset — assigned
# once, on first use, and reused for every login of theirs after that
# (whether modeled as an on-site badge-in or a remote/VPN session). Without
# this, picking a fresh random country per login makes ordinary employees
# flip countries constantly, which is indistinguishable from the thing the
# impossible-travel rule exists to catch and floods it with false positives.
_user_home_country: dict[str, str] = {}


def _home_country_for(user: str) -> str:
    if user not in _user_home_country:
        others = [c for c in COUNTRY_GEO if c != "India"]
        _user_home_country[user] = "India" if random.random() < 0.88 else random.choice(others)
    return _user_home_country[user]


def _random_background_event(ts: datetime) -> dict:
    kind = random.choices(list(EVENT_TYPE_WEIGHTS), weights=list(EVENT_TYPE_WEIGHTS.values()))[0]
    if kind == "auth":
        user = random_user()
        country = _home_country_for(user)
        # ~15% of logins are remote/VPN (external IP) rather than an on-site
        # badge-in — but same home country either way, see above. ~3% of all
        # logins fail (typo'd passwords): a low baseline is what makes a
        # brute-force burst stand out.
        src_ip = random_external_ip().ip if random.random() < 0.15 else None
        outcome = "failure" if random.random() < 0.03 else "success"
        action = "login_failure" if outcome == "failure" else "login_success"
        return emit_auth_event(ts, user=user, src_ip=src_ip, src_country=country, action=action, outcome=outcome)
    if kind == "network":
        return emit_network_event(ts)
    if kind == "dns":
        return emit_dns_event(ts)
    return emit_process_event(ts)


def generate_background(start: datetime, end: datetime, base_per_hour: int = 35) -> list[dict]:
    """Normal, unremarkable traffic across [start, end), rate-shaped by
    business_hours_weight so nights/weekends are quiet but not silent."""
    events: list[dict] = []
    hour = start.replace(minute=0, second=0, microsecond=0)
    while hour < end:
        n = np.random.poisson(max(base_per_hour * business_hours_weight(hour), 0.5))
        for _ in range(int(n)):
            ts = hour + timedelta(seconds=random.randint(0, 3599))
            if start <= ts < end:
                events.append(_random_background_event(ts))
        hour += timedelta(hours=1)
    return events


def _random_anchor(start: datetime, end: datetime, tail_hours: float) -> datetime:
    """A start time at least an hour in, leaving `tail_hours` before `end` so
    the whole scenario (up to ~3h for beaconing, ~6h for a kill chain) fits."""
    span = int((end - start).total_seconds())
    latest = max(3601, span - int(tail_hours * 3600))
    return start + timedelta(seconds=random.randint(3600, latest))


def generate_dataset(
    start: datetime,
    end: datetime,
    base_per_hour: int = 35,
    scenario_count: int = 6,
    campaign_count: int = 1,
    seed: int = 42,
) -> pd.DataFrame:
    """The full synthetic dataset: background traffic, `scenario_count`
    standalone attack scenarios, and `campaign_count` multi-stage kill-chain
    campaigns layered on top. Returns a DataFrame sorted by timestamp, ready
    for storage.db.write_events()."""
    random.seed(seed)
    np.random.seed(seed)
    _user_home_country.clear()

    events = generate_background(start, end, base_per_hour=base_per_hour)

    for _ in range(scenario_count):
        builder = random.choice(_scenarios.STANDALONE_BUILDERS)
        instance = builder(_random_anchor(start, end, tail_hours=3))
        events.extend(_scenarios.stamp(instance, _scenarios.new_scenario_id()))

    for _ in range(campaign_count):
        events.extend(_scenarios.kill_chain_scenario(_random_anchor(start, end, tail_hours=7)))

    df = pd.DataFrame(events)
    df.sort_values("ts", inplace=True, kind="stable")
    df.reset_index(drop=True, inplace=True)
    return df
