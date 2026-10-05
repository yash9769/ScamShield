from __future__ import annotations

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import (
    INK_MUTED,
    INK_SECONDARY,
    SERIES,
    db_mtime,
    get_all_alerts,
    get_events,
    get_suppressions,
    remove_suppression,
    require_data,
    rerun_detection,
    styled,
)
from socdash.detection import suppression
from socdash import tuning
from socdash.detection import rule_engine

CURRENT_BUDGET = 20  # anomaly.generate_anomaly_alerts(top_n=20), as the pipeline runs it
RECALL_COLOR = SERIES[0]
FP_COLOR = SERIES[1]


@st.cache_data(max_entries=32)
def _sweep(mtime: float, rule_id: str) -> pd.DataFrame:
    return tuning.sweep_rule(get_events(), rule_id)


@st.cache_data(max_entries=8)
def _budget(mtime: float) -> pd.DataFrame:
    return tuning.alert_budget(get_events())


def _fmt(param: str, value) -> str:
    if param == "bytes_sent_threshold":
        mb = value / 1_000_000
        return f"{mb:g} MB" if mb >= 1 else f"{value / 1000:g} KB"
    return f"{value:g}"


def _safe_band(sweep: pd.DataFrame, labels: list[str]) -> str:
    """The values that keep full recall with zero false positives — the
    band a threshold can move within before it starts costing something."""
    best = sweep["recall"].max()
    ok = (sweep["recall"] == best) & (sweep["false_positives"] == 0)
    if not ok.any():
        return "No tested value reaches full recall with zero false positives."
    idx = list(sweep.index[ok])
    lo, hi = labels[idx[0]], labels[idx[-1]]
    contiguous = idx == list(range(idx[0], idx[-1] + 1))
    span = f"**{lo}**" if lo == hi else f"**{lo} – {hi}**"
    note = "" if contiguous else " (not contiguous)"
    return f"Recall {best:.0%} with zero false positives from {span}{note}."


def _sweep_charts(sweep: pd.DataFrame, param: str, label: str) -> tuple[go.Figure, go.Figure]:
    labels = [_fmt(param, v) for v in sweep["value"]]
    # Position, not label: on a category axis Plotly reads a numeric-looking
    # string like "5" as a category index, which put the marker on "6".
    default = int(sweep.index[sweep["is_default"]][0])

    recall = go.Figure(go.Scatter(
        x=labels, y=sweep["recall"], mode="lines+markers",
        line=dict(color=RECALL_COLOR, width=2), marker=dict(size=9, color=RECALL_COLOR),
        customdata=sweep[["detected", "instances"]],
        hovertemplate=f"{label}: %{{x}}<br>recall %{{y:.0%}} (%{{customdata[0]}} of %{{customdata[1]}})<extra></extra>",
    ))
    recall.update_yaxes(range=[-0.05, 1.08], tickformat=".0%", title=None)
    recall.update_layout(title=dict(text="Recall — attack instances caught", font=dict(size=14)), height=300)

    fp = go.Figure(go.Bar(
        x=labels, y=sweep["false_positives"], marker=dict(color=FP_COLOR, cornerradius=4),
        text=[str(v) if v else "" for v in sweep["false_positives"]], textposition="outside",
        textfont=dict(color=INK_SECONDARY),
        hovertemplate=f"{label}: %{{x}}<br>%{{y}} false-positive alerts<extra></extra>",
    ))
    fp.update_yaxes(title=None, rangemode="tozero")
    fp.update_layout(title=dict(text="False-positive alerts", font=dict(size=14)), height=300, bargap=0.35)

    for fig in (recall, fp):
        fig.update_xaxes(type="category", title=label)
        fig.add_vline(x=default, line=dict(color=INK_MUTED, width=1, dash="dot"))
        fig.add_annotation(x=default, y=1, yref="paper", text="current", showarrow=False,
                           yanchor="bottom", font=dict(size=11, color=INK_SECONDARY))
        styled(fig)
    return recall, fp


def _budget_charts(budget: pd.DataFrame) -> tuple[go.Figure, go.Figure]:
    figs = []
    for column, title, color in (("precision", "Precision@k — share of the top k that were attack hours", SERIES[0]),
                                 ("recall", "Recall@k — share of all attack instances those k hours cover", SERIES[2])):
        fig = go.Figure(go.Scatter(
            x=budget["k"], y=budget[column], mode="lines", line=dict(color=color, width=2),
            customdata=budget[["true_positives", "instances_covered"]],
            hovertemplate="top %{x} host-hours<br>" + column + " %{y:.0%}<br>"
                          "%{customdata[0]} attack hours · %{customdata[1]} instances<extra></extra>",
        ))
        fig.add_vline(x=CURRENT_BUDGET, line=dict(color=INK_MUTED, width=1, dash="dot"))
        fig.add_annotation(x=CURRENT_BUDGET, y=1, yref="paper", text=f"current budget ({CURRENT_BUDGET})",
                           showarrow=False, yanchor="bottom", xanchor="left", font=dict(size=11, color=INK_SECONDARY))
        fig.update_yaxes(range=[0, 1.05], tickformat=".0%", title=None)
        fig.update_xaxes(title="alerts raised (top k host-hours by anomaly score)")
        fig.update_layout(title=dict(text=title, font=dict(size=14)), height=320, hovermode="x")
        figs.append(styled(fig))
    return figs[0], figs[1]


def render() -> None:
    st.title("Detection Tuning")
    st.caption(
        "Every threshold is a trade between catching quieter attacks and drowning the queue. "
        "With synthetic ground truth the trade is measured, not argued: each rule is re-run "
        "across a range of values and scored on what it caught and what it raised for nothing."
    )
    if not require_data():
        return
    if get_events().empty:
        st.info("No events yet — generate data on the Overview page.")
        return

    st.subheader("Rule thresholds")
    rules = {r["id"]: r for r in rule_engine.load_rules()}
    options = [rid for rid in tuning.SWEEPS if rid in rules]
    rule_id = st.segmented_control("Rule", options, default=options[0], format_func=lambda r: r.replace("_", " "))
    rule_id = rule_id or options[0]
    spec = tuning.SWEEPS[rule_id]
    st.caption(f"{rules[rule_id]['title']} · sweeping `{spec['param']}` ({spec['label']}) · "
               f"{rules[rule_id]['mitre']['technique']}")

    with st.spinner("Re-running the rule at each value…"):
        sweep = _sweep(db_mtime(), rule_id)
    labels = [_fmt(spec["param"], v) for v in sweep["value"]]
    recall_fig, fp_fig = _sweep_charts(sweep, spec["param"], spec["label"])
    c1, c2 = st.columns(2)
    c1.plotly_chart(recall_fig, use_container_width=True)
    c2.plotly_chart(fp_fig, use_container_width=True)
    st.markdown(_safe_band(sweep, labels))
    if sweep["false_positives"].sum() == 0:
        st.caption(
            "No value here produced a false positive. That says more about the synthetic background than "
            "about the rule — real traffic has travelling employees and legitimate bulk uploads, and this "
            "curve would bend on it."
        )
    with st.expander("Sweep table"):
        st.dataframe(sweep.assign(value=labels), use_container_width=True, hide_index=True,
                     column_config={"recall": st.column_config.NumberColumn(format="percent")})

    st.divider()
    st.subheader("Anomaly alert budget")
    st.caption(
        "Isolation Forest scores every active host-hour; the pipeline raises the top "
        f"{CURRENT_BUDGET} as alerts. An alert costs analyst time, so the real tuning knob is how many to raise. "
        "Recall is over every injected instance, including ones no host-hour model can see — it "
        "plateaus, and past the plateau more budget buys only false positives."
    )
    with st.spinner("Scoring host-hours…"):
        budget = _budget(db_mtime())
    if budget.empty:
        st.info("Nothing to score.")
    else:
        _budget_section(budget)
    _suppressions_section()


def _budget_section(budget: pd.DataFrame) -> None:
    at = budget.set_index("k")
    current = at.loc[min(CURRENT_BUDGET, len(budget))]
    plateau_k = int(budget.loc[budget["instances_covered"].idxmax(), "k"])
    m1, m2, m3 = st.columns(3)
    m1.metric(f"Precision @ {CURRENT_BUDGET}", f"{current['precision']:.0%}")
    m2.metric(f"Instances covered @ {CURRENT_BUDGET}", f"{int(current['instances_covered'])}",
              help=f"{current['recall']:.0%} of all injected instances")
    m3.metric("Coverage stops growing at", f"k = {plateau_k}",
              help=f"Precision there: {at.loc[plateau_k, 'precision']:.0%}")
    p_fig, r_fig = _budget_charts(budget)
    c1, c2 = st.columns(2)
    c1.plotly_chart(p_fig, use_container_width=True)
    c2.plotly_chart(r_fig, use_container_width=True)


def _suppressions_section() -> None:
    st.divider()
    st.subheader("Suppressions")
    st.caption("Exceptions for known-benign activity, written from an alert on Alerts & Triage. Matching alerts "
               "are stored as suppressed and kept out of incidents, risk and evaluation.")
    rules = get_suppressions()
    if rules.empty:
        st.caption("None yet. Open an alert on Alerts & Triage and use *Suppress alerts like this*.")
        return
    alerts = get_all_alerts()
    hits = alerts["suppressed_by"].value_counts() if "suppressed_by" in alerts.columns else pd.Series(dtype=int)
    events = get_events()
    attack_events = set(events.loc[events["scenario_id"].notna(), "event_id"]) if "scenario_id" in events else set()
    suppressed = alerts[alerts["status"] == "suppressed"] if "status" in alerts.columns else alerts.iloc[0:0]
    real = (suppressed[suppressed["event_ids"].apply(lambda ids: bool(set(ids) & attack_events))]
            ["suppressed_by"].value_counts())
    table = rules.assign(
        state=[("active" if suppression.is_active(r) else "expired") for r in rules.to_dict("records")],
        hits=rules["suppression_id"].map(hits).fillna(0).astype(int),
        real=rules["suppression_id"].map(real).fillna(0).astype(int),
    )[["suppression_id", "state", "source", "entity", "reason", "hits", "real", "created_at", "expires_at"]]
    st.dataframe(table, use_container_width=True, hide_index=True,
                 column_config={"hits": st.column_config.NumberColumn("alerts suppressed (last run)"),
                                "real": st.column_config.NumberColumn("of which real attacks",
                                                                      help="Synthetic ground truth. Should be 0.")})
    if table["real"].sum():
        st.warning("A suppression is hiding alerts that touched real attack activity. Narrow or remove it.")
    c1, c2, _ = st.columns([2, 1, 2], vertical_alignment="bottom")
    doomed = c1.selectbox("Remove a suppression", ["—"] + table["suppression_id"].tolist())
    if c2.button("Remove", disabled=doomed == "—", use_container_width=True):
        remove_suppression(doomed)
        st.rerun()
    if st.button("Re-run detection with current suppressions",
                 help="Rebuilds alerts and incidents, so incident triage and notes reset."):
        summary = rerun_detection()
        st.toast(f"{summary['total_alerts']} alerts, {summary['suppressed']} suppressed, {summary['incidents']} incidents.")
        st.rerun()
