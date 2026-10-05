"""Entry point: streamlit run dashboard/app.py"""

from __future__ import annotations

import sys
from pathlib import Path

import streamlit as st

sys.path.insert(0, str(Path(__file__).resolve().parent))

from views import (  # noqa: E402
    alerts_triage,
    anomaly_detection,
    coverage,
    dataset_validation,
    entity,
    incidents,
    live_monitor,
    overview,
    search,
    threat_hunting,
    threat_intel,
    threat_map,
    tuning,
)

st.set_page_config(page_title="SOC Dashboard", page_icon="\U0001F6E1️", layout="wide")

pages = {
    "Monitor": [
        st.Page(overview.render, title="Overview", icon="\U0001F9ED", url_path="overview", default=True),
        st.Page(incidents.render, title="Incidents", icon="\U0001F4C2", url_path="incidents"),
        st.Page(alerts_triage.render, title="Alerts & Triage", icon="\U0001F6A8", url_path="alerts-triage"),
        st.Page(live_monitor.render, title="Live Monitor", icon="\U0001F4E1", url_path="live"),
    ],
    "Investigate": [
        st.Page(search.render, title="Search", icon="\U0001F50D", url_path="search"),
        st.Page(entity.render, title="Entity Investigation", icon="\U0001F50E", url_path="entity"),
        st.Page(threat_hunting.render, title="Threat Hunting", icon="\U0001F3AF", url_path="threat-hunting"),
        st.Page(threat_intel.render, title="Threat Intel", icon="\U0001F6E1", url_path="threat-intel"),
        st.Page(threat_map.render, title="Threat Map", icon="\U0001F310", url_path="threat-map"),
    ],
    "Evaluate": [
        st.Page(coverage.render, title="Detection Coverage", icon="\U0001F4CB", url_path="coverage"),
        st.Page(tuning.render, title="Detection Tuning", icon="\U0001F39B", url_path="tuning"),
        st.Page(anomaly_detection.render, title="Anomaly Detection", icon="\U0001F4C8", url_path="anomaly-detection"),
        st.Page(dataset_validation.render, title="Dataset Validation", icon="\U0001F9EA", url_path="dataset-validation"),
    ],
}
st.navigation(pages).run()
