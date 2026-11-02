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

st.set_page_config(page_title="ScamShield SOC · SIEM", page_icon="🛡️", layout="wide")

# --- Custom Global Cybersecurity Theme CSS ---
st.markdown(
    """
    <style>
    @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap');

    html, body, [class*="css"] {
        font-family: 'Plus Jakarta Sans', system-ui, -apple-system, sans-serif;
    }

    code, pre, [data-testid="stCodeBlock"] {
        font-family: 'JetBrains Mono', monospace !important;
    }

    /* Metric Cards Glassmorphism */
    [data-testid="stMetric"] {
        background: linear-gradient(135deg, rgba(255, 255, 255, 0.04) 0%, rgba(255, 255, 255, 0.01) 100%) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 12px !important;
        padding: 14px 18px !important;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3) !important;
        backdrop-filter: blur(10px) !important;
        transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease !important;
    }
    [data-testid="stMetric"]:hover {
        transform: translateY(-2px);
        border-color: rgba(0, 210, 255, 0.45) !important;
        box-shadow: 0 8px 24px rgba(0, 210, 255, 0.12) !important;
    }
    [data-testid="stMetricValue"] {
        font-weight: 800 !important;
        font-size: 1.85rem !important;
        color: #ffffff !important;
        letter-spacing: -0.02em !important;
    }
    [data-testid="stMetricLabel"] {
        font-weight: 600 !important;
        color: #94a3b8 !important;
        text-transform: uppercase !important;
        font-size: 0.72rem !important;
        letter-spacing: 0.08em !important;
    }

    /* Primary Buttons & Interactive Elements */
    button[kind="primary"] {
        background: linear-gradient(135deg, #00d2ff 0%, #0070f3 100%) !important;
        color: #ffffff !important;
        font-weight: 600 !important;
        border: none !important;
        border-radius: 8px !important;
        box-shadow: 0 4px 14px rgba(0, 210, 255, 0.3) !important;
        transition: all 0.2s ease !important;
    }
    button[kind="primary"]:hover {
        box-shadow: 0 6px 20px rgba(0, 210, 255, 0.5) !important;
        transform: translateY(-1px) !important;
    }

    /* Sleek Expanders */
    [data-testid="stExpander"] {
        background: rgba(17, 24, 39, 0.6) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 10px !important;
    }

    /* Pulsing status indicator */
    @keyframes pulse-radar {
        0% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }
        70% { transform: scale(1); box-shadow: 0 0 0 7px rgba(16, 185, 129, 0); }
        100% { transform: scale(0.95); box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
    }
    .radar-dot {
        display: inline-block;
        width: 8px;
        height: 8px;
        background-color: #10b981;
        border-radius: 50%;
        animation: pulse-radar 2s infinite;
        margin-right: 6px;
    }

    /* Custom Modern Scrollbars */
    ::-webkit-scrollbar {
        width: 6px;
        height: 6px;
    }
    ::-webkit-scrollbar-track {
        background: #090d16;
    }
    ::-webkit-scrollbar-thumb {
        background: #1e293b;
        border-radius: 4px;
    }
    ::-webkit-scrollbar-thumb:hover {
        background: #334155;
    }
    </style>
    """,
    unsafe_allow_html=True,
)

with st.sidebar:
    st.markdown(
        """
        <div style="padding: 10px 4px 16px 4px; border-bottom: 1px solid rgba(255,255,255,0.08); margin-bottom: 12px;">
            <div style="font-size: 11px; font-weight: 700; color: #00d2ff; letter-spacing: 0.12em; text-transform: uppercase;">
                ScamShield Cyber Defense
            </div>
            <div style="font-size: 16px; font-weight: 800; color: #ffffff; margin-top: 2px;">
                SOC / SIEM Engine
            </div>
            <div style="margin-top: 8px; font-size: 11px; color: #10b981; display: flex; align-items: center; font-weight: 600;">
                <span class="radar-dot"></span> DETECTION & CORRELATION ACTIVE
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )


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
