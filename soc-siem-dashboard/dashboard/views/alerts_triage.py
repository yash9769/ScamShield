from __future__ import annotations

from datetime import datetime, timedelta

import pandas as pd
import streamlit as st

from common import (
    SEVERITY_ORDER,
    STATUS_OPTIONS,
    csv_download,
    add_suppression,
    get_alerts,
    get_all_alerts,
    get_events,
    rerun_detection,
    require_data,
    set_alert_status,
)
from socdash.detection import suppression
from socdash.detection.ioc import decoded_commands

EXPIRY = {"7 days": 7, "30 days": 30, "90 days": 90, "Until removed": None}

EDITOR = "alerts_editor"


def _editable_table(filtered: pd.DataFrame) -> None:
    """Inline status editing. Edits are applied once, then the editor is
    re-keyed: st.data_editor keeps positional edits across reruns, and once
    a status change moves a row out of the current filter, a stale edit
    would land on whichever alert now occupies that position."""
    version = st.session_state.setdefault(f"{EDITOR}_version", 0)
    key = f"{EDITOR}_{version}"
    # Status near the front: it's the one editable column, so it must never be
    # the one scrolled off the right edge.
    table = filtered[
        ["alert_id", "ts", "status", "severity", "source", "entity", "title", "incident_id", "mitre_technique"]
    ].reset_index(drop=True)
    table["mitre_technique"] = table["mitre_technique"].fillna("")
    st.data_editor(
        table, key=key, hide_index=True, use_container_width=True,
        disabled=[c for c in table.columns if c != "status"],
        column_config={
            "status": st.column_config.SelectboxColumn("status", options=STATUS_OPTIONS, required=True),
            "alert_id": None,
            "incident_id": st.column_config.TextColumn("incident"),
        },
    )
    changes = [
        (table.iloc[int(i)]["alert_id"], edit["status"])
        for i, edit in st.session_state.get(key, {}).get("edited_rows", {}).items()
        if "status" in edit and edit["status"] != table.iloc[int(i)]["status"]
    ]
    if changes:
        for alert_id, status in changes:
            set_alert_status(alert_id, status)
        st.session_state.pop(key, None)
        st.session_state[f"{EDITOR}_version"] = version + 1
        st.rerun()


def _attack_event_ids() -> set[str]:
    """Synthetic ground truth, used only to warn: detection never reads it."""
    events = get_events()
    return set(events.loc[events["scenario_id"].notna(), "event_id"]) if "scenario_id" in events else set()


def _suppress_form(alert, alerts) -> None:
    """Write a suppression from the selected alert, with a live preview of
    how many current alerts it would match."""
    with st.expander("Suppress alerts like this"):
        st.caption("For known-benign activity: a backup job, an approved scanner, a service account. Matching "
                   "alerts are still stored, as `suppressed`, but open no incident and add no risk.")
        c1, c2 = st.columns(2)
        any_source = c1.toggle("Any detector", value=False, key=f"sup_any::{alert['alert_id']}")
        source = "*" if any_source else alert["source"]
        c1.caption(f"Detector: `{source}`")
        entity = c2.text_input("Entity pattern (`*` wildcards)", value=str(alert["entity"] or "*"),
                               key=f"sup_entity::{alert['alert_id']}")
        reason = st.text_input("Reason (required)", key=f"sup_reason::{alert['alert_id']}",
                               placeholder="e.g. nightly backup to the offsite bucket")
        expiry = st.radio("Expires", list(EXPIRY), index=1, horizontal=True, key=f"sup_exp::{alert['alert_id']}")
        rule = {"source": source, "entity": entity.strip() or "*"}
        matched = [a for a in alerts.to_dict("records") if suppression.matches(a, rule)]
        attack_events = _attack_event_ids()
        real = sum(bool(set(a["event_ids"]) & attack_events) for a in matched)
        st.caption(f"Would match **{len(matched)}** of the {len(alerts)} current alerts.")
        if real:
            st.warning(f"Ground truth: {real} of those {len(matched)} touched injected attack activity. "
                       "This suppression would hide real detections.")
        if st.button("Create suppression", type="primary", disabled=not reason.strip(), key=f"sup_go::{alert['alert_id']}"):
            days = EXPIRY[expiry]
            new_id = add_suppression({**rule, "reason": reason.strip(), "created_from": alert["alert_id"],
                                      "expires_at": datetime.now() + timedelta(days=days) if days else None})
            st.session_state["sup_created"] = new_id
            st.rerun()
    if st.session_state.get("sup_created"):
        st.success(f"{st.session_state['sup_created']} saved. It applies the next time detection runs.")
        if st.button("Re-run detection now", help="Rebuilds alerts and incidents, so incident triage and notes reset."):
            summary = rerun_detection()
            st.session_state.pop("sup_created", None)
            st.toast(f"Detection re-run: {summary['total_alerts']} alerts, {summary['suppressed']} suppressed, "
                     f"{summary['incidents']} incidents.")
            st.rerun()


def render() -> None:
    st.title("Alerts & Triage")
    st.caption("Every individual detection. Change Status inline to triage — or work at the incident level on **Incidents**.")

    if not require_data():
        return
    alerts = get_alerts()
    if alerts.empty:
        st.info("No alerts yet — generate data on the Overview page.")
        return

    f1, f2, f3 = st.columns(3)
    sources = sorted(alerts["source"].unique())
    severities = f1.multiselect("Severity", SEVERITY_ORDER, default=SEVERITY_ORDER)
    chosen_sources = f2.multiselect("Source", sources, default=sources)
    statuses = f3.multiselect("Status", STATUS_OPTIONS, default=STATUS_OPTIONS)

    filtered = alerts[
        alerts["severity"].isin(severities) & alerts["source"].isin(chosen_sources) & alerts["status"].isin(statuses)
    ].sort_values("ts", ascending=False)
    st.caption(f"{len(filtered)} of {len(alerts)} alerts shown.")
    if filtered.empty:
        return
    _editable_table(filtered)
    csv_download(filtered.drop(columns=["event_ids", "entities"]), "alerts.csv")
    suppressed = get_all_alerts()
    suppressed = suppressed[suppressed["status"] == "suppressed"] if "status" in suppressed.columns else suppressed.iloc[0:0]
    if not suppressed.empty:
        with st.expander(f"Suppressed alerts ({len(suppressed)})"):
            st.dataframe(suppressed[["ts", "severity", "source", "entity", "title", "suppressed_by"]],
                         use_container_width=True, hide_index=True)

    st.divider()
    st.subheader("Alert detail")
    labels = {
        row["alert_id"]: f"{row['ts']} · {row['severity'].upper()} · {row['title']} · {row['entity']}"
        for _, row in filtered.iterrows()
    }
    chosen = st.selectbox("Select an alert", list(labels), format_func=labels.get)
    alert = filtered[filtered["alert_id"] == chosen].iloc[0]

    c1, c2 = st.columns([2, 1])
    with c1:
        st.markdown(f"**{alert['title']}**")
        st.write(alert["description"])
        if pd.notna(alert["mitre_technique"]):
            st.caption(f"MITRE ATT&CK: {alert['mitre_tactic']} — {alert['mitre_technique']} ({alert['mitre_technique_name']})")
        if pd.notna(alert.get("score")):
            st.caption(f"Anomaly score: {alert['score']:.3f}")
        entities = alert["entities"] or {}
        parts = [f"{label}: " + ", ".join(f"`{v}`" for v in entities.get(kind, []))
                 for kind, label in (("hosts", "hosts"), ("users", "accounts"), ("ips", "external IPs"))
                 if entities.get(kind)]
        if parts:
            st.markdown("Entities — " + " · ".join(parts))
    with c2:
        st.metric("Severity", alert["severity"].upper())
        st.metric("Incident", alert["incident_id"] if pd.notna(alert["incident_id"]) else "—")

    _suppress_form(alert, alerts)

    if alert["event_ids"]:
        events = get_events()
        related = events[events["event_id"].isin(alert["event_ids"])].sort_values("ts")
        st.caption(f"{len(related)} related raw event(s)")
        st.dataframe(
            related[["ts", "event_type", "user", "host", "src_ip", "dst_ip", "port", "action",
                     "bytes_sent", "domain", "command_line"]],
            use_container_width=True, hide_index=True,
        )
        decoded = decoded_commands(related)
        for _, row in decoded.iterrows():
            st.markdown(f"**Decoded PowerShell** on `{row['host']}` at {row['ts']:%H:%M:%S} — the `-enc` argument is base64 of UTF-16LE text:")
            st.code(row["decoded"], language="powershell", wrap_lines=True)
    else:
        st.caption("No linked raw events.")
