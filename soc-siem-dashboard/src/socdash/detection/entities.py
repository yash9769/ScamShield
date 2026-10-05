"""Structured entities (hosts, users, external IPs) attached to every alert:
what the correlation engine joins alerts on and what risk scoring attributes
risk to.

Internal IPs are resolved to host names through the asset inventory, the
way a SIEM enriches events from its CMDB — a lateral-movement alert keyed on
10.10.10.12 and a PowerShell alert on WKS-0012 are about the same machine,
and correlation has to know that. (The synthetic org's inventory happens to
live in generator/entities.py; a real deployment would read a CMDB.)
"""

from __future__ import annotations

import pandas as pd

from ..generator.entities import HOSTS

INTERNAL_PREFIX = "10.10."
KINDS = ("hosts", "users", "ips")
_IP_TO_HOST = {h.ip: h.name for h in HOSTS}


def is_internal(ip) -> bool:
    return isinstance(ip, str) and ip.startswith(INTERNAL_PREFIX)


def empty() -> dict[str, list[str]]:
    return {kind: [] for kind in KINDS}


def from_events(events: pd.DataFrame, kinds: tuple[str, ...] = KINDS) -> dict[str, list[str]]:
    found: dict[str, set[str]] = {kind: set() for kind in KINDS}
    if "host" in events:
        found["hosts"].update(events["host"].dropna().astype(str))
    if "user" in events:
        found["users"].update(events["user"].dropna().astype(str))
    for col in ("src_ip", "dst_ip"):
        if col not in events:
            continue
        for ip in events[col].dropna().astype(str):
            if not is_internal(ip):
                found["ips"].add(ip)
            elif ip in _IP_TO_HOST:
                found["hosts"].add(_IP_TO_HOST[ip])
    return {kind: sorted(found[kind]) if kind in kinds else [] for kind in KINDS}


def keys(entities: dict | None) -> set[tuple[str, str]]:
    """Flattens an entities dict into (kind, value) pairs for joining."""
    if not entities:
        return set()
    return {(kind, value) for kind in KINDS for value in entities.get(kind, [])}
