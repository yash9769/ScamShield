from __future__ import annotations

from datetime import datetime

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import (
    SERIES,
    SEVERITY_COLOR,
    SURFACE,
    db_mtime,
    get_events,
    require_data,
    styled,
)
from socdash import live

STATE = "live_sim"
TICK_SECONDS = 1.5


@st.cache_resource(max_entries=2)
def _trained(mtime: float):
    return live.train_from_history(get_events())


def _new_simulator(attack_probability: float) -> live.LiveSimulator:
    model, high_cut = _trained(db_mtime())
    start = datetime.now().replace(second=0, microsecond=0)
    sim = live.LiveSimulator(start, model=model, high_cut=high_cut, attack_probability=attack_probability)
    for _ in range(12):  # an hour of warm-up so the chart isn't empty on arrival
        sim.step(5)
    return sim


def _rate_chart(sim: live.LiveSimulator) -> go.Figure:
    rate = sim.rate_frame()
    fig = go.Figure(go.Scatter(
        x=rate["bucket"], y=rate["events"], mode="lines", line=dict(color=SERIES[0], width=2, shape="spline", smoothing=0.6),
        fill="tozeroy", fillcolor="rgba(42,120,214,0.10)", name="events / 5 min",
        hovertemplate="%{x|%H:%M}<br>%{y} events in 5 min<extra></extra>",
    ))
    alerts = sim.alerts_frame()
    if not alerts.empty and not rate.empty:
        alerts = alerts[alerts["detected_at"] >= rate["bucket"].min()]
        top = max(rate["events"].max(), 1) * 1.15
        fig.add_trace(go.Scatter(
            x=alerts["detected_at"], y=[top] * len(alerts), mode="markers", name="alerts",
            marker=dict(size=12, symbol="triangle-down", color=[SEVERITY_COLOR[s] for s in alerts["severity"]],
                        line=dict(width=2, color=SURFACE)),
            customdata=alerts[["title", "entity", "severity", "source"]],
            hovertemplate="<b>%{customdata[0]}</b><br>%{customdata[1]}<br>%{customdata[2]} · %{customdata[3]}"
                          "<br>raised %{x|%H:%M}<extra></extra>",
        ))
    fig.update_layout(height=280, showlegend=False, margin=dict(l=10, r=20, t=10, b=10))
    fig.update_yaxes(title=None, rangemode="tozero")
    fig.update_xaxes(title=None)
    return styled(fig)


def _dashboard(sim: live.LiveSimulator) -> None:
    alerts = sim.alerts_frame()
    injections = sim.injections_frame()
    caught = injections["detected_at"].notna().sum()
    tp = int(alerts["true_positive"].sum()) if not alerts.empty else 0

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Simulated clock", f"{sim.clock:%H:%M}", help=f"{sim.clock:%a %d %b %Y}")
    c2.metric("Events ingested", f"{sim.event_total:,}")
    c3.metric("Alerts raised", len(alerts), help=f"{tp} touched injected attack activity, {len(alerts) - tp} did not")
    c4.metric("Attacks caught", f"{caught} / {len(injections)}" if len(injections) else "—",
              help="Injected scenarios with at least one alert on their events so far — "
                   "one still unfolding may not have crossed a threshold yet.")
    ttd = injections["minutes_to_detect"].median()
    c5.metric("Median time to detect", f"{ttd:.0f} min" if pd.notna(ttd) else "—")

    st.plotly_chart(_rate_chart(sim), use_container_width=True, key="live_rate")
    st.caption("Events per 5 minutes over the last three simulated hours · ▼ alerts, colored by severity, "
               "at the moment they were raised.")

    left, right = st.columns([3, 2])
    with left:
        st.markdown("**Alert feed**")
        if alerts.empty:
            st.caption("Nothing yet.")
        else:
            st.dataframe(
                alerts.head(12).assign(raised=alerts["detected_at"].dt.strftime("%H:%M"),
                                       verdict=alerts["true_positive"].map({True: "attack", False: "benign"}))[
                    ["raised", "severity", "source", "entity", "verdict"]],
                use_container_width=True, hide_index=True,
            )
    with right:
        st.markdown("**Injected attacks** — ground truth the detectors never see")
        if injections.empty:
            st.caption("None injected yet.")
        else:
            view = injections.sort_values("started", ascending=False).head(12)
            st.dataframe(
                view.assign(
                    started=view["started"].dt.strftime("%H:%M"),
                    caught=view["detected_by"].fillna("— not yet"),
                    after=view["minutes_to_detect"].map(lambda m: f"{m:.0f} min" if pd.notna(m) else ""),
                )[["started", "scenario", "caught", "after"]],
                use_container_width=True, hide_index=True,
            )


def render() -> None:
    st.title("Live Monitor")
    st.caption(
        "The pipeline as a stream. Events arrive minute by minute, rules run on a rolling 90-minute "
        "buffer, and the anomaly model — trained once on the stored history — scores each host-hour "
        "as it closes. Attacks are injected at random; the right-hand table is the answer key."
    )
    if not require_data():
        return
    if get_events().empty:
        st.info("No stored events to train the anomaly model on — generate data on the Overview page.")
        return

    c1, c2, c3, c4 = st.columns([1, 1, 2, 1], vertical_alignment="bottom")
    running = c1.toggle("Running", value=st.session_state.get("live_running", False), key="live_running")
    speed = c2.selectbox("Simulated minutes per tick", [1, 5, 15], index=1)
    attack_probability = c3.slider("Attack probability per tick", 0.0, 0.5, 0.15, 0.05)
    if c4.button("Reset", use_container_width=True) or STATE not in st.session_state:
        st.session_state[STATE] = _new_simulator(attack_probability)
    sim: live.LiveSimulator = st.session_state[STATE]
    sim.attack_probability = attack_probability

    @st.fragment(run_every=TICK_SECONDS if running else None)
    def tick() -> None:
        if running:
            sim.step(speed)
        _dashboard(sim)

    tick()
    if not running:
        st.caption(f"Paused. Switch on **Running** to advance the clock {speed} simulated minute(s) every {TICK_SECONDS:g} s.")
    st.caption(f"Anomaly scoring raises at most {live.ANOMALY_BUDGET_PER_HOUR} alerts per closed hour; "
               "its alerts can only appear on the hour, which is why beaconing takes longer to catch than a brute force.")
