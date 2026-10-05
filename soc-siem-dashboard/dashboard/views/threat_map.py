from __future__ import annotations

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import SERIES, SEVERITY_COLOR, get_events, ip_country_lookup, ip_malicious_lookup, require_data, styled


def _country_activity(events: pd.DataFrame) -> pd.DataFrame:
    """One row per country: total events touching it, and whether any of
    those events involved an IP flagged known_malicious in the entity pool."""
    ip_country = ip_country_lookup()
    ip_malicious = ip_malicious_lookup()
    rows = []

    auth = events[(events["event_type"] == "auth") & events["src_country"].notna()]
    for country, g in auth.groupby("src_country"):
        rows.append({"country": country, "count": len(g), "malicious": False})

    net = events[events["event_type"] == "network"]
    outbound = net[net["direction"] == "outbound"]
    inbound = net[net["direction"] == "inbound"]
    for ip_col, sub in (("dst_ip", outbound), ("src_ip", inbound)):
        sub = sub.copy()
        sub["country"] = sub[ip_col].map(ip_country)
        sub["malicious"] = sub[ip_col].map(ip_malicious).fillna(False)
        sub = sub.dropna(subset=["country"])
        for (country, malicious), g in sub.groupby(["country", "malicious"]):
            rows.append({"country": country, "count": len(g), "malicious": bool(malicious)})

    if not rows:
        return pd.DataFrame(columns=["country", "count", "malicious"])
    df = pd.DataFrame(rows)
    return df.groupby("country").agg(count=("count", "sum"), malicious=("malicious", "any")).reset_index()


def render() -> None:
    st.title("Threat Map")
    st.caption("Where our traffic actually goes, and which countries any known-malicious source IP touched.")

    if not require_data():
        return

    events = get_events()
    if events.empty:
        st.info("No events yet — generate data on the Overview page.")
        return

    agg = _country_activity(events)
    if agg.empty:
        st.info("No geo-taggable traffic in this dataset.")
        return

    agg = agg.sort_values("count")
    colors = [SEVERITY_COLOR["critical"] if m else SERIES[0] for m in agg["malicious"]]
    fig = go.Figure(go.Bar(
        x=agg["count"], y=agg["country"], orientation="h", marker_color=colors,
        text=agg["count"], textposition="outside",
    ))
    fig.update_layout(height=max(320, 28 * len(agg)), xaxis_title="events", showlegend=False)
    st.plotly_chart(styled(fig), use_container_width=True)
    st.caption("Bars in red carried traffic from at least one IP flagged known-malicious; the rest are normal traffic only.")

    st.subheader("Countries with known-malicious activity")
    flagged = agg[agg["malicious"]].sort_values("count", ascending=False)
    if flagged.empty:
        st.caption("None in this dataset.")
    else:
        st.dataframe(
            flagged[["country", "count"]].rename(columns={"count": "events"}),
            use_container_width=True, hide_index=True,
        )
