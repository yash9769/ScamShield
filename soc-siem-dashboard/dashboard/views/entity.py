from __future__ import annotations

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import (
    EVENT_TYPE_COLOR,
    INK_MUTED,
    SEQUENTIAL_BLUE,
    SERIES,
    SEVERITY_COLOR,
    csv_download,
    get_alerts,
    get_events,
    get_incidents,
    get_risk,
    require_data,
    styled,
)
from socdash.generator.entities import HOSTS_BY_NAME

ZERO = "#f1f0ec"  # empty cells recede toward the surface instead of reading as "a little activity"


def _colorscale() -> list:
    steps = [[0.0, ZERO], [1e-6, SEQUENTIAL_BLUE[0]]]
    steps += [[i / (len(SEQUENTIAL_BLUE) - 1), c] for i, c in enumerate(SEQUENTIAL_BLUE) if i > 0]
    return steps


def _heatmap(mine: pd.DataFrame, involved: pd.DataFrame, all_days: pd.DatetimeIndex) -> go.Figure:
    labels = [d.strftime("%a %d %b") for d in all_days]
    grid = (
        mine.assign(day=mine["ts"].dt.floor("D"), hour=mine["ts"].dt.hour)
        .groupby(["day", "hour"]).size().unstack(fill_value=0)
        .reindex(index=all_days, columns=range(24), fill_value=0)
    )
    fig = go.Figure(go.Heatmap(
        z=grid.values, x=list(range(24)), y=labels, colorscale=_colorscale(), xgap=2, ygap=2,
        colorbar=dict(title="events", thickness=12),
        hovertemplate="%{y}, %{x}:00<br>%{z} events<extra></extra>",
    ))
    if not involved.empty:
        hours = involved.assign(day=involved["ts"].dt.floor("D"), hour=involved["ts"].dt.hour)
        hours = hours[hours["day"].isin(all_days)]
        fig.add_trace(go.Scatter(
            x=hours["hour"], y=hours["day"].dt.strftime("%a %d %b"), mode="markers", showlegend=False,
            marker=dict(symbol="square-open", size=16, color=SEVERITY_COLOR["critical"], line=dict(width=2)),
            customdata=hours[["title", "severity"]],
            hovertemplate="<b>%{customdata[0]}</b><br>%{customdata[1]}<extra></extra>",
        ))
    fig.update_yaxes(autorange="reversed", type="category", categoryorder="array", categoryarray=labels)
    fig.update_xaxes(title="hour of day", dtick=2)
    fig.update_layout(height=60 + 34 * len(all_days))
    return styled(fig)


def _peer_chart(daily: pd.DataFrame, col: str, entity: str, peers: list[str], all_days, peer_label: str) -> go.Figure:
    per_peer = (
        daily[daily[col].isin(peers)].groupby(["day", col]).size().unstack(fill_value=0)
        .reindex(index=all_days, columns=peers, fill_value=0)
    )
    mine = daily[daily[col] == entity].groupby("day").size().reindex(all_days, fill_value=0)
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=all_days, y=per_peer.median(axis=1), name=f"median of {peer_label}",
                             mode="lines", line=dict(color=INK_MUTED, width=2, dash="dash")))
    fig.add_trace(go.Scatter(x=all_days, y=mine, name=entity, mode="lines+markers",
                             line=dict(color=SERIES[0], width=2), marker=dict(size=8)))
    fig.update_layout(height=300, yaxis_title="events / day", legend=dict(orientation="h", y=1.15, x=0, title_text=""))
    return styled(fig)


def render() -> None:
    st.title("Entity Investigation")
    st.caption("Everything about one host or account: its risk, how it behaves over time, how it compares to its peers, and every alert and incident it's part of.")
    if not require_data():
        return
    events, alerts, incidents, risk = get_events(), get_alerts(), get_incidents(), get_risk()
    if events.empty:
        st.info("No events yet — generate data on the Overview page.")
        return

    kind = st.radio("Investigate a", ["host", "user"], horizontal=True, format_func=lambda k: "host" if k == "host" else "account")
    col = kind
    kind_risk = risk[risk["kind"] == kind].set_index("entity")["risk"] if not risk.empty else pd.Series(dtype=float)
    candidates = sorted(events[col].dropna().unique(), key=lambda e: (-kind_risk.get(e, 0.0), e))
    entity = st.selectbox("Riskiest first", candidates, format_func=lambda e: f"{e}  ·  risk {kind_risk.get(e, 0.0):g}")

    mine = events[events[col] == entity]
    involved = alerts[alerts["entities"].apply(lambda d: entity in (d or {}).get(f"{kind}s", []))] if not alerts.empty else alerts
    my_incidents = incidents[incidents["incident_id"].isin(involved["incident_id"].dropna())] if not incidents.empty else incidents
    rank = list(kind_risk.index).index(entity) + 1 if entity in kind_risk.index else None

    if kind == "host":
        role = HOSTS_BY_NAME[entity].role if entity in HOSTS_BY_NAME else "unknown"
        peers = [h for h, info in HOSTS_BY_NAME.items() if info.role == role and h != entity]
        peer_label = f"other {role.replace('_', ' ')} hosts" if peers else "all hosts"
        peers = peers or [h for h in HOSTS_BY_NAME if h != entity]
        subtitle = f"{role.replace('_', ' ')} · {HOSTS_BY_NAME[entity].ip}" if entity in HOSTS_BY_NAME else ""
    else:
        peers = [u for u in events["user"].dropna().unique() if u != entity]
        peer_label = "all other accounts"
        subtitle = "service / admin account" if entity.startswith(("svc-", "admin")) else "user account"
    st.caption(subtitle)

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Risk", f"{kind_risk.get(entity, 0.0):g}", help=f"Rank #{rank} of {len(kind_risk)} {kind}s with any risk" if rank else "No alerts involve this entity")
    c2.metric("Alerts", len(involved))
    c3.metric("Incidents", len(my_incidents))
    c4.metric("Events", f"{len(mine):,}")

    all_days = pd.date_range(events["ts"].min().floor("D"), events["ts"].max().floor("D"), freq="D")
    st.subheader("Activity by hour")
    st.plotly_chart(_heatmap(mine, involved, all_days), use_container_width=True)
    st.caption("Darker = more events. Red outlines mark hours with an alert involving this entity.")

    col_a, col_b = st.columns([3, 2])
    with col_a:
        st.subheader("Compared to peers")
        daily = events.assign(day=events["ts"].dt.floor("D"))
        st.plotly_chart(_peer_chart(daily, col, entity, peers, all_days, peer_label), use_container_width=True)
        st.caption("The first and last days are partial (the dataset starts and ends mid-day), so both lines dip there.")
    with col_b:
        st.subheader("Event mix")
        mix = mine["event_type"].value_counts()
        fig = go.Figure(go.Bar(
            x=mix.values, y=mix.index, orientation="h", text=mix.values, textposition="outside",
            marker_color=[EVENT_TYPE_COLOR.get(t, INK_MUTED) for t in mix.index],
        ))
        fig.update_layout(height=300, xaxis_title="events", showlegend=False)
        st.plotly_chart(styled(fig), use_container_width=True)

    st.subheader("Incidents")
    if my_incidents.empty:
        st.caption("Not part of any incident.")
    else:
        st.dataframe(my_incidents[["incident_id", "severity", "score", "title", "alert_count", "first_seen", "status"]],
                     use_container_width=True, hide_index=True)

    st.subheader("Alerts")
    if involved.empty:
        st.caption("No alerts involve this entity.")
    else:
        st.dataframe(involved.sort_values("ts")[["ts", "severity", "source", "title", "description", "incident_id"]],
                     use_container_width=True, hide_index=True)

    st.subheader("Raw events")
    st.dataframe(mine.sort_values("ts", ascending=False).head(300)[
        ["ts", "event_type", "user", "host", "src_ip", "dst_ip", "action", "bytes_sent", "domain", "command_line"]
    ], use_container_width=True, hide_index=True)
    csv_download(mine.drop(columns=["scenario_tag", "scenario_id", "campaign_id"]), f"{entity}_events.csv",
                 label=f"Download all {len(mine):,} events")
