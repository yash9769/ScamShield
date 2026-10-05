from __future__ import annotations

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import SERIES, db_mtime, get_events, require_data, styled
from socdash.detection import anomaly


@st.cache_data(max_entries=16)
def _score(mtime: float, contamination: float):
    events = get_events()
    if events.empty:
        return events, events
    feat = anomaly.extract_features(events)
    scored = anomaly.score_anomalies(feat, contamination=contamination)
    return events, scored


def render() -> None:
    st.title("Anomaly Detection")
    st.caption(
        "Sigma-style rules catch known signatures. This catches the thing with no single "
        "bad event — DNS beaconing is just many ordinary-looking queries at a suspiciously "
        "regular interval. Every host-hour gets a behavioral feature vector; an Isolation "
        "Forest scores how unusual it is relative to every other host-hour."
    )

    if not require_data():
        return

    contamination = st.slider(
        "Contamination (expected fraction of host-hours that are anomalous)",
        0.01, 0.15, 0.03, 0.01,
    )
    events, scored = _score(db_mtime(), contamination)
    if events.empty:
        st.info("No events yet — generate data on the Overview page.")
        return

    n_anom = int(scored["is_anomaly"].sum())
    c1, c2, c3 = st.columns(3)
    c1.metric("Host-hours scored", len(scored))
    c2.metric("Flagged anomalous", n_anom)
    c3.metric("Flag rate", f"{n_anom / max(len(scored), 1) * 100:.1f}%")

    alerts = anomaly.generate_anomaly_alerts(scored, events, top_n=25)
    if not alerts:
        st.info("Nothing flagged at this contamination level — try raising the slider.")
        return

    st.subheader("Top anomalies")
    table = pd.DataFrame([{
        "when": a["ts"], "host": a["entity"], "score": round(a["score"], 3),
        "severity": a["severity"], "reason": a["description"],
    } for a in alerts])
    st.dataframe(table, use_container_width=True, hide_index=True)

    st.subheader("Why this one? Feature comparison")
    choice = st.selectbox(
        "Pick a flagged host-hour",
        range(len(alerts)),
        format_func=lambda i: f"{alerts[i]['ts']} · {alerts[i]['entity']} · score {alerts[i]['score']:.2f}",
    )
    chosen = alerts[choice]
    row = scored[(scored["host"] == chosen["entity"]) & (scored["bucket"] == chosen["ts"])]
    if not row.empty:
        row = row.iloc[0]
        baseline = scored[anomaly.FEATURE_COLS].mean()
        # Raw features span wildly different units (byte counts in the
        # hundreds of thousands next to port counts under 10) — plotting
        # them together on one linear axis would bury everything except
        # bytes. Normalizing to "multiples of the dataset average" puts
        # every feature on one comparable, honest axis instead.
        cols = [c for c in anomaly.FEATURE_COLS if c != "dns_interval_std"]
        ratios = [row[c] / baseline[c] if baseline[c] > 0 else (0.0 if row[c] == 0 else float("inf")) for c in cols]
        capped = [min(r, 10) for r in ratios]
        labels = [("off the chart" if r == float("inf") else f"{r:.1f}×") for r in ratios]
        fig = go.Figure(go.Bar(
            x=cols, y=capped, marker_color=SERIES[0], text=labels, textposition="outside",
        ))
        fig.add_hline(y=1, line_dash="dash", line_color="#898781")
        fig.update_layout(height=340, yaxis_title="× dataset average", showlegend=False)
        st.plotly_chart(styled(fig), use_container_width=True)
        if row["dns_interval_std"] >= anomaly.NO_SIGNAL_STD:
            regularity = "not measurable — fewer than 3 DNS queries this hour"
        else:
            regularity = f"{row['dns_interval_std']:.1f}s (lower = more regular = more beacon-like)"
        st.caption(f"Dashed line = the dataset average (1×); bars are capped at 10×. DNS query interval std-dev: {regularity}.")
