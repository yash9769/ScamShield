"""A small local slice of MITRE ATT&CK (Enterprise) — just the techniques
this project's rules and anomaly detector actually cite. Not a full copy of
the framework; a real deployment would pull the STIX bundle instead."""

from __future__ import annotations

# The Enterprise matrix's left-to-right tactic order — roughly the order an
# intrusion progresses, which is how incident kill-chain views are drawn.
TACTIC_ORDER = [
    "Reconnaissance", "Resource Development", "Initial Access", "Execution",
    "Persistence", "Privilege Escalation", "Defense Evasion", "Credential Access",
    "Discovery", "Lateral Movement", "Collection", "Command and Control",
    "Exfiltration", "Impact",
]

TECHNIQUES: dict[str, dict[str, str]] = {
    "T1595": {"tactic": "Reconnaissance", "name": "Active Scanning"},
    # Valid Accounts sits under four tactics in ATT&CK; impossible travel is
    # an account being *used* from somewhere it shouldn't be, i.e. access.
    "T1078": {"tactic": "Initial Access", "name": "Valid Accounts"},
    "T1059.001": {"tactic": "Execution", "name": "Command and Scripting Interpreter: PowerShell"},
    "T1110": {"tactic": "Credential Access", "name": "Brute Force"},
    "T1021": {"tactic": "Lateral Movement", "name": "Remote Services"},
    "T1071": {"tactic": "Command and Control", "name": "Application Layer Protocol"},
    "T1568": {"tactic": "Command and Control", "name": "Dynamic Resolution"},
    "T1041": {"tactic": "Exfiltration", "name": "Exfiltration Over C2 Channel"},
}


def describe(technique_id: str) -> dict[str, str]:
    return TECHNIQUES.get(technique_id, {"tactic": "Unknown", "name": technique_id})


def tactic_rank(tactic: str | None) -> int:
    return TACTIC_ORDER.index(tactic) if tactic in TACTIC_ORDER else len(TACTIC_ORDER)
