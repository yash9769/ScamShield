"""A streaming simulation of the detection pipeline.

The batch pipeline sees the whole dataset at once. A SOC does not: events
arrive, rules run on what has arrived so far, and anomaly scoring can only
judge an hour once it has closed. This module replays that:

* a simulated clock advances in steps; each step emits background traffic
  for the slice it covers, and occasionally starts an attack scenario whose
  events are then released as the clock reaches them;
* rules run on a rolling buffer (long enough for every rule's window), and
  every step re-runs them over activity they have already alerted on. An
  alert is new only if the event that triggered it is not already evidence
  in an earlier alert from the same rule on the same entity. Keying on the
  first event alone is not enough: once that event slides out of the
  buffer, the leftover events re-match with a different "first" event;
* anomaly scoring uses a model trained on the stored history (fit once,
  `anomaly.fit_model`) and scores each host-hour as it closes.

Every injected scenario is tracked, so the monitor can show live recall:
what was injected, what was caught, and how long after it started.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from datetime import datetime, timedelta

import pandas as pd

from .detection import anomaly, rule_engine
from .generator import generate_background
from .generator import scenarios as _scenarios

BUFFER = timedelta(minutes=90)  # longer than any rule window (30 min) plus slack
ANOMALY_BUDGET_PER_HOUR = 2     # alerts raised per closed hour, at most


@dataclass
class Injection:
    scenario_id: str
    tag: str
    started: datetime
    detected_at: datetime | None = None
    detected_by: str | None = None


@dataclass
class LiveSimulator:
    start: datetime
    base_per_hour: int = 35
    attack_probability: float = 0.15   # chance per step that a new attack starts
    model: object | None = None        # a fitted IsolationForest, or None to skip anomaly scoring
    high_cut: float | None = None
    rules: list[dict] = field(default_factory=rule_engine.load_rules)
    seed: int | None = None

    def __post_init__(self) -> None:
        self.rng = random.Random(self.seed)
        self.clock = self.start
        self.buffer = pd.DataFrame()
        self.hour_events: list[dict] = []      # current, still-open hour
        self.pending: list[dict] = []          # scenario events not yet reached
        self.alerts: list[dict] = []
        self.signatures: set[tuple] = set()
        self.covered: dict[tuple, set[str]] = {}   # (rule, entity) -> event ids already alerted on
        self.injections: dict[str, Injection] = {}
        self.scenario_of_event: dict[str, str] = {}  # answer key, never shown to the detectors
        self.per_minute: dict[pd.Timestamp, int] = {}
        self.event_total = 0

    # --- stream -----------------------------------------------------------
    def _inject(self) -> None:
        builder = self.rng.choice(_scenarios.STANDALONE_BUILDERS)
        scenario_id = _scenarios.new_scenario_id("live")
        events = _scenarios.stamp(builder(self.clock + timedelta(seconds=self.rng.randint(0, 59))), scenario_id)
        tag = events[0].get("scenario_tag") or builder.__name__.removesuffix("_scenario")
        self.injections[scenario_id] = Injection(scenario_id, tag, min(e["ts"] for e in events))
        self.scenario_of_event.update((e["event_id"], scenario_id) for e in events)
        self.pending.extend(events)

    def _release(self, until: datetime) -> list[dict]:
        due = [e for e in self.pending if e["ts"] < until]
        self.pending = [e for e in self.pending if e["ts"] >= until]
        return due

    def step(self, minutes: int = 5) -> list[dict]:
        """Advance the clock; returns the alerts raised during this step."""
        end = self.clock + timedelta(minutes=minutes)
        if self.rng.random() < self.attack_probability:
            self._inject()
        new = generate_background(self.clock, end, base_per_hour=self.base_per_hour) + self._release(end)
        new.sort(key=lambda e: e["ts"])
        raised: list[dict] = []

        # An hour boundary inside this step closes the hour: score it first.
        boundary = end.replace(minute=0, second=0, microsecond=0)
        if boundary > self.clock:
            self.hour_events.extend(e for e in new if e["ts"] < boundary)
            raised += self._score_closed_hour(boundary)
            self.hour_events = [e for e in new if e["ts"] >= boundary]
        else:
            self.hour_events.extend(new)

        for event in new:
            minute = pd.Timestamp(event["ts"]).floor("min")
            self.per_minute[minute] = self.per_minute.get(minute, 0) + 1
        self.event_total += len(new)

        frame = pd.DataFrame(new)
        self.buffer = pd.concat([self.buffer, frame], ignore_index=True) if not self.buffer.empty else frame
        if not self.buffer.empty:
            self.buffer = self.buffer[self.buffer["ts"] >= end - BUFFER].reset_index(drop=True)
            raised += self._run_rules(end)

        self.clock = end
        self.alerts.extend(raised)
        return raised

    # --- detection --------------------------------------------------------
    def _accept(self, alert: dict, signature: tuple, detected_at: datetime) -> bool:
        if signature in self.signatures:
            return False
        self.signatures.add(signature)
        alert["detected_at"] = detected_at
        scenario_of = self._scenario_of(alert["event_ids"])
        for scenario_id in scenario_of:
            injection = self.injections.get(scenario_id)
            if injection and injection.detected_at is None:
                injection.detected_at = detected_at
                injection.detected_by = alert["source"]
        alert["true_positive"] = bool(scenario_of)
        return True

    def _scenario_of(self, event_ids: list[str]) -> set[str]:
        return {self.scenario_of_event[e] for e in event_ids if e in self.scenario_of_event}

    def _run_rules(self, now: datetime) -> list[dict]:
        raised = []
        for alert in rule_engine.run_rules(self.buffer, self.rules):
            if not alert["event_ids"]:
                continue
            seen = self.covered.setdefault((alert["source"], alert["entity"]), set())
            trigger = alert["event_ids"][0]
            if trigger in seen:
                seen.update(alert["event_ids"])  # the same activity, with more evidence absorbed
                continue
            seen.update(alert["event_ids"])
            if self._accept(alert, (alert["source"], alert["entity"], trigger), now):
                raised.append(alert)
        return raised

    def _score_closed_hour(self, boundary: datetime) -> list[dict]:
        if self.model is None or not self.hour_events:
            return []
        hour = pd.DataFrame(self.hour_events)
        hour = hour[hour["ts"] >= boundary - timedelta(hours=1)]
        if hour.empty:
            return []
        scored = anomaly.score_with(self.model, anomaly.extract_features(hour))
        raised = []
        for alert in anomaly.generate_anomaly_alerts(scored, hour, top_n=ANOMALY_BUDGET_PER_HOUR, high_cut=self.high_cut):
            if self._accept(alert, (alert["source"], alert["entity"], alert["ts"]), boundary):
                raised.append(alert)
        return raised

    # --- views ------------------------------------------------------------
    def alerts_frame(self) -> pd.DataFrame:
        columns = ["detected_at", "ts", "severity", "source", "title", "entity", "mitre_technique", "true_positive", "description"]
        if not self.alerts:
            return pd.DataFrame(columns=columns)
        return pd.DataFrame(self.alerts)[columns].sort_values("detected_at", ascending=False).reset_index(drop=True)

    def injections_frame(self) -> pd.DataFrame:
        rows = [{
            "scenario": i.tag, "started": i.started, "detected_at": i.detected_at, "detected_by": i.detected_by,
            "minutes_to_detect": (i.detected_at - i.started).total_seconds() / 60 if i.detected_at else None,
        } for i in self.injections.values()]
        return pd.DataFrame(rows, columns=["scenario", "started", "detected_at", "detected_by", "minutes_to_detect"])

    def rate_frame(self, window: timedelta = timedelta(hours=3), bin: str = "5min") -> pd.DataFrame:
        """Event counts per `bin` over the trailing `window`, zero-filled.
        Only complete bins are returned."""
        if not self.per_minute:
            return pd.DataFrame(columns=["bucket", "events"])
        series = pd.Series(self.per_minute).sort_index()
        series = series[series.index >= pd.Timestamp(self.clock - window)]
        binned = series.groupby(series.index.floor(bin)).sum()
        last = pd.Timestamp(self.clock).floor(bin)
        full = pd.date_range(binned.index.min(), last, freq=bin, inclusive="left")
        return binned.reindex(full, fill_value=0).rename_axis("bucket").reset_index(name="events")


def train_from_history(events: pd.DataFrame, contamination: float = 0.03) -> tuple[object | None, float | None]:
    """A model fitted on stored events, and the score cut for 'high'."""
    feat = anomaly.extract_features(events)
    if feat[feat["event_count"] > 0].empty:
        return None, None
    model = anomaly.fit_model(feat, contamination=contamination)
    scored = anomaly.score_with(model, feat)
    return model, float(scored["anomaly_score"].quantile(0.97))
