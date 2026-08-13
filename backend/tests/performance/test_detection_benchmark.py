"""
backend/tests/performance/test_detection_benchmark.py
Detection-accuracy benchmark: does ScamShield actually detect scams better
than chance / baseline?

Runs the heuristic engine over the labelled dataset (dataset/scam_messages.csv
+ dataset/safe_messages.csv) and asserts minimum accuracy / precision /
recall. This is the "does it work" complement to the latency benchmarks —
it guards against regressions where the engine silently starts classifying
everything as safe (or everything as a threat).

Ground-truth convention matches dataset/evaluation/evaluation_report.md:
  * scam + suspicious  -> predicted THREAT (positive)
  * safe               -> predicted non-threat (negative)
"""

from __future__ import annotations

import csv
from pathlib import Path

import pytest

from app.models.enums import ScamClassification
from app.services.heuristic_service import HeuristicService

# Dataset lives at the repository root (one level above backend/).
_DATASET_DIR = Path(__file__).resolve().parents[3] / "dataset"

# Minimum acceptable scores — the baseline engine measured ~89% accuracy / F1
# in the evaluation report. CI should catch anything meaningfully worse.
MIN_ACCURACY = 0.80
MIN_PRECISION = 0.80
MIN_RECALL = 0.80


def _load_messages(path: Path, label: str) -> list[tuple[str, bool]]:
    """Returns (text, is_scam) pairs. CSV columns: id,message,label,category."""
    rows: list[tuple[str, bool]] = []
    if not path.exists():
        pytest.skip(f"Dataset not found: {path}")
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            text = (row.get("message") or "").strip()
            if text:
                rows.append((text, (row.get("label") or "").strip() == label))
    return rows


def _classify(engine: HeuristicService, text: str) -> bool:
    """True = predicted threat (scam or suspicious)."""
    result = engine.analyze(text)
    return result.classification in (ScamClassification.scam, ScamClassification.suspicious)


@pytest.fixture(scope="module")
def confusion():
    """Evaluate the heuristic engine against the labelled dataset once."""
    engine = HeuristicService()
    scam = _load_messages(_DATASET_DIR / "scam_messages.csv", "scam")
    safe = _load_messages(_DATASET_DIR / "safe_messages.csv", "safe")

    assert len(scam) >= 50, f"Scam dataset too small: {len(scam)}"
    assert len(safe) >= 50, f"Safe dataset too small: {len(safe)}"

    tp = sum(1 for text, is_scam in scam if _classify(engine, text))
    fp = sum(1 for text, is_safe in safe if _classify(engine, text))
    fn = len(scam) - tp
    tn = len(safe) - fp

    stats = {
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "n_scam": len(scam), "n_safe": len(safe),
    }
    stats["accuracy"] = (tp + tn) / (len(scam) + len(safe))
    stats["precision"] = tp / (tp + fp) if (tp + fp) else 0.0
    stats["recall"] = tp / (tp + fn) if (tp + fn) else 0.0
    stats["f1"] = (2 * stats["precision"] * stats["recall"] /
                   (stats["precision"] + stats["recall"])) if (stats["precision"] + stats["recall"]) else 0.0
    return stats


class TestDetectionBenchmark:

    def test_benchmark_runs_on_real_dataset(self, confusion):
        assert confusion["n_scam"] >= 50
        assert confusion["n_safe"] >= 50

    def test_accuracy_above_baseline(self, confusion):
        acc = confusion["accuracy"]
        print(f"\n[DETECTION BENCHMARK] Accuracy={acc:.1%} "
              f"(TP={confusion['tp']} FP={confusion['fp']} "
              f"FN={confusion['fn']} TN={confusion['tn']})")
        assert acc >= MIN_ACCURACY, f"Accuracy {acc:.1%} below {MIN_ACCURACY:.0%}"

    def test_precision_above_baseline(self, confusion):
        print(f"\n[DETECTION BENCHMARK] Precision={confusion['precision']:.1%}")
        assert confusion["precision"] >= MIN_PRECISION

    def test_recall_above_baseline(self, confusion):
        print(f"\n[DETECTION BENCHMARK] Recall={confusion['recall']:.1%} "
              f"(F1={confusion['f1']:.1%})")
        assert confusion["recall"] >= MIN_RECALL
