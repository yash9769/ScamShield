from __future__ import annotations

import html

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import (
    add_to_watchlist,
    GRIDLINE,
    INK_MUTED,
    INK_SECONDARY,
    SERIES,
    SEVERITY_COLOR,
    SEVERITY_ORDER,
    STATUS_OPTIONS,
    SURFACE,
    csv_download,
    format_duration,
    get_alerts,
    get_evaluation,
    get_events,
    get_incidents,
    require_data,
    set_incident_actions,
    set_incident_notes,
    set_incident_status,
    severity_badge,
    styled,
    technique_label,
)
from socdash import mitre, response
from socdash.detection import graph as attack_graph
from socdash.detection.correlation import kill_chain_stages
from socdash.detection.ioc import decoded_commands, incident_iocs
from socdash.response import report

EDITOR = "incidents_editor"


def _kill_chain_html(tactics: list[str]) -> str:
    """The 14 Enterprise tactics as a fixed 7 × 2 grid — a fixed grid rather
    than wrapping flex, which stretched the last row's cells to full width."""
    cells = []
    for tactic, touched in kill_chain_stages(tactics):
        style = (
            f"background:{SERIES[0]};color:#fff;border:1px solid {SERIES[0]};"
            if touched else
            f"background:transparent;color:{INK_MUTED};border:1px dashed {GRIDLINE};"
        )
        cells.append(
            f'<div style="{style}padding:7px 6px;border-radius:6px;font-size:12px;line-height:1.25;'
            f'text-align:center;display:flex;align-items:center;justify-content:center;">{html.escape(tactic)}</div>'
        )
    return ('<div style="display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:4px;margin:2px 0 8px;">'
            + "".join(cells) + "</div>")


def _editable_table(filtered: pd.DataFrame) -> None:
    """Inline status editing. Edits are applied once, then the editor is
    re-keyed: st.data_editor keeps positional edits across reruns, and once
    a status change moves a row out of the current filter, a stale edit
    would land on whichever incident now occupies that position."""
    version = st.session_state.setdefault(f"{EDITOR}_version", 0)
    key = f"{EDITOR}_{version}"
    # Status second: it's the one editable column, so it must never be the
    # one scrolled off the right edge.
    table = filtered.assign(
        tactic_count=filtered["tactics"].apply(len),
        duration=(filtered["last_seen"] - filtered["first_seen"]).apply(format_duration),
    )[["incident_id", "status", "severity", "score", "title", "alert_count", "tactic_count", "first_seen", "duration"]
      ].reset_index(drop=True)
    st.data_editor(
        table, key=key, hide_index=True, use_container_width=True,
        disabled=[c for c in table.columns if c != "status"],
        column_config={
            "status": st.column_config.SelectboxColumn("status", options=STATUS_OPTIONS, required=True),
            "alert_count": st.column_config.NumberColumn("alerts"),
            "tactic_count": st.column_config.NumberColumn("tactics"),
        },
    )
    changes = [
        (table.iloc[int(i)]["incident_id"], edit["status"])
        for i, edit in st.session_state.get(key, {}).get("edited_rows", {}).items()
        if "status" in edit and edit["status"] != table.iloc[int(i)]["status"]
    ]
    if changes:
        for incident_id, status in changes:
            set_incident_status(incident_id, status)
        st.session_state.pop(key, None)
        st.session_state[f"{EDITOR}_version"] = version + 1
        st.rerun()


def _timeline(members: pd.DataFrame) -> go.Figure:
    """Rule alerts are points in time. Anomaly alerts describe a whole host-
    hour, so they're drawn as that hour — a single point stamped at the start
    of the hour would show them happening before the activity they flag."""
    members = members.assign(stage=members["mitre_tactic"].fillna("Unattributed"))
    present = set(members["stage"])
    order = [t for t in mitre.TACTIC_ORDER if t in present] + (["Unattributed"] if "Unattributed" in present else [])
    is_anomaly = members["source"] == "anomaly_isolation_forest"
    hour = pd.Timedelta(hours=1)
    fig = go.Figure()

    anomalies = members[is_anomaly]
    for severity, group in anomalies.groupby("severity"):
        xs, ys = [], []
        for _, alert in group.iterrows():
            xs += [alert["ts"], alert["ts"] + hour, None]
            ys += [alert["stage"], alert["stage"], None]
        fig.add_trace(go.Scatter(x=xs, y=ys, mode="lines", line=dict(color=SEVERITY_COLOR[severity], width=8),
                                 opacity=0.35, hoverinfo="skip", showlegend=False))

    rules = members[~is_anomaly].assign(when=members.loc[~is_anomaly, "ts"].dt.strftime("%d %b %H:%M:%S"))
    mids = anomalies.assign(
        when=anomalies["ts"].dt.strftime("%d %b %H:%M") + "–" + (anomalies["ts"] + hour).dt.strftime("%H:%M"),
        ts=anomalies["ts"] + hour / 2,
    )
    for subset, symbol in ((rules, "circle"), (mids, "diamond")):
        if subset.empty:
            continue
        fig.add_trace(go.Scatter(
            x=subset["ts"], y=subset["stage"], mode="markers", showlegend=False,
            marker=dict(size=14, symbol=symbol, color=[SEVERITY_COLOR[s] for s in subset["severity"]],
                        line=dict(width=2, color=SURFACE)),
            customdata=subset[["title", "source", "severity", "entity", "when"]],
            hovertemplate="<b>%{customdata[0]}</b><br>%{customdata[4]}<br>%{customdata[1]} · "
                          "%{customdata[2]}<br>%{customdata[3]}<extra></extra>",
        ))
    # Plotly stacks categories bottom-up; reverse so the matrix reads top-down.
    fig.update_yaxes(categoryorder="array", categoryarray=order[::-1], title=None)
    fig.update_layout(height=max(220, 52 * len(order) + 80))
    return styled(fig)


NODE_SYMBOL = {"host": "circle", "user": "square", "ip": "diamond", "domain": "hexagon"}
NODE_KIND_LABEL = {"host": "host", "user": "account", "ip": "external IP", "domain": "domain"}


def _curve(x0, y0, x1, y1, bend: float, steps: int = 24):
    """Points along a quadratic curve from (x0, y0) to (x1, y1); `bend`
    pushes the control point sideways so parallel edges fan apart."""
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    dx, dy = x1 - x0, y1 - y0
    length = (dx * dx + dy * dy) ** 0.5 or 1.0
    cx, cy = mx - dy / length * bend, my + dx / length * bend
    ts = [i / steps for i in range(steps + 1)]
    xs = [(1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1 for t in ts]
    ys = [(1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y1 for t in ts]
    return xs, ys


def _attack_graph(members: pd.DataFrame) -> go.Figure | None:
    nodes, edges = attack_graph.build(members, get_events())
    if nodes.empty or not edges:
        return None
    nodes = attack_graph.layout(nodes).set_index("id")
    tactics = [t for t in mitre.TACTIC_ORDER if any(e.tactic == t for e in edges)]
    color = {t: SERIES[i] for i, t in enumerate(tactics)} | {"Unattributed": INK_MUTED}
    fig = go.Figure()
    # Legend entries first, in ATT&CK matrix order; the edges then join them.
    for tactic in tactics + (["Unattributed"] if any(e.tactic == "Unattributed" for e in edges) else []):
        fig.add_trace(go.Scatter(x=[None], y=[None], mode="lines", line=dict(color=color[tactic], width=3),
                                 name=tactic, legendgroup=tactic))

    # Parallel edges between the same two nodes fan out instead of overlapping.
    groups: dict[tuple[str, str], list] = {}
    for edge in edges:
        groups.setdefault(tuple(sorted((edge.source, edge.target))), []).append(edge)
    mids_x, mids_y, mids_text, mids_color = [], [], [], []
    for pair_edges in groups.values():
        n = len(pair_edges)
        for k, edge in enumerate(pair_edges):
            a, b = nodes.loc[edge.source], nodes.loc[edge.target]
            bend = (k - (n - 1) / 2) * 0.32
            if abs(a["y"] - b["y"]) < 0.3 and abs(a["x"] - b["x"]) > 1:
                # Same lane, not adjacent: arc above the lane so the edge
                # doesn't run through the nodes in between. Longer = higher.
                bend += 0.16 * abs(a["x"] - b["x"]) * (1 if b["x"] > a["x"] else -1)
            xs, ys = _curve(a["x"], a["y"], b["x"], b["y"], bend)
            width = 1.5 + min(edge.count, 40) ** 0.5 * 0.45
            fig.add_trace(go.Scatter(
                x=xs, y=ys, mode="lines", line=dict(color=color[edge.tactic], width=width),
                name=edge.tactic, legendgroup=edge.tactic, showlegend=False, hoverinfo="skip",
            ))
            # Arrowhead just short of the target marker.
            fig.add_annotation(x=xs[-3], y=ys[-3], ax=xs[-6], ay=ys[-6], xref="x", yref="y", axref="x", ayref="y",
                               showarrow=True, arrowhead=2, arrowsize=1.1, arrowwidth=1.5,
                               arrowcolor=color[edge.tactic], text="")
            mids_x.append(xs[len(xs) // 2])
            mids_y.append(ys[len(ys) // 2])
            label = "unattributed" if edge.technique == "unattributed" else f"{edge.technique} · {mitre.describe(edge.technique)['name']}"
            when = edge.first.strftime("%d %b %H:%M") + ("" if edge.first == edge.last else "–" + edge.last.strftime("%H:%M"))
            mids_text.append(
                f"<b>{html.escape(edge.source.split(':', 1)[1])} → {html.escape(edge.target.split(':', 1)[1])}</b><br>"
                f"{label}<br>{edge.count} event(s) · {when}<br>{html.escape(', '.join(sorted(edge.actions))[:90])}"
            )
            mids_color.append(color[edge.tactic])
    # Invisible hover targets at each edge's midpoint: line traces only
    # hover at their vertices, which sit under the node markers.
    fig.add_trace(go.Scatter(x=mids_x, y=mids_y, mode="markers", showlegend=False,
                             marker=dict(size=16, color=mids_color, opacity=0), hovertext=mids_text, hoverinfo="text"))

    for kind, group in nodes.groupby("kind"):
        fig.add_trace(go.Scatter(
            x=group["x"], y=group["y"], mode="markers+text", showlegend=False,
            marker=dict(size=20, symbol=NODE_SYMBOL[kind], color=SURFACE, line=dict(width=2, color=INK_SECONDARY)),
            text=group["label"], textposition="top center" if kind in ("ip", "domain") else "bottom center", textfont=dict(size=11, color=INK_SECONDARY),
            customdata=group[["first_seen", "alerts"]].assign(first_seen=group["first_seen"].dt.strftime("%d %b %H:%M:%S")),
            hovertemplate=f"<b>%{{text}}</b><br>{NODE_KIND_LABEL[kind]} · first seen %{{customdata[0]}}"
                          "<br>in %{customdata[1]} alert(s)<extra></extra>",
        ))
    lanes = sorted(set(attack_graph.LANE_LABELS))
    fig.update_yaxes(tickvals=lanes, ticktext=[attack_graph.LANE_LABELS[v] for v in lanes], showgrid=True,
                     zeroline=False, range=[min(nodes["y"].min(), 0) - 0.5, max(nodes["y"].max(), 2) + 0.45])
    fig.update_xaxes(visible=False, range=[-0.6, nodes["x"].max() + 0.6])
    fig.update_layout(height=420, hovermode="closest", legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0),
                      margin=dict(l=10, r=10, t=30, b=10))
    return styled(fig)


def _ground_truth(incident_id: str) -> None:
    ev = get_evaluation()
    touched = ev["matches"][(ev["matches"]["incident_id"] == incident_id) & ev["matches"]["scenario_id"].notna()]
    with st.expander("What actually happened — synthetic ground truth (detection never sees this)"):
        if touched.empty:
            st.write("None of this incident's alerts touched injected attack activity: **false positives only**.")
            return
        instances = ev["instances"][ev["instances"]["scenario_id"].isin(touched["scenario_id"])]
        attacks = instances["campaign_id"].fillna(instances["scenario_id"]).nunique()
        verdict = "one attack" if attacks == 1 else f"{attacks} separate attacks, merged by shared entities"
        st.write(f"This incident's alerts touched **{len(instances)} injected technique instance(s)** from **{verdict}**.")
        st.dataframe(
            instances.sort_values("first_ts")[["scenario_tag", "campaign_id", "first_ts", "last_ts", "n_events"]],
            use_container_width=True, hide_index=True,
        )


def _toggle_step(incident_id: str, step_key: str, widget_key: str, done: list[str]) -> None:
    updated = set(done)
    if st.session_state[widget_key]:
        updated.add(step_key)
    else:
        updated.discard(step_key)
    set_incident_actions(incident_id, updated)


def _response(incident, members: pd.DataFrame) -> None:
    """Indicators, a playbook-driven response checklist, analyst notes, and
    the exportable report — the part of the page an analyst works in."""
    linked = get_events()
    linked = linked[linked["event_id"].isin({e for ids in members["event_ids"] for e in ids})]
    iocs = incident_iocs(members, get_events())
    steps = response.plan(response.entities_by_technique(members),
                          iocs.loc[iocs["type"] == "domain", "value"].tolist())
    done = [k for k in incident["actions_done"] if k in {s["key"] for s in steps}]
    incident_id = incident["incident_id"]

    st.markdown("#### Indicators of compromise")
    if iocs.empty:
        st.caption("No indicators extracted — no external addresses, decoded URLs or rare domains in this incident.")
    else:
        st.dataframe(iocs, use_container_width=True, hide_index=True,
                     column_config={"first_seen": st.column_config.DatetimeColumn("first seen", format="DD MMM HH:mm:ss")})
        b1, b2 = st.columns([1, 3], vertical_alignment="center")
        with b1:
            csv_download(iocs, f"{incident_id}-iocs.csv", label="Download IOCs (CSV)")
        if b2.button("Add IOCs to the watchlist", key=f"watch::{incident_id}"):
            hunted = iocs[iocs["type"].isin(["ip", "domain"])]
            new = add_to_watchlist([{"value": v, "type": t, "note": f"IOC from {incident_id}", "incident_id": incident_id}
                                    for t, v in zip(hunted["type"], hunted["value"])])
            st.session_state["intel_sweep_values"] = hunted["value"].tolist()
            st.toast(f"{new} new indicator(s) on the watchlist. Threat Intel has them ready to retro-hunt.")
    decoded = decoded_commands(linked)
    if not decoded.empty:
        with st.expander(f"Decoded PowerShell ({len(decoded)})", expanded=True):
            for _, row in decoded.iterrows():
                st.caption(f"{row['host']} · {row['user']} · {row['ts']:%d %b %H:%M:%S}")
                st.code(row["decoded"], language="powershell", wrap_lines=True)

    st.markdown("#### Response plan")
    if not steps:
        st.caption("No playbook steps apply to this incident's techniques.")
    else:
        st.progress(len(done) / len(steps), text=f"{len(done)} of {len(steps)} steps done")
        st.caption("Steps come from ATT&CK-keyed playbooks, filled in with the entities of each technique's own alerts.")
        for phase in response.PHASES:
            phase_steps = [s for s in steps if s["phase"] == phase]
            if not phase_steps:
                continue
            st.markdown(f"**{phase.capitalize()}**")
            for step in phase_steps:
                widget_key = f"step::{incident_id}::{step['key']}"
                st.checkbox(
                    step["action"], value=step["key"] in done, key=widget_key,
                    help=technique_label(None if step["technique"] == response.UNATTRIBUTED else step["technique"]),
                    on_change=_toggle_step, args=(incident_id, step["key"], widget_key, done),
                )

    st.markdown("#### Analyst notes")
    with st.form(f"notes::{incident_id}", border=False):
        notes = st.text_area("Notes", value=incident["notes"], height=120, label_visibility="collapsed",
                             placeholder="What you checked, what you found, who you told.")
        if st.form_submit_button("Save notes"):
            set_incident_notes(incident_id, notes)
            st.rerun()

    html_report = report.build(incident, members, iocs, steps, set(done), notes=incident["notes"])
    st.download_button("Download incident report (HTML)", html_report.encode("utf-8"),
                       file_name=f"{incident_id}-report.html", mime="text/html", type="primary")
    st.caption("A single self-contained file — attach it to a ticket, or open it and print to PDF.")


def render() -> None:
    st.title("Incidents")
    st.caption(
        "Alerts that share a host, account, or external address and fired within three hours of each "
        "other are one incident — transitively, so a five-stage intrusion whose first and last alerts "
        "share nothing still lands in one place."
    )
    if not require_data():
        return
    incidents = get_incidents()
    alerts = get_alerts()
    if incidents.empty:
        st.info("No incidents yet — generate data on the Overview page.")
        return

    open_count = incidents["status"].isin(["new", "investigating"]).sum()
    multi = (incidents["tactics"].apply(len) >= 3).sum()
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Incidents", len(incidents))
    c2.metric("Open", int(open_count))
    c3.metric("Multi-stage", int(multi), help="Spanning three or more ATT&CK tactics — automatically critical.")
    c4.metric("Alert reduction", f"{len(alerts) / len(incidents):.1f}×",
              help=f"{len(alerts)} alerts became {len(incidents)} things to look at.")

    f1, f2 = st.columns(2)
    severities = f1.multiselect("Severity", SEVERITY_ORDER, default=SEVERITY_ORDER)
    statuses = f2.multiselect("Status", STATUS_OPTIONS, default=STATUS_OPTIONS)
    filtered = incidents[incidents["severity"].isin(severities) & incidents["status"].isin(statuses)]
    st.caption(f"{len(filtered)} of {len(incidents)} incidents · change Status inline to triage — member alerts follow.")
    if filtered.empty:
        return
    _editable_table(filtered)
    csv_download(filtered.assign(tactics=filtered["tactics"].apply(", ".join)), "incidents.csv")

    st.divider()
    labels = {row["incident_id"]: f"{row['incident_id']} · {row['severity'].upper()} · {row['title']}"
              for _, row in filtered.iterrows()}
    chosen = st.selectbox("Open an incident", list(labels), format_func=labels.get)
    incident = filtered[filtered["incident_id"] == chosen].iloc[0]
    members = alerts[alerts["incident_id"] == chosen].sort_values("ts")

    st.markdown(f"### {html.escape(incident['title'])}")
    st.markdown(
        f"{severity_badge(incident['severity'])} &nbsp;·&nbsp; score **{incident['score']:g}** &nbsp;·&nbsp; "
        f"{incident['alert_count']} alerts over {format_duration(incident['last_seen'] - incident['first_seen'])} "
        f"&nbsp;·&nbsp; detectors: {', '.join(incident['sources'])} &nbsp;·&nbsp; status: **{incident['status']}**",
        unsafe_allow_html=True,
    )

    st.markdown("**ATT&CK kill chain** — filled stages are the tactics this incident touched")
    st.markdown(_kill_chain_html(incident["tactics"]), unsafe_allow_html=True)

    st.markdown("**Timeline**")
    st.plotly_chart(_timeline(members), use_container_width=True)
    st.caption("Color = severity · ● rule alert, at the moment it fired · ◆ anomaly alert, shaded across the host-hour it scored.")

    graph_fig = _attack_graph(members)
    if graph_fig is not None:
        st.markdown("**Attack graph** — who did what to whom, left to right in the order each entity first appears")
        st.plotly_chart(graph_fig, use_container_width=True)
        st.caption("● host · ■ account · ◆ external IP · ⬢ domain · edges colored by ATT&CK tactic, thicker = more events. "
                   "Hover an edge's midpoint for its evidence.")

    entities = incident["entities"]
    e1, e2, e3 = st.columns(3)
    for column, kind, label in ((e1, "hosts", "Hosts"), (e2, "users", "Accounts"), (e3, "ips", "External IPs")):
        values = entities.get(kind, [])
        column.markdown(f"**{label}** ({len(values)})")
        column.markdown(", ".join(f"`{v}`" for v in values) if values else "—")

    st.markdown("**Member alerts**")
    st.dataframe(
        members.assign(mitre_tactic=members["mitre_tactic"].fillna("—"))[
            ["ts", "severity", "source", "mitre_tactic", "title", "entity", "description", "status"]
        ],
        use_container_width=True, hide_index=True,
    )
    _response(incident, members)
    _ground_truth(chosen)
