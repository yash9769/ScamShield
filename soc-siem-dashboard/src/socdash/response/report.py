"""Self-contained HTML incident report: one file an analyst can attach to a
ticket, email, or print to PDF from any browser. No external assets — the
styles are inline, so it renders the same offline."""

from __future__ import annotations

import html
from datetime import datetime

import pandas as pd

from .. import mitre
from . import PHASES

SEVERITY_COLOR = {"low": "#0ca30c", "medium": "#c98500", "high": "#d4683b", "critical": "#d03b3b"}

CSS = """
*{box-sizing:border-box}
body{margin:0;background:#f9f9f7;color:#0b0b0b;font:14px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:980px;margin:0 auto;padding:40px 32px 64px;background:#fcfcfb}
header{border-bottom:1px solid #e1e0d9;padding-bottom:20px;margin-bottom:24px}
.eyebrow{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#52514e}
h1{font-size:26px;line-height:1.25;margin:6px 0 10px}
h2{font-size:16px;margin:32px 0 10px;padding-bottom:6px;border-bottom:1px solid #e1e0d9}
.chip{display:inline-block;padding:2px 10px;border-radius:999px;color:#fff;font-weight:600;font-size:12px;letter-spacing:.03em}
.facts{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px 24px;margin-top:16px}
.facts div{font-size:12px;color:#52514e}
.facts b{display:block;font-size:15px;color:#0b0b0b;font-weight:600}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;font-weight:600;color:#52514e;border-bottom:1px solid #c3c2b7;padding:6px 8px}
td{border-bottom:1px solid #e1e0d9;padding:6px 8px;vertical-align:top}
td.mono,code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;word-break:break-all}
.phase{font-weight:600;text-transform:capitalize;margin:14px 0 4px}
.step{display:flex;gap:10px;align-items:baseline;padding:4px 0}
.status{flex:none;width:44px;font-size:11px;font-weight:600;text-align:center;border-radius:4px;padding:1px 0}
.done{background:#e3f4e3;color:#006300}.open{background:#f0efec;color:#52514e}
.notes{white-space:pre-wrap;background:#f9f9f7;border:1px solid #e1e0d9;border-radius:6px;padding:12px}
footer{margin-top:40px;font-size:12px;color:#898781}
@media print{body{background:#fff}main{padding:0}h2{break-after:avoid}tr{break-inside:avoid}}
"""


def _e(value) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)) or value is pd.NaT:
        return "—"
    if isinstance(value, (pd.Timestamp, datetime)):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return html.escape(str(value))


def _duration(delta: pd.Timedelta) -> str:
    minutes = int(delta.total_seconds() // 60)
    return f"{minutes} min" if minutes < 60 else f"{minutes // 60} h {minutes % 60:02d} min"


def summary(incident, members: pd.DataFrame, iocs: pd.DataFrame) -> str:
    entities = incident["entities"]
    n_hosts, n_users, n_ips = (len(entities.get(k, [])) for k in ("hosts", "users", "ips"))
    tactics = incident["tactics"]
    text = (
        f"Between {_e(incident['first_seen'])} and {_e(incident['last_seen'])}, {len(members)} alerts from "
        f"{len(incident['sources'])} detectors described activity across {n_hosts} host(s), {n_users} account(s) "
        f"and {n_ips} external address(es)."
    )
    if len(tactics) >= 2:
        text += f" The alerts span {len(tactics)} ATT&CK tactics — {', '.join(tactics)} — the shape of an intrusion progressing, not isolated noise."
    elif tactics:
        text += f" All attributed alerts fall under {tactics[0]}."
    if not iocs.empty:
        text += f" {len(iocs)} indicator(s) were extracted for blocking and threat-intel sharing."
    return html.escape(text)


def build(
    incident,
    members: pd.DataFrame,
    iocs: pd.DataFrame,
    steps: list[dict],
    done: set[str],
    notes: str = "",
    generated_at: datetime | None = None,
) -> str:
    generated_at = generated_at or datetime.now()
    severity = str(incident["severity"])
    chip = f'<span class="chip" style="background:{SEVERITY_COLOR.get(severity, "#898781")}">{_e(severity.upper())}</span>'

    facts = [
        ("First seen", _e(incident["first_seen"])), ("Last seen", _e(incident["last_seen"])),
        ("Duration", _duration(incident["last_seen"] - incident["first_seen"])),
        ("Alerts", str(len(members))), ("Detectors", _e(", ".join(incident["sources"]))),
        ("Score", f"{incident['score']:g}"),
    ]
    facts_html = "".join(f"<div>{label}<b>{value}</b></div>" for label, value in facts)

    techniques = members["mitre_technique"].dropna().value_counts()
    technique_rows = sorted(
        ((mitre.describe(t)["tactic"], t, mitre.describe(t)["name"], n) for t, n in techniques.items()),
        key=lambda r: (mitre.tactic_rank(r[0]), r[1]),
    )
    attack_html = "".join(
        f"<tr><td>{_e(tactic)}</td><td class='mono'>{_e(t)}</td><td>{_e(name)}</td><td>{n}</td></tr>"
        for tactic, t, name, n in technique_rows
    ) or "<tr><td colspan='4'>No technique attribution.</td></tr>"

    timeline_html = "".join(
        f"<tr><td class='mono'>{_e(a['ts'])}</td><td>{_e(a['severity'])}</td><td>{_e(a['source'])}</td>"
        f"<td>{_e(a['title'])}<br><span style='color:#52514e'>{_e(a['description'])}</span></td></tr>"
        for _, a in members.sort_values("ts").iterrows()
    )

    ioc_html = "".join(
        f"<tr><td>{_e(i['type'])}</td><td class='mono'>{_e(i['value'])}</td><td>{_e(i['context'])}</td>"
        f"<td class='mono'>{_e(i['first_seen'])}</td></tr>"
        for _, i in iocs.iterrows()
    ) or "<tr><td colspan='4'>No indicators extracted.</td></tr>"

    entities = incident["entities"]
    assets_html = "".join(
        f"<tr><td>{label}</td><td class='mono'>{_e(', '.join(entities.get(kind, [])) or chr(8212))}</td></tr>"
        for kind, label in (("hosts", "Hosts"), ("users", "Accounts"), ("ips", "External addresses"))
    )

    plan_html = ""
    for phase in PHASES:
        phase_steps = [s for s in steps if s["phase"] == phase]
        if not phase_steps:
            continue
        plan_html += f"<div class='phase'>{phase}</div>"
        for s in phase_steps:
            state = "done" if s["key"] in done else "open"
            plan_html += (f"<div class='step'><span class='status {state}'>{state.upper()}</span>"
                          f"<span>{_e(s['action'])} <span style='color:#898781'>({_e(s['technique'])})</span></span></div>")
    if not plan_html:
        plan_html = "<p>No playbook steps apply.</p>"

    notes_html = f"<div class='notes'>{_e(notes)}</div>" if notes.strip() else "<p style='color:#898781'>No analyst notes.</p>"

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{_e(incident['incident_id'])} — incident report</title><style>{CSS}</style></head>
<body><main>
<header>
  <div class="eyebrow">Incident report · {_e(incident['incident_id'])} · status: {_e(incident['status'])}</div>
  <h1>{_e(incident['title'])}</h1>
  {chip}
  <div class="facts">{facts_html}</div>
</header>
<h2>Summary</h2><p>{summary(incident, members, iocs)}</p>
<h2>MITRE ATT&amp;CK</h2>
<table><tr><th>Tactic</th><th>Technique</th><th>Name</th><th>Alerts</th></tr>{attack_html}</table>
<h2>Timeline</h2>
<table><tr><th>Time</th><th>Severity</th><th>Detector</th><th>Alert</th></tr>{timeline_html}</table>
<h2>Indicators of compromise</h2>
<table><tr><th>Type</th><th>Value</th><th>Context</th><th>First seen</th></tr>{ioc_html}</table>
<h2>Affected assets</h2>
<table>{assets_html}</table>
<h2>Response plan</h2>{plan_html}
<h2>Analyst notes</h2>{notes_html}
<footer>Generated {_e(generated_at)} by the SOC dashboard. Built from synthetic data for a portfolio project.</footer>
</main></body></html>"""
