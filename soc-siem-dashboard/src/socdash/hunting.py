"""Threat hunting: ad-hoc, read-only SQL over the event store.

This executes text a person typed, so there are three independent guards:

1. the connection is opened read-only (SQLite URI `mode=ro`);
2. an authorizer callback allows only SELECT, column reads, and function
   calls — ATTACH, PRAGMA, and every kind of write are refused at prepare
   time, before anything runs;
3. a progress handler aborts any query that runs past its time budget, so a
   runaway cross join can't hang the dashboard.

sqlite3's execute() additionally refuses more than one statement per call.

Hunts also get a few SQL functions SQLite doesn't ship with: entropy(),
domain_label(), is_internal(), and a stddev() aggregate.
"""

from __future__ import annotations

import math
import sqlite3
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from .detection.entities import INTERNAL_PREFIX

_ALLOWED_ACTIONS = {sqlite3.SQLITE_SELECT, sqlite3.SQLITE_READ, sqlite3.SQLITE_FUNCTION, sqlite3.SQLITE_RECURSIVE}


class HuntError(Exception):
    """A hunt that was refused, failed, or timed out. The message is meant
    to be shown to the analyst as-is."""


def entropy(text) -> float | None:
    """Shannon entropy of a string, in bits per character."""
    if not text:
        return None
    n = len(text)
    return -sum(c / n * math.log2(c / n) for c in Counter(text).values())


def domain_label(domain) -> str | None:
    """The label left of the TLD: 'xq3kz9pl.net' -> 'xq3kz9pl',
    'aws.amazon.com' -> 'amazon'. Entropy of this, not of the whole name,
    is what separates random-looking domains from brands."""
    if not domain:
        return None
    parts = str(domain).lower().strip(".").split(".")
    return parts[-2] if len(parts) >= 2 else parts[0]


def is_internal(ip) -> int:
    return int(isinstance(ip, str) and ip.startswith(INTERNAL_PREFIX))


class _StdDev:
    """Sample standard deviation aggregate (Welford's algorithm)."""

    def __init__(self) -> None:
        self.n, self.mean, self.m2 = 0, 0.0, 0.0

    def step(self, value) -> None:
        if value is None:
            return
        self.n += 1
        delta = value - self.mean
        self.mean += delta / self.n
        self.m2 += delta * (value - self.mean)

    def finalize(self) -> float | None:
        return math.sqrt(self.m2 / (self.n - 1)) if self.n > 1 else None


SQL_FUNCTIONS = {
    "entropy(text)": "Shannon entropy in bits per character",
    "domain_label(domain)": "label left of the TLD, e.g. amazon from aws.amazon.com",
    "is_internal(ip)": f"1 if the address is in the internal range ({INTERNAL_PREFIX}x.x)",
    "stddev(x)": "sample standard deviation (aggregate)",
}


# Ground truth exists in the table (evaluation needs it) but no real analyst
# would have it, so hunts read these columns as NULL rather than erroring —
# `SELECT *` keeps working, it just can't cheat.
HIDDEN_COLUMNS = {"events": {"scenario_tag", "scenario_id", "campaign_id"}}


def _authorizer(action, arg1, arg2, db_name, trigger) -> int:
    if action == sqlite3.SQLITE_READ and arg2 in HIDDEN_COLUMNS.get(arg1, ()):
        return sqlite3.SQLITE_IGNORE
    return sqlite3.SQLITE_OK if action in _ALLOWED_ACTIONS else sqlite3.SQLITE_DENY


@dataclass
class HuntResult:
    frame: pd.DataFrame
    truncated: bool
    elapsed_ms: float


def run_query(db_path: str | Path, sql: str, max_rows: int = 5000, timeout_s: float = 5.0) -> HuntResult:
    path = Path(db_path)
    if not path.exists():
        raise HuntError("No database yet — generate data first.")
    if not sql.strip():
        raise HuntError("Write a query first.")

    conn = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
    try:
        conn.create_function("entropy", 1, entropy, deterministic=True)
        conn.create_function("domain_label", 1, domain_label, deterministic=True)
        conn.create_function("is_internal", 1, is_internal, deterministic=True)
        conn.create_aggregate("stddev", 1, _StdDev)
        conn.set_authorizer(_authorizer)
        deadline = time.monotonic() + timeout_s
        conn.set_progress_handler(lambda: int(time.monotonic() > deadline), 10_000)

        started = time.perf_counter()
        try:
            cursor = conn.execute(sql)
            rows = cursor.fetchmany(max_rows + 1)
        except (sqlite3.Error, sqlite3.Warning) as exc:
            message = str(exc)
            if "interrupted" in message:
                raise HuntError(f"Stopped: the query ran past its {timeout_s:g}s time budget.") from exc
            if "not authorized" in message:
                raise HuntError("Refused: hunts are read-only — only SELECT queries can run here.") from exc
            raise HuntError(message) from exc
        elapsed_ms = (time.perf_counter() - started) * 1000
        columns = [d[0] for d in cursor.description] if cursor.description else []
    finally:
        conn.close()

    frame = pd.DataFrame(rows[:max_rows], columns=columns)
    return HuntResult(frame=frame, truncated=len(rows) > max_rows, elapsed_ms=elapsed_ms)


@dataclass(frozen=True)
class Hunt:
    name: str
    hypothesis: str
    sql: str


SAVED_HUNTS = [
    Hunt(
        "Beacon-like DNS cadence",
        "Implants check in with their C2 on a timer; people don't. For every host/domain pair, "
        "measure the gap between consecutive queries — a low standard deviation over many "
        "queries is a machine on a schedule.",
        """WITH gaps AS (
    SELECT host, domain,
           (julianday(ts) - julianday(LAG(ts) OVER (PARTITION BY host, domain ORDER BY ts))) * 86400 AS gap_s
    FROM events
    WHERE event_type = 'dns'
)
SELECT host,
       domain,
       COUNT(gap_s) + 1           AS queries,
       ROUND(AVG(gap_s), 1)       AS mean_gap_s,
       ROUND(stddev(gap_s), 1)    AS gap_stddev_s
FROM gaps
WHERE gap_s IS NOT NULL
GROUP BY host, domain
HAVING queries >= 10
ORDER BY gap_stddev_s
LIMIT 25""",
    ),
    Hunt(
        "DGA-like domains",
        "Malware resolving algorithmically generated domains leaves random-looking labels in DNS. "
        "Rank by label entropy — but real brands can score high too (entropy alone overlaps), so "
        "read the top of this list, don't threshold it.",
        """SELECT domain,
       LENGTH(domain_label(domain))              AS label_length,
       ROUND(entropy(domain_label(domain)), 2)   AS label_entropy,
       COUNT(*)                                  AS queries,
       COUNT(DISTINCT host)                      AS hosts
FROM events
WHERE event_type = 'dns'
GROUP BY domain
ORDER BY label_entropy DESC, label_length DESC
LIMIT 25""",
    ),
    Hunt(
        "PowerShell: spot the odd one out",
        "Admins run PowerShell all day, so the binary name means nothing. Sorting by command-line "
        "length floats encoded payloads (long base64 blobs) to the top.",
        """SELECT ts, host, user, LENGTH(command_line) AS length, command_line
FROM events
WHERE event_type = 'process' AND process_name IN ('powershell.exe', 'pwsh.exe')
ORDER BY length DESC
LIMIT 50""",
    ),
    Hunt(
        "Internal fan-out",
        "One internal machine logging into many others is how an intruder spreads. Count distinct "
        "targets per internal source address — excluding each machine's logins to itself, found by "
        "deriving every host's own address from its DNS traffic.",
        """WITH own_ip AS (
    SELECT DISTINCT host, src_ip FROM events WHERE event_type = 'dns'
)
SELECT a.src_ip,
       COUNT(DISTINCT a.host)          AS distinct_targets,
       COUNT(*)                        AS logins,
       GROUP_CONCAT(DISTINCT a.user)   AS accounts,
       MIN(a.ts)                       AS first_seen,
       MAX(a.ts)                       AS last_seen
FROM events a
LEFT JOIN own_ip o ON o.host = a.host AND o.src_ip = a.src_ip
WHERE a.event_type = 'auth' AND a.action = 'login_success'
  AND is_internal(a.src_ip) AND o.host IS NULL
GROUP BY a.src_ip
HAVING distinct_targets > 1
ORDER BY distinct_targets DESC""",
    ),
    Hunt(
        "Accounts with a high failed-login ratio",
        "Password guessing shows up as accounts whose failures dominate their attempts, often "
        "from several source addresses.",
        """SELECT user,
       SUM(action = 'login_failure')                                AS failures,
       COUNT(*)                                                     AS attempts,
       ROUND(100.0 * SUM(action = 'login_failure') / COUNT(*), 1)   AS failure_pct,
       COUNT(DISTINCT src_ip)                                       AS source_ips
FROM events
WHERE event_type = 'auth' AND user IS NOT NULL
GROUP BY user
HAVING attempts >= 5
ORDER BY failure_pct DESC
LIMIT 25""",
    ),
    Hunt(
        "Remote logins outside business hours",
        "Successful logins from outside the network at night or on weekends — most are someone "
        "working late, which is exactly why this is a hunt and not an alert.",
        """SELECT ts, user, host, src_ip, src_country
FROM events
WHERE event_type = 'auth'
  AND action = 'login_success'
  AND NOT is_internal(src_ip)
  AND (CAST(strftime('%H', ts) AS INTEGER) NOT BETWEEN 7 AND 20
       OR strftime('%w', ts) IN ('0', '6'))
ORDER BY ts DESC
LIMIT 200""",
    ),
    Hunt(
        "Top outbound talkers per day",
        "Exfiltration has to move bytes somewhere. Rank each host's daily outbound volume to "
        "external addresses.",
        """SELECT DATE(ts) AS day,
       host,
       ROUND(SUM(bytes_sent) / 1e6, 1)   AS mb_out,
       COUNT(DISTINCT dst_ip)            AS destinations
FROM events
WHERE event_type = 'network' AND direction = 'outbound' AND NOT is_internal(dst_ip)
GROUP BY day, host
ORDER BY mb_out DESC
LIMIT 25""",
    ),
]
