"""Emits single, schema-normalized SOC events (auth / network / dns / process).

Every event is a flat dict with the same keys regardless of event_type so the
storage layer, rule engine, and dashboard can all treat the event stream
uniformly — unused fields for a given type are just None.

Three fields are ground truth, stamped only on events generator/scenarios.py
produces: `scenario_tag` (which technique), `scenario_id` (which injected
instance of it), and `campaign_id` (which multi-stage attack it belongs to,
if any). Nothing in detection/ reads them; evaluation.py scores detections
against them.
"""

from __future__ import annotations

import random
import uuid
from datetime import datetime

from .entities import Host, NORMAL_DOMAINS, random_external_ip, random_host, random_user

COMMON_PORTS = [443, 443, 443, 80, 22, 3389, 53, 445, 8080, 3306, 5432]

# Everyday command lines. Background PowerShell is deliberately present —
# admins run scripts constantly — so the suspicious-PowerShell rule has to
# key on *how* it's invoked (encoded payloads, download cradles), not on the
# binary name, or it would page someone for every inventory script.
BENIGN_COMMAND_LINES: dict[str, list[str]] = {
    "chrome.exe": [r'"C:\Program Files\Google\Chrome\Application\chrome.exe" --type=renderer --lang=en-US'],
    "outlook.exe": [r'"C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE" /recycle'],
    "excel.exe": [r'"C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE" /dde'],
    "teams.exe": [r'"C:\Users\Public\Teams\current\Teams.exe" --processStart "Teams.exe"'],
    "explorer.exe": [r"C:\Windows\explorer.exe"],
    "svchost.exe": [r"C:\Windows\System32\svchost.exe -k netsvcs -p", r"C:\Windows\System32\svchost.exe -k LocalService"],
    "backup_agent.exe": [r'"C:\Program Files\BackupAgent\backup_agent.exe" --scheduled --target \\FILE-01\backups'],
    "powershell.exe": [
        r"powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\inventory.ps1",
        r"powershell.exe -NoProfile -Command Get-Service | Where-Object Status -eq Running",
    ],
    "cmd.exe": [r"cmd.exe /c ipconfig /all", r"cmd.exe /c dir C:\Users"],
    "ssh": ["ssh deploy@10.10.1.10"],
}


def _new_id() -> str:
    return uuid.uuid4().hex[:12]


def business_hours_weight(dt: datetime) -> float:
    """Relative likelihood of activity at this hour. Weekdays 9-18 are
    busiest; nights/weekends keep a low baseline for shift work and cron-like
    automated jobs, which is what makes a 3am burst stand out later."""
    if dt.weekday() < 5:
        if 9 <= dt.hour < 18:
            return 1.0
        if 7 <= dt.hour < 21:
            return 0.5
        return 0.1
    if 10 <= dt.hour < 16:
        return 0.3
    return 0.08


def _host_name(host: Host | str) -> str:
    return host.name if isinstance(host, Host) else host


def base_event(ts: datetime, event_type: str, scenario_tag: str | None = None) -> dict:
    return {
        "event_id": _new_id(),
        "ts": ts,
        "event_type": event_type,
        "user": None,
        "host": None,
        "src_ip": None,
        "src_country": None,
        "dst_ip": None,
        "direction": None,
        "action": None,
        "outcome": None,
        "port": None,
        "protocol": None,
        "bytes_sent": None,
        "bytes_received": None,
        "process_name": None,
        "command_line": None,
        "domain": None,
        "scenario_tag": scenario_tag,
        "scenario_id": None,
        "campaign_id": None,
    }


def emit_auth_event(
    ts: datetime,
    user: str | None = None,
    host: Host | None = None,
    src_ip: str | None = None,
    src_country: str = "India",
    action: str = "login_success",
    outcome: str = "success",
    scenario_tag: str | None = None,
) -> dict:
    user = user or random_user()
    host = host or random_host(roles=["workstation", "domain_controller", "gateway"])
    e = base_event(ts, "auth", scenario_tag)
    e.update(
        user=user,
        host=_host_name(host),
        src_ip=src_ip or host.ip,
        src_country=src_country,
        action=action,
        outcome=outcome,
    )
    return e


def emit_network_event(
    ts: datetime,
    host: Host | None = None,
    dst_ip: str | None = None,
    src_ip: str | None = None,
    direction: str = "outbound",
    port: int | None = None,
    bytes_sent: int | None = None,
    bytes_received: int | None = None,
    scenario_tag: str | None = None,
) -> dict:
    """`host` is always the internal asset the record is attributed to.
    For outbound records (the default: an employee or server calling out to
    the internet) host.ip is the source. For inbound records (e.g. a port
    scan hitting one of our hosts) host.ip is the destination and the real
    source is an external address — pass src_ip or let one be picked."""
    host = host or random_host()
    external = random_external_ip()
    e = base_event(ts, "network", scenario_tag)
    base_bytes = 50_000 if host.role in ("web", "file") else 8_000
    if direction == "inbound":
        real_src, real_dst = src_ip or external.ip, host.ip
    else:
        real_src, real_dst = host.ip, dst_ip or external.ip
    e.update(
        host=_host_name(host),
        src_ip=real_src,
        dst_ip=real_dst,
        direction=direction,
        action="connection",
        outcome="success",
        port=port or random.choice(COMMON_PORTS),
        protocol="tcp",
        bytes_sent=bytes_sent if bytes_sent is not None else max(200, int(random.gauss(base_bytes, base_bytes * 0.4))),
        bytes_received=bytes_received if bytes_received is not None else max(200, int(random.gauss(base_bytes * 3, base_bytes))),
    )
    return e


def emit_dns_event(
    ts: datetime,
    host: Host | None = None,
    domain: str | None = None,
    scenario_tag: str | None = None,
) -> dict:
    host = host or random_host()
    e = base_event(ts, "dns", scenario_tag)
    e.update(
        host=_host_name(host),
        src_ip=host.ip,
        action="query",
        outcome="success",
        domain=domain or random.choice(NORMAL_DOMAINS),
        protocol="udp",
        port=53,
    )
    return e


def emit_process_event(
    ts: datetime,
    host: Host | None = None,
    user: str | None = None,
    process_name: str | None = None,
    command_line: str | None = None,
    scenario_tag: str | None = None,
) -> dict:
    host = host or random_host(roles=["workstation"])
    process_name = process_name or random.choice(list(BENIGN_COMMAND_LINES))
    if command_line is None:
        command_line = random.choice(BENIGN_COMMAND_LINES.get(process_name, [process_name]))
    e = base_event(ts, "process", scenario_tag)
    e.update(
        host=_host_name(host),
        user=user or random_user(),
        action="exec",
        outcome="success",
        process_name=process_name,
        command_line=command_line,
    )
    return e
