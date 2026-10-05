"""Static inventory the generator and scenarios draw from: users, hosts,
external IPs with geo coordinates, and domains. Kept as plain data so the
rest of the generator stays deterministic given a seeded RNG.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

from faker import Faker

from ..geo import COUNTRY_GEO

_fake = Faker()
Faker.seed(42)
random.seed(42)


@dataclass(frozen=True)
class Host:
    name: str
    ip: str
    role: str  # domain_controller, web, database, file, workstation


@dataclass(frozen=True)
class ExternalIP:
    ip: str
    country: str
    lat: float
    lon: float
    known_malicious: bool


def _build_hosts() -> list[Host]:
    hosts: list[Host] = [
        Host("DC-01", "10.10.0.10", "domain_controller"),
        Host("DC-02", "10.10.0.11", "domain_controller"),
        Host("WEB-01", "10.10.1.10", "web"),
        Host("WEB-02", "10.10.1.11", "web"),
        Host("WEB-03", "10.10.1.12", "web"),
        Host("DB-01", "10.10.2.10", "database"),
        Host("DB-02", "10.10.2.11", "database"),
        Host("FILE-01", "10.10.3.10", "file"),
        Host("VPN-GW-01", "10.10.4.10", "gateway"),
    ]
    for i in range(1, 31):
        hosts.append(Host(f"WKS-{i:04d}", f"10.10.10.{i}", "workstation"))
    return hosts


def _build_users() -> list[str]:
    users = set()
    while len(users) < 35:
        first = _fake.first_name().lower()
        last = _fake.last_name().lower()
        users.add(f"{first[0]}.{last}")
    users_list = sorted(users)
    users_list += ["svc-backup", "svc-sql", "svc-web", "admin", "administrator"]
    return users_list


def _build_external_ips(n: int = 70) -> list[ExternalIP]:
    countries = list(COUNTRY_GEO.keys())
    ips: list[ExternalIP] = []
    seen = set()
    while len(ips) < n:
        ip = _fake.ipv4_public()
        if ip in seen:
            continue
        seen.add(ip)
        country = random.choice(countries)
        lat, lon = COUNTRY_GEO[country]
        # Small jitter so IPs from the same country don't all plot on one point.
        lat += random.uniform(-3, 3)
        lon += random.uniform(-3, 3)
        # ~12% of the external pool is "known bad" (scanners, botnet C2, etc.),
        # spread uniformly across countries rather than tied to any one region —
        # real attacker infrastructure is overwhelmingly rented/compromised
        # cloud and residential hosts, not geography.
        known_malicious = random.random() < 0.12
        ips.append(ExternalIP(ip, country, round(lat, 4), round(lon, 4), known_malicious))
    return ips


NORMAL_DOMAINS = [
    "google.com", "microsoft.com", "office.com", "github.com", "slack.com",
    "zoom.us", "salesforce.com", "cloudflare.com", "wikipedia.org", "aws.amazon.com",
    "awsstatic.com", "akamai.net", "linkedin.com", "atlassian.net", "dropbox.com",
    "docusign.net", "okta.com", "zendesk.com", "notion.so", "figma.com",
]

_DGA_SUFFIXES = [".net", ".info", ".top", ".xyz", ".biz"]


def random_dga_domain() -> str:
    """A random-looking algorithmically-generated domain, the kind C2
    beaconing malware uses instead of a hardcoded, easily-blocklisted host."""
    length = random.randint(8, 14)
    body = "".join(random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(length))
    return body + random.choice(_DGA_SUFFIXES)


HOSTS: list[Host] = _build_hosts()
USERS: list[str] = _build_users()
EXTERNAL_IPS: list[ExternalIP] = _build_external_ips()

HOSTS_BY_NAME = {h.name: h for h in HOSTS}
WORKSTATIONS = [h for h in HOSTS if h.role == "workstation"]
SERVERS = [h for h in HOSTS if h.role != "workstation"]


def random_host(roles: list[str] | None = None) -> Host:
    pool = HOSTS if roles is None else [h for h in HOSTS if h.role in roles]
    return random.choice(pool)


def random_user() -> str:
    return random.choice(USERS)


def random_external_ip(malicious_only: bool = False) -> ExternalIP:
    pool = [ip for ip in EXTERNAL_IPS if ip.known_malicious] if malicious_only else EXTERNAL_IPS
    return random.choice(pool)
