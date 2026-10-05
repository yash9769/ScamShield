"""Shared DB access, caching, and chart styling for every dashboard page.

Colors follow the validated reference palette from the dataviz skill:
status colors (severity) are reserved and never reused for series identity;
categorical slots are assigned in the documented fixed order, never cycled.
"""

from __future__ import annotations

import html
import sys
from pathlib import Path

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from socdash import evaluation, mitre, pipeline  # noqa: E402
from socdash.detection import rule_engine  # noqa: E402
from socdash.detection.risk import entity_risk  # noqa: E402
from socdash.generator.entities import EXTERNAL_IPS  # noqa: E402
from socdash.storage import db  # noqa: E402

DB_PATH = pipeline.DEFAULT_DB_PATH
STATUS_OPTIONS = db.STATUS_OPTIONS

# --- Palette (reference instance; see dataviz skill references/palette.md) ---
INK_PRIMARY = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRIDLINE = "#e1e0d9"
SURFACE = "#fcfcfb"

# Categorical, fixed order — never cycled, never reassigned per filter.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
EVENT_TYPE_COLOR = {"auth": SERIES[0], "network": SERIES[1], "dns": SERIES[2], "process": SERIES[3]}
CATEGORY_COLOR = {"DoS": SERIES[0], "Probe": SERIES[1], "R2L": SERIES[2], "U2R": SERIES[3], "Unknown": INK_MUTED}
DETECTOR_COLOR = {"rule": SERIES[0], "anomaly": SERIES[1]}
MODEL_COLOR = {"Isolation Forest": SERIES[0], "Random Forest": SERIES[1]}

# Status — reserved for severity/state, never used for series identity.
SEVERITY_COLOR = {"low": "#0ca30c", "medium": "#fab219", "high": "#ec835a", "critical": "#d03b3b"}
SEVERITY_ORDER = ["low", "medium", "high", "critical"]
# Detection outcomes: the three "caught" states are identities (which
# detector family), "missed" is a state — so it takes the status color.
OUTCOME_COLOR = {"rules only": SERIES[0], "anomaly only": SERIES[1], "both": SERIES[2], "missed": SEVERITY_COLOR["critical"]}

# Sequential (blue), light -> dark — for magnitude (heatmaps, intensity).
SEQUENTIAL_BLUE = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]

PLOTLY_LAYOUT = dict(
    paper_bgcolor=SURFACE,
    plot_bgcolor=SURFACE,
    font=dict(color=INK_PRIMARY, family="system-ui, -apple-system, 'Segoe UI', sans-serif", size=13),
    margin=dict(l=10, r=36, t=40, b=10),
    xaxis=dict(gridcolor=GRIDLINE, linecolor=GRIDLINE, zerolinecolor=GRIDLINE, color=INK_MUTED),
    yaxis=dict(gridcolor=GRIDLINE, linecolor=GRIDLINE, zerolinecolor=GRIDLINE, color=INK_MUTED),
    legend=dict(bgcolor="rgba(0,0,0,0)"),
)


def styled(fig: go.Figure) -> go.Figure:
    fig.update_layout(**PLOTLY_LAYOUT)
    # Value labels sit just past the end of each bar; without this the
    # longest bar's label is clipped by its own axis range.
    fig.update_traces(cliponaxis=False, selector=dict(type="bar"))
    return fig


def db_mtime() -> float:
    """Changes whenever the DB file is written — passed to every cached
    loader so a write from anywhere (this app, or the CLI scripts while the
    app is open) invalidates the dashboard's cached reads.

    The loaders' parameter must be named `mtime`, not `_mtime`: st.cache_data
    leaves underscore-prefixed arguments out of the cache key entirely."""
    return DB_PATH.stat().st_mtime if DB_PATH.exists() else 0.0


def _read(reader) -> pd.DataFrame:
    if not DB_PATH.exists():
        return pd.DataFrame()
    conn = db.connect(DB_PATH)
    try:
        return reader(conn)
    finally:
        conn.close()


@st.cache_data(max_entries=8)
def load_events(mtime: float) -> pd.DataFrame:
    return _read(db.read_events)


@st.cache_data(max_entries=8)
def load_alerts(mtime: float) -> pd.DataFrame:
    return _read(db.read_alerts)


@st.cache_data(max_entries=8)
def load_incidents(mtime: float) -> pd.DataFrame:
    return _read(db.read_incidents)


@st.cache_data(max_entries=8)
def load_watchlist(mtime: float) -> pd.DataFrame:
    return _read(db.read_watchlist)


def get_watchlist() -> pd.DataFrame:
    frame = load_watchlist(db_mtime())
    return frame if not frame.empty else pd.DataFrame(columns=list(db.WATCHLIST_SCHEMA))


def get_events() -> pd.DataFrame:
    return load_events(db_mtime())


def get_all_alerts() -> pd.DataFrame:
    """Every stored alert, suppressed ones included."""
    return load_alerts(db_mtime())


def get_alerts() -> pd.DataFrame:
    """The alerts analysts work with: suppressed ones are left out of every
    count, chart, risk score and evaluation."""
    alerts = load_alerts(db_mtime())
    return alerts[alerts["status"] != "suppressed"] if "status" in alerts.columns else alerts


@st.cache_data(max_entries=8)
def load_suppressions(mtime: float) -> pd.DataFrame:
    return _read(db.read_suppressions)


def get_suppressions() -> pd.DataFrame:
    frame = load_suppressions(db_mtime())
    return frame if not frame.empty else pd.DataFrame(columns=list(db.SUPPRESSION_SCHEMA))


def get_incidents() -> pd.DataFrame:
    return load_incidents(db_mtime())


@st.cache_data(max_entries=8)
def _risk(mtime: float) -> pd.DataFrame:
    alerts = get_alerts()
    return entity_risk(alerts) if not alerts.empty else pd.DataFrame(columns=["kind", "entity", "risk", "alerts", "detectors", "last_seen"])


def get_risk() -> pd.DataFrame:
    return _risk(db_mtime())


@st.cache_data(max_entries=8)
def _evaluation(mtime: float) -> dict[str, pd.DataFrame]:
    return evaluation.evaluate(get_events(), get_alerts(), rule_engine.load_rules())


def get_evaluation() -> dict[str, pd.DataFrame]:
    return _evaluation(db_mtime())


def clear_db_caches() -> None:
    """Explicit invalidation on top of the mtime key, for filesystems with
    coarse (1 s) mtime resolution. Only the DB-derived caches — clearing
    everything would also throw away the expensive NSL-KDD model fits."""
    for cached in (load_events, load_alerts, load_incidents, load_watchlist, load_suppressions, _risk, _evaluation):
        cached.clear()


def _write(action) -> None:
    conn = db.connect(DB_PATH)
    try:
        action(conn)
    finally:
        conn.close()
    clear_db_caches()


def set_alert_status(alert_id: str, status: str) -> None:
    _write(lambda conn: db.update_alert_status(conn, alert_id, status))


def set_incident_status(incident_id: str, status: str) -> None:
    _write(lambda conn: db.update_incident_status(conn, incident_id, status))


def set_incident_notes(incident_id: str, notes: str) -> None:
    _write(lambda conn: db.update_incident_notes(conn, incident_id, notes))


def set_incident_actions(incident_id: str, done: set[str]) -> None:
    _write(lambda conn: db.update_incident_actions(conn, incident_id, done))


def add_to_watchlist(entries: list[dict]) -> int:
    added = []
    _write(lambda conn: added.append(db.add_watchlist(conn, entries)))
    return added[0]


def remove_from_watchlist(values: list[str]) -> None:
    _write(lambda conn: db.remove_watchlist(conn, values))


def add_suppression(rule: dict) -> str:
    created = []
    _write(lambda conn: created.append(db.add_suppression(conn, rule)))
    return created[0]


def remove_suppression(suppression_id: str) -> None:
    _write(lambda conn: db.remove_suppression(conn, suppression_id))


def rerun_detection() -> dict:
    summary = pipeline.detect_and_store(DB_PATH)
    clear_db_caches()
    return summary


@st.cache_resource
def ip_country_lookup() -> dict[str, str]:
    return {ip.ip: ip.country for ip in EXTERNAL_IPS}


@st.cache_resource
def ip_malicious_lookup() -> dict[str, bool]:
    return {ip.ip: ip.known_malicious for ip in EXTERNAL_IPS}


def severity_badge(severity: str) -> str:
    color = SEVERITY_COLOR.get(severity, INK_MUTED)
    return f'<span style="color:{color}; font-weight:600;">● {html.escape(severity.upper())}</span>'


def technique_label(technique_id: str | None) -> str:
    if not technique_id or pd.isna(technique_id):
        return "Unattributed"
    return f"{technique_id} · {mitre.describe(technique_id)['name']}"


def format_duration(delta: pd.Timedelta) -> str:
    minutes = int(delta.total_seconds() // 60)
    if minutes < 60:
        return f"{minutes} min"
    hours, minutes = divmod(minutes, 60)
    return f"{hours} h {minutes:02d} min" if hours < 48 else f"{hours // 24} days"


def csv_download(df: pd.DataFrame, filename: str, label: str = "Download CSV") -> None:
    st.download_button(label, df.to_csv(index=False).encode("utf-8"), file_name=filename, mime="text/csv")


def require_data() -> bool:
    """Call at the top of every page; returns False (after showing guidance)
    if there's no database yet to read from."""
    if not DB_PATH.exists():
        st.info("No data yet. Go to **Overview** and click **Generate demo data** to get started.")
        return False
    return True
