from __future__ import annotations

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from common import INK_MUTED, MODEL_COLOR, SEQUENTIAL_BLUE, styled
from socdash.datasets import nsl_kdd

IF, RF = "Isolation Forest", "Random Forest"


@st.cache_resource(show_spinner=False)
def _datasets():
    train, test = nsl_kdd.load()
    return train, test, nsl_kdd.novel_attack_labels(train, test)


@st.cache_data(show_spinner=False, max_entries=8)
def _isolation_forest(contamination: float) -> dict:
    train, test, _ = _datasets()
    return nsl_kdd.evaluate_isolation_forest(train, test, contamination=contamination)


@st.cache_data(show_spinner=False)
def _random_forest() -> dict:
    train, test, _ = _datasets()
    return nsl_kdd.evaluate_random_forest(train, test)


def _grouped_bars(frame: pd.DataFrame, x_title: str) -> go.Figure:
    """frame: index = groups, columns = model names, values = recall."""
    fig = go.Figure()
    for model in (IF, RF):
        fig.add_trace(go.Bar(
            x=frame.index, y=frame[model], name=model, marker_color=MODEL_COLOR[model],
            text=[f"{v:.0%}" for v in frame[model]], textposition="outside",
        ))
    fig.update_layout(barmode="group", height=330, yaxis=dict(range=[0, 1.12], tickformat=".0%", title="recall"),
                      xaxis_title=x_title, legend=dict(orientation="h", y=1.12, x=0, title_text=""))
    return styled(fig)


def _pr_chart(results: dict[str, dict], prevalence: float) -> go.Figure:
    fig = go.Figure()
    fig.add_hline(y=prevalence, line_dash="dash", line_color=INK_MUTED,
                  annotation_text=f"random guessing ({prevalence:.0%} of records are attacks)", annotation_position="bottom left")
    for model, result in results.items():
        curve = nsl_kdd.pr_curve(result)
        fig.add_trace(go.Scatter(x=curve["recall"], y=curve["precision"], mode="lines",
                                 name=f"{model} (AP {result['average_precision']:.2f})",
                                 line=dict(color=MODEL_COLOR[model], width=2)))
        fig.add_trace(go.Scatter(x=[result["recall"]], y=[result["precision"]], mode="markers", showlegend=False,
                                 marker=dict(size=11, color=MODEL_COLOR[model], line=dict(width=2, color="#fcfcfb")),
                                 hovertemplate=f"{model} operating point<br>recall %{{x:.0%}}, precision %{{y:.0%}}<extra></extra>"))
    fig.update_layout(height=360, xaxis=dict(range=[0, 1], tickformat=".0%", title="recall"),
                      yaxis=dict(range=[0, 1.02], tickformat=".0%", title="precision"))
    styled(fig)
    # Inside the plot's empty lower-left corner — above the plot it collided
    # with the curves, which both run along the top edge.
    fig.update_layout(legend=dict(x=0.02, y=0.04, xanchor="left", yanchor="bottom", title_text="",
                                  bgcolor="rgba(252,252,251,0.85)"))
    return fig


def _confusion(result: dict, title: str) -> go.Figure:
    cm = result["confusion_matrix"]
    fig = go.Figure(go.Heatmap(
        z=cm, x=["Predicted normal", "Predicted attack"], y=["Actually normal", "Actually attack"],
        colorscale=[[0, SEQUENTIAL_BLUE[0]], [1, SEQUENTIAL_BLUE[-1]]], text=cm, texttemplate="%{text:,}", showscale=False,
    ))
    # Plotly draws category axes bottom-to-top; reverse so it reads like the labels above.
    fig.update_yaxes(autorange="reversed")
    fig.update_layout(height=260, title=dict(text=title, font=dict(size=14)))
    return styled(fig)


def render() -> None:
    st.title("Dataset Validation")
    st.markdown(
        "The synthetic dashboard proves this pipeline catches the scenarios it was built to inject — a "
        "weak test, since the same person wrote the generator and the detectors. **NSL-KDD** is a real, "
        "independently labeled intrusion-detection benchmark. Scoring the same Isolation Forest against it "
        "checks whether the *approach* generalizes. A supervised **Random Forest** — which gets to learn "
        "from labels — is the reference point."
    )
    st.caption(
        "Isolation Forest is fit without labels; labels are used only afterwards to score it. NSL-KDD's test "
        "set deliberately includes attack types that never appear in training — that split is the point of this page."
    )

    contamination = st.slider("Isolation Forest contamination", 0.02, 0.40, 0.10, 0.01)
    with st.spinner("Loading NSL-KDD (first run downloads ~22 MB) and fitting both models..."):
        try:
            _, test, novel = _datasets()
            results = {IF: _isolation_forest(contamination), RF: _random_forest()}
        except nsl_kdd.DatasetUnavailableError as exc:
            st.error(str(exc))
            return

    breakdowns = {model: nsl_kdd.recall_by(result, novel) for model, result in results.items()}
    seen_counts = breakdowns[IF]["seen_counts"]
    summary = pd.DataFrame([{
        "model": model,
        "learns from labels": model == RF,
        "precision": r["precision"], "recall": r["recall"], "F1": r["f1"], "avg precision": r["average_precision"],
        "recall · seen types": breakdowns[model]["seen"].get("seen in training", float("nan")),
        "recall · unseen types": breakdowns[model]["seen"].get("unseen in training", float("nan")),
    } for model, r in results.items()])
    pct = st.column_config.NumberColumn(format="percent")
    st.dataframe(summary, hide_index=True, use_container_width=True,
                 column_config={c: pct for c in summary.columns if c not in ("model", "learns from labels")})

    st.subheader("Attacks it was trained on vs. attacks it never saw")
    seen = pd.DataFrame({model: breakdowns[model]["seen"] for model in (IF, RF)}).reindex(["seen in training", "unseen in training"])
    st.plotly_chart(_grouped_bars(seen, "attack type"), use_container_width=True)
    st.caption(
        f"{len(novel)} attack types ({int(seen_counts.get('unseen in training', 0)):,} of "
        f"{int(seen_counts.sum()):,} attack records) appear only in the test set: {', '.join(sorted(novel))}."
    )

    if_unseen, rf_unseen = seen.loc["unseen in training", IF], seen.loc["unseen in training", RF]
    rf_seen = seen.loc["seen in training", RF]
    verdict = (
        f"Isolation Forest — which never sees a label — catches **{if_unseen:.0%}** of those, "
        f"{'more than' if if_unseen > rf_unseen else 'less than'} the supervised model."
    )
    st.info(
        f"**Reading this honestly:** the Random Forest catches **{rf_seen:.0%}** of attack types it was trained on, "
        f"but only **{rf_unseen:.0%}** of the {len(novel)} types it never saw. {verdict} Supervision memorizes "
        "the attacks you already know; anomaly detection is how you notice the ones you don't — which is why real "
        "SOCs run both, and why this project pairs rules with an anomaly detector. Also note the test set is "
        f"{results[IF]['n_attacks_true'] / results[IF]['n_test']:.0%} attacks, far above any real network, so "
        "these are relative strengths, not deployable false-positive rates."
    )

    col_a, col_b = st.columns(2)
    with col_a:
        st.subheader("Precision–recall")
        st.plotly_chart(_pr_chart(results, results[IF]["n_attacks_true"] / results[IF]["n_test"]), use_container_width=True)
        st.caption("Dots mark each model's current operating point. Contamination only moves Isolation Forest's dot along its curve.")
    with col_b:
        st.subheader("Recall by attack category")
        categories = pd.DataFrame({model: breakdowns[model]["category"] for model in (IF, RF)}).reindex(["DoS", "Probe", "R2L", "U2R"]).dropna(how="all")
        st.plotly_chart(_grouped_bars(categories, "KDD attack category"), use_container_width=True)
        st.caption("DoS and Probe are volumetric — easy to see. R2L and U2R mimic legitimate use and are hard for both.")

    st.subheader("Confusion matrices")
    m1, m2 = st.columns(2)
    m1.plotly_chart(_confusion(results[IF], IF), use_container_width=True)
    m2.plotly_chart(_confusion(results[RF], RF), use_container_width=True)
