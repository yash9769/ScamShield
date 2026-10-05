from __future__ import annotations

import time

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import INK_MUTED, SERIES, csv_download, get_events, require_data, styled
from socdash import search

STARTER = "event_type=auth outcome=failure | timechart span=1h count by host"
CUSTOM = "Write my own"


def _timechart(result: search.SearchResult) -> go.Figure:
    fig = go.Figure()
    frame = result.frame
    named = [c for c in result.y if c != "OTHER"]
    for column in result.y:
        # Fixed order, never cycled: timechart keeps at most 8 named series
        # (one per categorical slot) and folds the rest into OTHER, which is
        # muted grey and takes no slot.
        color = INK_MUTED if column == "OTHER" else SERIES[named.index(column)]
        fig.add_trace(go.Scatter(
            x=frame[result.x], y=frame[column], name=column, mode="lines", line=dict(color=color, width=2),
            hovertemplate=f"<b>{column}</b><br>%{{x|%d %b %H:%M}}<br>%{{y:,}}<extra></extra>",
        ))
    single = len(result.y) == 1
    fig.update_layout(height=320, showlegend=not single, hovermode="x unified",
                      legend=dict(orientation="h", yanchor="bottom", y=1.02, x=0))
    fig.update_yaxes(title=None if not single else result.y[0], rangemode="tozero")
    return styled(fig)


def _bar(result: search.SearchResult) -> go.Figure:
    top = result.frame.head(20)
    labels = top[result.x].astype(str)
    value = result.y[0]
    fig = go.Figure(go.Bar(
        x=top[value][::-1], y=labels[::-1], orientation="h", marker=dict(color=SERIES[0], cornerradius=4),
        text=[f"{v:,.0f}" if pd.notna(v) else "" for v in top[value][::-1]], textposition="outside",
        hovertemplate="%{y}<br>%{x:,}<extra></extra>",
    ))
    fig.update_layout(height=80 + 26 * len(top), showlegend=False, xaxis_title=value)
    fig.update_yaxes(type="category")
    return styled(fig)


def _help() -> None:
    with st.expander("Syntax"):
        st.markdown(
            "**Search terms** (before the first pipe), ANDed together:\n"
            "- `host=WKS-0014`, `dst_ip=10.10.*` (case-insensitive, `*` wildcards), `outcome!=success`\n"
            "- `bytes_sent>1000000`, `port<=1024`\n"
            "- a bare word or quoted phrase matches any text field: `powershell`, `\"-enc\"`\n"
            "- `NOT term`, `term OR term`, `earliest=-6h`, `latest=-1h` (relative to the newest event)\n\n"
            "**Commands** after `|`:\n"
            "- `stats count, dc(f), sum(f), avg(f), min(f), max(f), median(f), values(f) [as name] by f1, f2`\n"
            "- `timechart span=1h <aggregate> [by f]` (up to 8 series, the rest become OTHER)\n"
            "- `top [limit=N] f [by g]`, `rare [limit=N] f`\n"
            "- `where f > 10 and g = x`, `sort -f, g`, `head N`, `tail N`, `table f1, f2`, `dedup f`, `rename f as g`"
        )
        st.caption("An interpreter over the events table, so a search can only read. Ground-truth columns are dropped before it runs.")


def render() -> None:
    st.title("Search")
    st.caption("Search the raw events with a pipe-based query language in the style of Splunk's SPL: "
               "filter first, then reshape with stats, timechart and top. Charts follow the shape of the result.")
    if not require_data():
        return
    events = get_events()
    if events.empty:
        st.info("No events yet — generate data on the Overview page.")
        return

    names = list(search.SAVED_SEARCHES) + [CUSTOM]
    choice = st.selectbox("Saved searches", names)
    preset = search.SAVED_SEARCHES.get(choice, STARTER)

    st.markdown(
        '<style>[data-testid="stForm"] textarea{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;'
        "font-size:13px;line-height:1.5;}</style>",
        unsafe_allow_html=True,
    )
    with st.form("search"):
        query = st.text_area("Query", value=preset, height=90, key=f"spl::{choice}")
        st.form_submit_button("Search", type="primary")
    _help()

    started = time.perf_counter()
    try:
        result = search.run(events, query)
    except search.SearchError as exc:
        st.error(str(exc))
        return
    elapsed = (time.perf_counter() - started) * 1000

    st.caption(f"{result.matched:,} of {result.scanned:,} events matched · {len(result.frame):,} row(s) · {elapsed:.0f} ms")
    if result.frame.empty:
        st.info("Nothing matched.")
        return
    if result.chart == "timechart" and len(result.frame) > 1:
        st.plotly_chart(_timechart(result), use_container_width=True)
    elif result.chart == "bar" and len(result.frame) > 1:
        st.plotly_chart(_bar(result), use_container_width=True)
    st.dataframe(result.frame, use_container_width=True, hide_index=True)
    csv_download(result.frame, "search_results.csv")
