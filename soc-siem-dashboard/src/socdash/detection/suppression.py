"""Alert suppression: analyst-written exceptions for known-benign noise.

A suppression names a detector (or `*` for any) and an entity pattern
(`fnmatch`-style, case-insensitive, e.g. `svc-backup` or `WKS-00*`). While
it is active, matching alerts are still produced and stored, so the record
is auditable, but with status `suppressed`. They never reach correlation,
so they open no incident and add no entity risk, and evaluation does not
count them as detections.

Suppressions apply when detection runs. Like a SIEM's, they act on alerts
that detection produces from then on and do not rewrite incidents already
open. The dashboard says so and offers a re-run.
"""

from __future__ import annotations

import fnmatch
from datetime import datetime

import pandas as pd

SUPPRESSED = "suppressed"


def is_active(rule: dict, now: datetime | None = None) -> bool:
    expires = rule.get("expires_at")
    if expires is None or expires == "" or pd.isna(expires):
        return True
    return (now or datetime.now()) < pd.Timestamp(expires)


def matches(alert: dict, rule: dict) -> bool:
    source = (rule.get("source") or "*").strip()
    if source != "*" and source != alert.get("source"):
        return False
    pattern = (rule.get("entity") or "*").strip().lower()
    return fnmatch.fnmatchcase(str(alert.get("entity") or "").lower(), pattern)


def apply(alerts: list[dict], rules: list[dict], now: datetime | None = None) -> tuple[list[dict], list[dict]]:
    """Split alerts into (kept, suppressed); suppressed ones are marked with
    status `suppressed` and the id of the first matching rule."""
    active = [r for r in rules if is_active(r, now)]
    kept, suppressed = [], []
    for alert in alerts:
        rule = next((r for r in active if matches(alert, r)), None)
        if rule is None:
            kept.append(alert)
        else:
            suppressed.append({**alert, "status": SUPPRESSED, "suppressed_by": rule["suppression_id"], "incident_id": None})
    return kept, suppressed
