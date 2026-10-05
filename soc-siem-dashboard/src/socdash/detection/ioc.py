"""Indicators of compromise: what an analyst copies into a block list or a
threat-intel ticket.

Encoded PowerShell is decoded first — `-enc` takes base64 of UTF-16LE text,
and the decoded script is where the download URL lives. DNS lookups only
count when the domain is rare across the whole environment (queried by very
few hosts), because a SaaS domain every laptop resolves indicates nothing.
"""

from __future__ import annotations

import base64
import binascii
import re
from collections import defaultdict
from urllib.parse import urlparse

import pandas as pd

ENCODED_ARGUMENT = re.compile(r"(?i)\s-e[a-z]*\s+([A-Za-z0-9+/=]{40,})")
URL = re.compile(r"https?://[^\s'\"<>()]+", re.IGNORECASE)
IOC_COLUMNS = ["type", "value", "context", "first_seen"]


def decode_powershell(command_line: str | None) -> str | None:
    """The script behind `powershell -enc <base64>`, or None if there isn't
    an encoded argument (or it doesn't decode to UTF-16LE text)."""
    if not command_line:
        return None
    match = ENCODED_ARGUMENT.search(command_line)
    if not match:
        return None
    blob = match.group(1)
    try:
        return base64.b64decode(blob + "=" * (-len(blob) % 4), validate=True).decode("utf-16-le")
    except (binascii.Error, UnicodeDecodeError, ValueError):
        return None


def decoded_commands(events: pd.DataFrame) -> pd.DataFrame:
    """Process events whose command line carries an encoded PowerShell
    argument, with the decoded script alongside."""
    procs = events[(events["event_type"] == "process") & events["command_line"].notna()]
    decoded = procs["command_line"].apply(decode_powershell)
    out = procs.assign(decoded=decoded)[decoded.notna()]
    return out[["ts", "host", "user", "command_line", "decoded"]].sort_values("ts").reset_index(drop=True)


def urls_in(text: str | None) -> list[str]:
    return URL.findall(text or "")


def rare_domains(events: pd.DataFrame, max_hosts: int = 2) -> set[str]:
    """Domains resolved by at most `max_hosts` distinct hosts in the dataset."""
    dns = events[(events["event_type"] == "dns") & events["domain"].notna()]
    hosts_per_domain = dns.groupby("domain")["host"].nunique()
    return set(hosts_per_domain[hosts_per_domain <= max_hosts].index)


def incident_iocs(members: pd.DataFrame, events: pd.DataFrame) -> pd.DataFrame:
    """Indicators for one incident: external addresses its alerts involve,
    URLs and domains inside decoded PowerShell, and rare domains its hosts
    resolved. One row per indicator, contexts merged, earliest sighting."""
    found: dict[tuple[str, str], dict] = {}

    def add(kind: str, value: str, context: str, seen) -> None:
        key = (kind, value)
        entry = found.setdefault(key, {"type": kind, "value": value, "contexts": [], "first_seen": seen})
        if context not in entry["contexts"]:
            entry["contexts"].append(context)
        if pd.notna(seen) and (pd.isna(entry["first_seen"]) or seen < entry["first_seen"]):
            entry["first_seen"] = seen

    linked = events[events["event_id"].isin({e for ids in members["event_ids"] for e in ids})]

    sources_by_ip: dict[str, set[str]] = defaultdict(set)
    for _, alert in members.iterrows():
        for ip in (alert["entities"] or {}).get("ips", []):
            sources_by_ip[ip].add(alert["source"])
    for ip, sources in sources_by_ip.items():
        seen = linked.loc[(linked["src_ip"] == ip) | (linked["dst_ip"] == ip), "ts"].min()
        add("ip", ip, "seen by " + ", ".join(sorted(sources)), seen)

    for _, event in linked[linked["event_type"] == "process"].iterrows():
        for url in urls_in(decode_powershell(event["command_line"])):
            context = f"downloaded by encoded PowerShell on {event['host']}"
            add("url", url, context, event["ts"])
            if host := urlparse(url).hostname:
                add("domain", host, context, event["ts"])

    rare = rare_domains(events)
    lookups = linked[(linked["event_type"] == "dns") & linked["domain"].isin(rare)]
    for domain, group in lookups.groupby("domain"):
        hosts = ", ".join(sorted(group["host"].unique()))
        add("domain", domain, f"resolved {len(group)}× by {hosts}", group["ts"].min())

    if not found:
        return pd.DataFrame(columns=IOC_COLUMNS)
    rows = [{**{k: v for k, v in e.items() if k != "contexts"}, "context": "; ".join(e["contexts"])} for e in found.values()]
    order = {"url": 0, "domain": 1, "ip": 2}
    return (pd.DataFrame(rows)[IOC_COLUMNS]
            .sort_values(["type", "first_seen"], key=lambda s: s.map(order) if s.name == "type" else s)
            .reset_index(drop=True))
