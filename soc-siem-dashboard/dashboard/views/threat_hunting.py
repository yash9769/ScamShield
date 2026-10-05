from __future__ import annotations

import plotly.graph_objects as go
import streamlit as st

from common import DB_PATH, SERIES, csv_download, db_mtime, require_data, styled
from socdash import hunting
from socdash.storage import db

BLANK = "Blank query"
STARTER_SQL = "SELECT event_type, COUNT(*) AS events\nFROM events\nGROUP BY event_type\nORDER BY events DESC"


@st.cache_data(max_entries=32, show_spinner=False)
def _run(sql: str, mtime: float):
    result = hunting.run_query(DB_PATH, sql)
    return result.frame, result.truncated, result.elapsed_ms


def _schema_reference() -> None:
    with st.expander("Tables, columns, and extra SQL functions"):
        visible = [c for c in db.EVENT_COLUMNS if c not in hunting.HIDDEN_COLUMNS["events"]]
        st.markdown("**events** — " + ", ".join(f"`{c}`" for c in visible))
        st.markdown("**alerts** — " + ", ".join(f"`{c}`" for c in db.ALERT_COLUMNS))
        st.markdown("**incidents** — " + ", ".join(f"`{c}`" for c in db.INCIDENT_COLUMNS))
        st.markdown("**Functions** — " + " · ".join(f"`{sig}` {desc}" for sig, desc in hunting.SQL_FUNCTIONS.items()))
        st.caption(
            "Read-only by construction: the database is opened read-only, an authorizer refuses anything "
            "but SELECT, and queries are stopped after 5 seconds. The generator's ground-truth columns "
            "read as NULL here — hunting them would be cheating."
        )


def _quick_chart(frame) -> None:
    numeric = frame.select_dtypes("number").columns.tolist()
    text = [c for c in frame.columns if c not in numeric]
    if not numeric or not text or len(frame) < 2:
        return
    with st.expander("Chart these results"):
        c1, c2 = st.columns(2)
        label_col = c1.selectbox("Label", text)
        value_col = c2.selectbox("Value", numeric)
        top = frame.nlargest(25, value_col)
        labels = top[label_col].astype(str)
        if labels.duplicated().any():  # e.g. the same host on several days
            labels = top[text].astype(str).agg(" · ".join, axis=1)
        fig = go.Figure(go.Bar(x=top[value_col][::-1], y=labels[::-1], orientation="h",
                               marker_color=SERIES[0], text=top[value_col][::-1], textposition="outside"))
        fig.update_layout(height=80 + 26 * len(top), xaxis_title=value_col, showlegend=False)
        st.plotly_chart(styled(fig), use_container_width=True)


def render() -> None:
    st.title("Threat Hunting")
    st.caption("Hypothesis-driven search over the raw events, in read-only SQL. Start from a saved hunt or write your own.")
    if not require_data():
        return

    names = [h.name for h in hunting.SAVED_HUNTS] + [BLANK]
    choice = st.selectbox("Saved hunts", names)
    hunt = next((h for h in hunting.SAVED_HUNTS if h.name == choice), None)
    if hunt:
        st.markdown(f"**Hypothesis.** {hunt.hypothesis}")

    # Monospace for the SQL editor only — the saved hunts align their AS
    # clauses, which a proportional font turns ragged.
    st.markdown(
        '<style>[data-testid="stForm"] textarea{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;'
        "font-size:13px;line-height:1.5;}</style>",
        unsafe_allow_html=True,
    )
    with st.form("hunt"):
        sql = st.text_area("SQL", value=hunt.sql if hunt else STARTER_SQL, height=280, key=f"sql::{choice}")
        st.form_submit_button("Run hunt", type="primary")
    _schema_reference()

    try:
        frame, truncated, elapsed_ms = _run(sql, db_mtime())
    except hunting.HuntError as exc:
        st.error(str(exc))
        return

    st.caption(f"{len(frame):,} row(s) · {elapsed_ms:.0f} ms" + (" · truncated to the first 5,000 rows" if truncated else ""))
    if frame.empty:
        st.info("No rows matched.")
        return
    st.dataframe(frame, use_container_width=True, hide_index=True)
    csv_download(frame, "hunt_results.csv")
    _quick_chart(frame)
