from __future__ import annotations

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import (
    INK_MUTED,
    SERIES,
    SEVERITY_COLOR,
    SURFACE,
    add_to_watchlist,
    csv_download,
    db_mtime,
    get_alerts,
    get_events,
    get_watchlist,
    remove_from_watchlist,
    require_data,
    styled,
)
from socdash import intel

DIRECTION_COLOR = {"inbound": SERIES[0], "outbound": SERIES[1], "dns query": SERIES[2]}
SWEEP_KEY = "intel_sweep_values"


@st.cache_data(max_entries=8)
def _matches(mtime: float, watch_values: tuple[str, ...]):
    events, alerts = get_events(), get_alerts()
    indicators = _indicators(watch_values)
    found = intel.sightings(events, indicators)
    return found, intel.summarize(found, indicators, alerts), intel.feed_coverage(events, intel.feed())


def _indicators(watch_values: tuple[str, ...]) -> pd.DataFrame:
    watch = pd.DataFrame({
        "type": [intel.indicator_type(v) for v in watch_values], "value": list(watch_values),
        "source": "watchlist", "confidence": 100, "note": "",
    }, columns=intel.INDICATOR_COLUMNS)
    return pd.concat([watch, intel.feed()], ignore_index=True).drop_duplicates(["type", "value"])


def _activity_chart(found: pd.DataFrame, values: list[str]) -> go.Figure:
    """One row per indicator, one mark per sighting, colored by direction."""
    fig = go.Figure()
    subset = found[found["value"].isin(values)]
    for direction, group in subset.groupby("direction"):
        fig.add_trace(go.Scatter(
            x=group["ts"], y=group["value"], mode="markers", name=direction,
            marker=dict(size=9, color=DIRECTION_COLOR.get(direction, INK_MUTED), line=dict(width=1.5, color=SURFACE)),
            customdata=group[["host", "event_type"]],
            hovertemplate="<b>%{y}</b><br>%{x|%d %b %H:%M:%S}<br>%{customdata[0]} · %{customdata[1]}<extra>" + direction + "</extra>",
        ))
    fig.update_yaxes(categoryorder="array", categoryarray=values[::-1], title=None)
    fig.update_layout(height=60 + 30 * len(values), legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0))
    return styled(fig)


def _sweep_chart(sweep: pd.DataFrame, found: pd.DataFrame) -> go.Figure:
    hosts = sweep.sort_values("first_contact")["host"].drop_duplicates().tolist()
    fig = go.Figure()
    for i, value in enumerate(sweep["value"].drop_duplicates()):
        hits = found[(found["value"] == value) & found["host"].isin(hosts)]
        fig.add_trace(go.Scatter(
            x=hits["ts"], y=hits["host"], mode="markers", name=value,
            marker=dict(size=9, color=SERIES[i], line=dict(width=1.5, color=SURFACE)),
            hovertemplate="<b>%{y}</b> · " + value + "<br>%{x|%d %b %H:%M:%S}<extra></extra>",
        ))
    first = sweep.groupby("host")["first_contact"].min()
    fig.add_trace(go.Scatter(x=first.values, y=first.index, mode="markers", name="first contact",
                             marker=dict(size=16, symbol="line-ns", line=dict(width=2, color=SEVERITY_COLOR["critical"])),
                             hovertemplate="<b>%{y}</b> first contact<br>%{x|%d %b %H:%M:%S}<extra></extra>"))
    fig.update_yaxes(categoryorder="array", categoryarray=hosts[::-1], title=None)
    fig.update_layout(height=80 + 30 * len(hosts), legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0))
    return styled(fig)


def _domains_chart(domains: pd.DataFrame) -> go.Figure:
    domains = domains.iloc[::-1]
    fig = go.Figure(go.Bar(
        x=domains["score"], y=domains["domain"], orientation="h", marker=dict(color=SERIES[0], cornerradius=4),
        text=[f"{s:.2f} · {h} host{'s' if h != 1 else ''}" for s, h in zip(domains["score"], domains["hosts"])],
        textposition="outside", customdata=domains[["queries", "hosts"]],
        hovertemplate="<b>%{y}</b><br>score %{x:.2f}<br>%{customdata[0]} queries from %{customdata[1]} host(s)<extra></extra>",
    ))
    fig.update_layout(height=80 + 26 * len(domains), showlegend=False,
                      xaxis=dict(range=[0, 1.15], title="how machine-generated the name looks (0–1)"))
    return styled(fig)


def render() -> None:
    st.title("Threat Intel")
    st.caption("Known-bad indicators matched against every event, an analyst watchlist, retro-hunting "
               "(who else touched this, and since when?), and scoring for algorithmically generated domains.")
    if not require_data():
        return
    events = get_events()
    if events.empty:
        st.info("No events yet — generate data on the Overview page.")
        return

    watch = get_watchlist()
    found, summary, coverage = _matches(db_mtime(), tuple(sorted(watch["value"])))

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Feed indicators", len(intel.feed()))
    c2.metric("Watchlist", len(watch))
    c3.metric("Indicators seen", len(summary), help=f"{len(found):,} matching events")
    c4.metric("Attack IPs the feed knew", f"{coverage['listed']} / {coverage['attack_ips']}",
              help="Ground truth: of the external addresses used in injected attacks, how many the feed already listed.")

    st.subheader("Indicator matches")
    if summary.empty:
        st.info("No event touched a listed indicator.")
    else:
        top = summary.sort_values("events", ascending=False)["value"].head(12).tolist()
        st.plotly_chart(_activity_chart(found, top), use_container_width=True)
        st.dataframe(
            summary.assign(alerted=summary["alerted"].map({True: "yes", False: "no"})),
            use_container_width=True, hide_index=True,
            column_config={"alerted": st.column_config.TextColumn("covered by an alert"),
                           "confidence": st.column_config.NumberColumn(format="%d")},
        )
        st.caption(
            "Indicators seen but never covered by an alert are the ones to read first. Here most of them are an "
            "artifact of the generator: its background traffic picks external peers uniformly, so listed addresses "
            "turn up in ordinary sessions far more than they would on a real network."
        )

    st.subheader("Retro-hunt")
    st.caption("Search every event, not just alerted ones, for hosts that touched an indicator — and when that started.")
    # Watchlist first, then matches with alert coverage (most events first):
    # the default sweep should be an indicator someone already cares about.
    ranked = summary.sort_values(["alerted", "events"], ascending=[False, False]) if not summary.empty else summary
    known = list(dict.fromkeys(list(watch["value"]) + ranked.get("value", pd.Series(dtype=str)).tolist()))
    default = st.session_state.get(SWEEP_KEY) or list(watch["value"])[:8] or known[:1]
    chosen = st.multiselect("Indicators", known, default=[v for v in default if v in known][:8], max_selections=8)
    extra = st.text_input("Or paste indicators (comma-separated)", placeholder="e.g. 203.0.113.9, evil.example.info")
    values = list(dict.fromkeys(chosen + [v.strip() for v in extra.split(",") if v.strip()]))
    if len(values) > 8:
        st.caption(f"Sweeping the first 8 of {len(values)} indicators, one color each.")
        values = values[:8]
    sweep = intel.sweep(events, values)
    if values and sweep.empty:
        st.info("No event touched those indicators.")
    elif not sweep.empty:
        swept = intel.sightings(events, pd.DataFrame({"type": [intel.indicator_type(v) for v in values], "value": values}))
        m1, m2, m3 = st.columns(3)
        m1.metric("Hosts that touched them", sweep["host"].nunique())
        m2.metric("Events", int(sweep["events"].sum()))
        m3.metric("First contact", f"{sweep['first_contact'].min():%d %b %H:%M}")
        st.plotly_chart(_sweep_chart(sweep, swept), use_container_width=True)
        st.dataframe(sweep, use_container_width=True, hide_index=True)
        csv_download(sweep, "retro_hunt.csv")

    st.subheader("Watchlist")
    with st.form("watch_add", clear_on_submit=True):
        a1, a2, a3 = st.columns([2, 3, 1], vertical_alignment="bottom")
        value = a1.text_input("Indicator", placeholder="IP address or domain")
        note = a2.text_input("Note", placeholder="Why it's here")
        if a3.form_submit_button("Add", use_container_width=True) and value.strip():
            add_to_watchlist([{"value": value.strip(), "type": intel.indicator_type(value.strip()), "note": note or None}])
            st.rerun()
    if watch.empty:
        st.caption("Empty. Add indicators here, or from an incident's IOC table.")
    else:
        st.dataframe(watch, use_container_width=True, hide_index=True)
        doomed = st.multiselect("Remove", watch["value"].tolist(), key="watch_remove")
        if doomed and st.button(f"Remove {len(doomed)} indicator(s)"):
            remove_from_watchlist(doomed)
            st.rerun()

    st.subheader("Suspicious domains")
    domains = intel.suspicious_domains(events)
    if not domains.empty:
        st.plotly_chart(_domains_chart(domains), use_container_width=True)
        st.caption("Malware that rotates through generated names (DGA) leaves high-entropy, digit-heavy labels. "
                   "One querying host and many queries is the beacon shape. Real DNS has CDN and tracking "
                   "hosts that score high too, so this ranks names for review rather than alerting.")
