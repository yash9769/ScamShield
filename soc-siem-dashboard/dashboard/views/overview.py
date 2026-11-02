from __future__ import annotations

import plotly.graph_objects as go
import streamlit as st

from common import (
    EVENT_TYPE_COLOR,
    SERIES,
    SEVERITY_COLOR,
    SEVERITY_ORDER,
    clear_db_caches,
    get_alerts,
    get_events,
    get_incidents,
    get_risk,
    require_data,
    styled,
)
from socdash import pipeline


def _generate_data_panel() -> None:
    with st.expander("Generate / regenerate demo data", expanded=not pipeline.DEFAULT_DB_PATH.exists()):
        st.caption(
            "Builds a synthetic SOC event stream — normal traffic, standalone attack scenarios, and "
            "multi-stage campaigns — then runs the rule engine, the anomaly detector, and alert "
            "correlation over it."
        )
        c1, c2, c3, c4 = st.columns(4)
        days = c1.slider("Days of history", 2, 14, 5)
        scenarios = c2.slider("Standalone attacks", 0, 30, 14)
        campaigns = c3.slider("Multi-stage campaigns", 0, 3, 1)
        seed = c4.number_input("Random seed", value=42, step=1)
        if st.button("Generate demo data", type="primary"):
            with st.spinner("Generating events, running detection, correlating alerts..."):
                result = pipeline.run_pipeline(days=days, scenario_count=scenarios, campaign_count=campaigns, seed=int(seed))
            clear_db_caches()
            st.success(
                f"Generated {result['events']:,} events → {result['rule_alerts']} rule alerts + "
                f"{result['anomaly_alerts']} anomaly alerts → {result['incidents']} incidents."
            )
            st.rerun()


    st.markdown(
        """
        <div style="margin-bottom: 22px;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 6px;">
                <span style="background: rgba(0, 210, 255, 0.12); color: #00d2ff; border: 1px solid rgba(0, 210, 255, 0.3); font-size: 11px; font-weight: 700; padding: 2px 10px; border-radius: 20px; letter-spacing: 0.08em; text-transform: uppercase;">
                    Operational Console
                </span>
                <span style="color: #64748b; font-size: 12px;">Automated Telemetry & Kill-Chain Correlation</span>
            </div>
            <h1 style="font-size: 2.1rem; font-weight: 800; color: #ffffff; margin: 0 0 6px 0; letter-spacing: -0.02em;">
                SOC Overview & Real-Time Intelligence
            </h1>
            <p style="color: #94a3b8; font-size: 13.5px; margin: 0;">
                Synthetic security-operations telemetry evaluated via Sigma rules, Isolation Forest anomaly scoring, and multi-stage campaign correlation.
            </p>
        </div>
        """,
        unsafe_allow_html=True,
    )

    _generate_data_panel()

    if not require_data():
        return

    events = get_events()
    alerts = get_alerts()
    incidents = get_incidents()
    if events.empty:
        st.info("Database exists but has no events yet — generate data above.")
        return

    open_incidents = incidents[incidents["status"].isin(["new", "investigating"])] if not incidents.empty else incidents
    multi_stage = incidents[incidents["tactics"].apply(len) >= 3] if not incidents.empty else incidents
    span_days = max((events["ts"].max() - events["ts"].min()).days, 1)

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Total Events", f"{len(events):,}", help=f"Across {span_days} days of recorded telemetry")
    c2.metric("Triggered Alerts", f"{len(alerts):,}")
    c3.metric("Correlated Incidents", f"{len(incidents):,}",
              help="Alerts grouped by correlation engine into actionable investigations.")
    c4.metric("Active Investigations", f"{len(open_incidents):,}")
    c5.metric("Multi-Stage Campaigns", f"{len(multi_stage):,}", help="High-risk attacks spanning ≥ 3 ATT&CK tactics.")

    st.markdown('<div style="height: 12px;"></div>', unsafe_allow_html=True)
    st.subheader("Event Telemetry Volume over Time")
    bucketed = events.assign(window=events["ts"].dt.floor("6h"))
    counts = bucketed.groupby(["window", "event_type"]).size().reset_index(name="count")
    fig = go.Figure()
    for event_type, color in EVENT_TYPE_COLOR.items():
        sub = counts[counts["event_type"] == event_type]
        fig.add_trace(go.Scatter(
            x=sub["window"], y=sub["count"], mode="lines", name=event_type.upper(),
            line=dict(color=color, width=2.5, shape="spline"),
            hovertemplate="%{x|%b %d, %H:%M}<br>" + event_type.upper() + ": <b>%{y}</b> events<extra></extra>",
        ))
    fig.update_layout(height=320, yaxis_title="events / 6h", legend_title_text="")
    st.plotly_chart(styled(fig), use_container_width=True)

    col_a, col_b = st.columns(2)
    with col_a:
        st.subheader("Alerts by severity")
        if alerts.empty:
            st.caption("No alerts.")
        else:
            sev_counts = alerts["severity"].value_counts().reindex(SEVERITY_ORDER).fillna(0)
            fig2 = go.Figure(go.Bar(
                x=sev_counts.values, y=[s.upper() for s in sev_counts.index], orientation="h",
                marker_color=[SEVERITY_COLOR[s] for s in sev_counts.index],
                text=sev_counts.values.astype(int), textposition="outside",
            ))
            fig2.update_layout(height=280, xaxis_title="alerts", showlegend=False)
            st.plotly_chart(styled(fig2), use_container_width=True)

    with col_b:
        st.subheader("Riskiest entities")
        risk = get_risk()
        if risk.empty:
            st.caption("No alerts.")
        else:
            top = risk.head(10).iloc[::-1]
            fig3 = go.Figure(go.Bar(
                x=top["risk"], y=top["kind"] + ": " + top["entity"], orientation="h",
                marker_color=SERIES[0], text=top["risk"], textposition="outside",
                customdata=top[["alerts", "detectors"]],
                hovertemplate="%{y}<br>risk %{x}<br>%{customdata[0]} alerts from %{customdata[1]} detectors<extra></extra>",
            ))
            fig3.update_layout(height=280, xaxis_title="time-decayed risk", showlegend=False)
            st.plotly_chart(styled(fig3), use_container_width=True)
            st.caption("Each alert adds risk to every host, account and address it involves; risk halves every 24 h.")

    st.subheader("Highest-scoring incidents")
    if incidents.empty:
        st.caption("No incidents yet.")
    else:
        preview = incidents.head(6).assign(tactics=incidents["tactics"].apply(len))
        st.dataframe(
            preview[["incident_id", "severity", "score", "title", "alert_count", "tactics", "first_seen", "status"]],
            use_container_width=True, hide_index=True,
            column_config={
                "alert_count": st.column_config.NumberColumn("alerts"),
                "tactics": st.column_config.NumberColumn("ATT&CK tactics"),
            },
        )
        st.caption("Open **Incidents** for the kill-chain view of each one.")
