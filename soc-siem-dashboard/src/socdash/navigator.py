"""Export detection coverage as a MITRE ATT&CK Navigator layer.

Navigator (https://mitre-attack.github.io/attack-navigator/) is how
detection teams share coverage: open the JSON file there and every
technique this project detects is shaded by measured recall, with the
detectors and the injected/caught counts in each technique's comment.

Scores are measured recall against the synthetic ground truth (0-100).
A technique with a detector but no injected instances in the current data
gets no score — no test, no number — and says so in its comment.
"""

from __future__ import annotations

import json

import pandas as pd

LAYER_VERSIONS = {"attack": "16", "navigator": "5.1.0", "layer": "4.5"}
# Sequential, one hue light -> dark (the dashboard's blue ramp).
GRADIENT = ["#cde2fb", "#6da7ec", "#184f95"]
UNTESTED_COLOR = "#e1e0d9"


def _tactic_shortname(tactic: str) -> str:
    return tactic.lower().replace(" ", "-")


def layer(coverage: pd.DataFrame, name: str = "SOC dashboard — detection coverage") -> dict:
    """A Navigator layer from evaluation.attack_coverage()."""
    techniques = []
    parents_with_subs = set()
    for _, row in coverage.iterrows():
        detectors = list(row["detectors"])
        if not detectors and row["alerts"] == 0:
            continue
        entry = {
            "techniqueID": row["technique"],
            "tactic": _tactic_shortname(row["tactic"]),
            "enabled": True,
            "showSubtechniques": False,
            "metadata": [
                {"name": "detectors", "value": ", ".join(detectors) or "none"},
                {"name": "alerts", "value": str(int(row["alerts"]))},
            ],
        }
        if row["injected"]:
            entry["score"] = round(100 * row["caught"] / row["injected"])
            entry["comment"] = f"Caught {row['caught']} of {row['injected']} injected instances."
        else:
            entry["color"] = UNTESTED_COLOR
            entry["comment"] = "Detector exists; no injected instances in this dataset, so recall is untested."
        techniques.append(entry)
        if "." in row["technique"]:
            parents_with_subs.add((row["technique"].split(".")[0], entry["tactic"]))
    # Navigator hides sub-techniques unless the parent is expanded.
    for parent, tactic in sorted(parents_with_subs):
        techniques.append({"techniqueID": parent, "tactic": tactic, "enabled": True, "showSubtechniques": True})

    return {
        "name": name,
        "versions": LAYER_VERSIONS,
        "domain": "enterprise-attack",
        "description": "Detection coverage measured against synthetic ground truth. Score = recall (%).",
        "sorting": 0,
        "layout": {"layout": "side", "showName": True, "showID": True, "hideDisabled": False},
        "hideDisabled": False,
        "techniques": techniques,
        "gradient": {"colors": GRADIENT, "minValue": 0, "maxValue": 100},
        "legendItems": [
            {"label": "Recall 100%", "color": GRADIENT[-1]},
            {"label": "Recall 0%", "color": GRADIENT[0]},
            {"label": "Detector exists, untested", "color": UNTESTED_COLOR},
        ],
        "showTacticRowBackground": False,
        "selectTechniquesAcrossTactics": True,
        "selectSubtechniquesWithParent": False,
    }


def layer_json(coverage: pd.DataFrame, **kwargs) -> str:
    return json.dumps(layer(coverage, **kwargs), indent=2)
