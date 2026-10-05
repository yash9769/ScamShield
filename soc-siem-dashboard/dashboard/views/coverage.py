from __future__ import annotations

import html

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import (
    DB_PATH,
    DETECTOR_COLOR,
    GRIDLINE,
    INK_MUTED,
    INK_SECONDARY,
    OUTCOME_COLOR,
    SERIES,
    SEVERITY_COLOR,
    clear_db_caches,
    csv_download,
    get_evaluation,
    require_data,
    styled,
    technique_label,
)
from socdash import evaluation, mitre, navigator, pipeline

TTD_TICKS = ([1, 10, 60, 600, 3600, 4 * 3600], ["1 s", "10 s", "1 min", "10 min", "1 h", "4 h"])


def _matrix_order(frame: pd.DataFrame) -> pd.DataFrame:
    """Sort techniques the way the ATT&CK matrix reads, so every chart and the
    grid below list them in the same order."""
    rank = frame["technique"].map(lambda t: mitre.tactic_rank(mitre.describe(t)["tactic"]))
    return frame.assign(_rank=rank).sort_values(["_rank", "technique"]).drop(columns="_rank")


def _outcome_chart(techniques: pd.DataFrame) -> go.Figure:
    techniques = _matrix_order(techniques).iloc[::-1]  # Plotly draws the first category at the bottom
    labels = techniques["technique"].map(technique_label)
    fig = go.Figure()
    for outcome in evaluation.OUTCOMES:
        fig.add_trace(go.Bar(
            y=labels, x=techniques[outcome], name=outcome, orientation="h",
            marker=dict(color=OUTCOME_COLOR[outcome], line=dict(color="#fcfcfb", width=2)),
            hovertemplate="%{y}<br>" + outcome + ": %{x} instance(s)<extra></extra>",
        ))
    styled(fig)
    fig.update_layout(barmode="stack", height=70 + 44 * len(techniques), xaxis_title="injected attack instances",
                      legend=dict(orientation="h", y=1.1, x=0, title_text="", traceorder="normal"))
    return fig


def _ttd_chart(outcomes: pd.DataFrame) -> go.Figure:
    caught = _matrix_order(outcomes[outcomes["detected"]]).iloc[::-1].copy()
    caught["ttd_s"] = (caught["ttd_minutes"] * 60).clip(lower=1)
    caught["label"] = caught["technique"].map(technique_label)
    fig = go.Figure()
    for detector, name in (("rule", "first caught by a rule"), ("anomaly", "first caught by anomaly detection")):
        sub = caught[caught["first_detector"] == detector]
        if sub.empty:
            continue
        fig.add_trace(go.Box(
            x=sub["ttd_s"], y=sub["label"], name=name, orientation="h", boxpoints="all", jitter=0.4, pointpos=0,
            marker=dict(color=DETECTOR_COLOR[detector], size=8), line=dict(color=DETECTOR_COLOR[detector]),
            fillcolor="rgba(0,0,0,0)",
        ))
    fig.update_xaxes(type="log", tickvals=TTD_TICKS[0], ticktext=TTD_TICKS[1],
                     title="time from an attack's first event to its first alert (log scale)")
    fig.update_yaxes(categoryorder="array", categoryarray=list(dict.fromkeys(caught["label"])))
    styled(fig)
    fig.update_layout(boxmode="group", height=90 + 46 * caught["label"].nunique(),
                      legend=dict(orientation="h", y=1.12, x=0, title_text=""))
    return fig


def _coverage_grid(coverage: pd.DataFrame) -> str:
    """One column per tactic in matrix order, as a fixed grid (wrapping flex
    stretched whatever landed on the last row to full width)."""
    tactics = [t for t in mitre.TACTIC_ORDER if t in set(coverage["tactic"])]
    columns = []
    for tactic in tactics:
        cards = []
        for _, row in coverage[coverage["tactic"] == tactic].iterrows():
            if not row["detectors"]:
                border, background, status = f"1px dashed {INK_MUTED}", "transparent", "no detector — gap"
            elif row["injected"] and row["caught"] < row["injected"]:
                border, background, status = f"2px solid {SEVERITY_COLOR['critical']}", "#fff", f"caught {row['caught']}/{row['injected']} injected"
            elif row["injected"]:
                border, background, status = f"2px solid {SERIES[0]}", "#fff", f"caught {row['caught']}/{row['injected']} injected"
            else:
                border, background, status = f"1px solid {GRIDLINE}", "#fff", "not exercised in this dataset"
            detectors = ", ".join(row["detectors"]) or "—"
            cards.append(
                f'<div style="border:{border};background:{background};border-radius:8px;padding:8px 10px;margin-bottom:6px;">'
                f'<div style="font-weight:600;font-size:13px;">{html.escape(row["technique"])}</div>'
                f'<div style="font-size:12px;line-height:1.3;margin-bottom:4px;">{html.escape(row["name"])}</div>'
                f'<div style="font-size:11px;color:{INK_SECONDARY};">{html.escape(detectors)}</div>'
                f'<div style="font-size:11px;color:{INK_SECONDARY};">{row["alerts"]} alerts · {html.escape(status)}</div>'
                "</div>"
            )
        columns.append(
            "<div>"
            f'<div style="font-size:11px;font-weight:600;color:{INK_MUTED};text-transform:uppercase;'
            f'letter-spacing:.04em;margin-bottom:6px;min-height:28px;">{html.escape(tactic)}</div>'
            + "".join(cards) + "</div>"
        )
    return (f'<div style="display:grid;grid-template-columns:repeat({len(tactics)},minmax(0,1fr));gap:8px;">'
            + "".join(columns) + "</div>")


def _tuning_panel() -> None:
    with st.expander("Re-run detection with different settings"):
        st.caption("Re-scores the stored events and replaces every alert and incident (triage statuses reset).")
        c1, c2 = st.columns(2)
        contamination = c1.slider("Anomaly contamination", 0.01, 0.15, 0.03, 0.01, key="cov_contamination")
        window = c2.slider("Correlation window (hours)", 0.5, 12.0, 3.0, 0.5, key="cov_window")
        if st.button("Re-run detection"):
            with st.spinner("Re-running rules, anomaly detection and correlation..."):
                result = pipeline.detect_and_store(DB_PATH, anomaly_contamination=contamination, link_window_hours=window)
            clear_db_caches()
            st.success(f"{result['total_alerts']} alerts → {result['incidents']} incidents.")
            st.rerun()


def render() -> None:
    st.title("Detection Coverage")
    st.caption(
        "Every attack in the synthetic dataset is labeled at generation time, so detection can be "
        "graded like a test: what was caught, by what, how fast, and how cleanly correlation told the "
        "story. Note that an anomaly alert is credited with any attack active on its host that hour, "
        "so anomaly-detection credit is an upper bound."
    )
    if not require_data():
        return
    ev = get_evaluation()
    outcomes, techniques, precision = ev["outcomes"], ev["techniques"], ev["precision"]
    if outcomes.empty:
        st.info("No injected attacks in this dataset — regenerate with standalone attacks or campaigns on the Overview page.")
        return

    _tuning_panel()

    campaigns = ev["campaigns"]
    alerts_total = int(precision["alerts"].sum())
    tp_total = int(precision["true_positives"].sum())
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Attack instances injected", len(outcomes))
    c2.metric("Detected", f"{outcomes['detected'].mean():.0%}", help=f"{int(outcomes['detected'].sum())} of {len(outcomes)}")
    c3.metric("Alert precision", f"{tp_total / alerts_total:.0%}" if alerts_total else "—",
              help=f"{tp_total} of {alerts_total} alerts touched injected attack activity")
    c4.metric("Campaigns reconstructed", f"{int(campaigns['reconstructed'].sum())} / {len(campaigns)}" if not campaigns.empty else "—",
              help="Campaigns whose detected stages all landed in a single incident")

    st.subheader("What caught each technique")
    st.plotly_chart(_outcome_chart(techniques), use_container_width=True)

    st.subheader("Time to detect")
    st.plotly_chart(_ttd_chart(outcomes), use_container_width=True)
    st.caption("Anomaly scoring is an hourly batch, so it can't fire until the hour closes — that latency is the price of catching what no rule describes.")

    st.subheader("Precision by detector")
    p = precision.sort_values("precision")
    fig = go.Figure(go.Bar(
        x=p["precision"], y=p["source"], orientation="h", marker_color=SERIES[0],
        text=[f"{tp} of {n}" for tp, n in zip(p["true_positives"], p["alerts"])], textposition="outside",
    ))
    fig.update_layout(height=70 + 36 * len(p), showlegend=False,
                      xaxis=dict(range=[0, 1.12], tickformat=".0%", title="share of alerts that touched real attack activity"))
    st.plotly_chart(styled(fig), use_container_width=True)

    st.subheader("MITRE ATT&CK coverage")
    st.caption("Blue: injected and fully caught · red: injected, some missed · dashed: no detector at all — a known blind spot.")
    st.markdown(_coverage_grid(ev["coverage"]), unsafe_allow_html=True)
    st.download_button(
        "Download ATT&CK Navigator layer (JSON)", navigator.layer_json(ev["coverage"]).encode("utf-8"),
        file_name="soc-dashboard-coverage-layer.json", mime="application/json",
    )
    st.caption("Open it at mitre-attack.github.io/attack-navigator → *Open Existing Layer* → *Upload from local*. "
               "Each technique is shaded by measured recall; detectors and counts are in its comment.")

    st.subheader("Correlation quality")
    purity = ev["purity"]
    q1, q2 = st.columns(2)
    with q1:
        st.markdown("**Campaigns** — did correlation reassemble each multi-stage attack?")
        if campaigns.empty:
            st.caption("No multi-stage campaigns in this dataset.")
        else:
            st.dataframe(campaigns, use_container_width=True, hide_index=True,
                         column_config={"stages_detected": st.column_config.NumberColumn("stages detected"),
                                        "incidents": st.column_config.NumberColumn("split across incidents")})
    with q2:
        st.markdown("**Incidents** — does each one describe a single attack?")
        if purity.empty:
            st.caption("No incidents.")
        else:
            counts = purity["verdict"].value_counts()
            st.markdown(
                f"- **{int(counts.get('one attack', 0))}** describe exactly one attack\n"
                f"- **{int(counts.get('merged attacks', 0))}** combine separate attacks that shared an entity\n"
                f"- **{int(counts.get('false positives only', 0))}** contain only false positives"
            )
            st.caption("Combining isn't always wrong: two attacks on the same host in the same hours is something an analyst would want to see together.")

    st.subheader("Per-instance detail")
    detail = outcomes[["scenario_id", "scenario_tag", "technique", "campaign_id", "first_ts", "outcome", "first_detector", "ttd_minutes"]]
    st.dataframe(
        detail.assign(campaign_id=detail["campaign_id"].fillna("—"), first_detector=detail["first_detector"].fillna("—"))
        .sort_values("first_ts"),
        use_container_width=True, hide_index=True,
        column_config={"ttd_minutes": st.column_config.NumberColumn("minutes to detect", format="%.1f")},
    )
    csv_download(detail, "detection_coverage.csv")
