"""Response planning: turn an incident into concrete next steps.

Steps come from ATT&CK-keyed playbooks (playbooks.yml) and are rendered with
the incident's own hosts, accounts, addresses and domains, so the plan says
"block 209.154.196.24", not "block the attacker".
"""

from __future__ import annotations

from pathlib import Path

import yaml

from .. import mitre

PLAYBOOKS_PATH = Path(__file__).parent / "playbooks.yml"
PHASES = ["investigate", "contain", "eradicate", "recover"]
UNATTRIBUTED = "_unattributed"


def load_playbooks(path: Path = PLAYBOOKS_PATH) -> dict[str, list[dict]]:
    with open(path) as f:
        return yaml.safe_load(f)


def _join(values: list[str], limit: int = 4) -> str:
    values = list(values)
    if len(values) <= limit:
        return ", ".join(values)
    return f"{', '.join(values[:limit])} and {len(values) - limit} more"


def entities_by_technique(alerts) -> dict[str, dict[str, list[str]]]:
    """Each technique's entities, taken from that technique's own alerts.

    Scoping matters: an incident's entity set is the union over all its
    alerts, so it holds every host a port scan touched. "Isolate the hosts"
    must mean the host that ran the encoded PowerShell, not the scan targets.
    """
    merged: dict[str, dict[str, list[str]]] = {}
    for _, alert in alerts.iterrows():
        technique = alert["mitre_technique"]
        key = technique if isinstance(technique, str) and technique else UNATTRIBUTED
        bucket = merged.setdefault(key, {"hosts": [], "users": [], "ips": []})
        for kind in bucket:
            for value in (alert["entities"] or {}).get(kind, []):
                if value not in bucket[kind]:
                    bucket[kind].append(value)
    return merged


def plan(
    by_technique: dict[str, dict[str, list[str]]],
    domains: list[str] | None = None,
    playbooks: dict[str, list[dict]] | None = None,
) -> list[dict]:
    """Deduplicated response steps for one incident, in phase order, each
    with a stable `key` ("T1110:block-source") so completion can be stored.
    `by_technique` maps technique -> its own entities (entities_by_technique);
    `domains` are the incident's domain IOCs."""
    playbooks = playbooks if playbooks is not None else load_playbooks()
    ordered = sorted(by_technique, key=lambda t: (t == UNATTRIBUTED, mitre.tactic_rank(mitre.describe(t)["tactic"]), t))

    steps = []
    for technique in ordered:
        entities = by_technique[technique]
        context = {
            "hosts": list(entities.get("hosts", [])),
            "users": list(entities.get("users", [])),
            "ips": list(entities.get("ips", [])),
            "domains": list(domains or []),
        }
        rendered = {name: _join(values) for name, values in context.items()}
        for step in playbooks.get(technique, []):
            if not context.get(step["needs"]):
                continue
            steps.append({
                "key": f"{technique}:{step['id']}",
                "technique": technique,
                "phase": step["phase"],
                "action": step["action"].format_map(rendered),
            })
    steps.sort(key=lambda s: PHASES.index(s["phase"]))  # stable: technique order kept within a phase
    return steps
