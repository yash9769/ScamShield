"""Tests the NSL-KDD evaluation logic without touching the network — only
nsl_kdd.load() downloads anything, and nothing here calls it. Tiny synthetic
frames matching NSL-KDD's schema exercise the same encode/fit/score code
path the real 125k-row dataset goes through.
"""

from __future__ import annotations

import pandas as pd

from socdash.datasets import nsl_kdd


def _kdd_frame(n_normal: int, attacks: dict[str, int]) -> pd.DataFrame:
    rows = []
    for _ in range(n_normal):
        rows.append(("normal", 200))
    for label, count in attacks.items():
        rows.extend([(label, 500_000)] * count)
    records = []
    for label, src_bytes in rows:
        record = {col: 0 for col in nsl_kdd.NUMERIC_COLS}
        record.update(protocol_type="tcp", service="http", flag="SF", src_bytes=src_bytes, label=label)
        records.append(record)
    df = pd.DataFrame(records)
    df["binary_label"] = (df["label"] != "normal").astype(int)
    df["attack_category"] = df["label"].map(lambda x: nsl_kdd.ATTACK_CATEGORY.get(x, "normal" if x == "normal" else "Unknown"))
    return df


def test_attack_category_mapping_covers_known_labels():
    assert nsl_kdd.ATTACK_CATEGORY["neptune"] == "DoS"
    assert nsl_kdd.ATTACK_CATEGORY["satan"] == "Probe"
    assert nsl_kdd.ATTACK_CATEGORY["guess_passwd"] == "R2L"
    assert nsl_kdd.ATTACK_CATEGORY["rootkit"] == "U2R"


def test_isolation_forest_runs_offline():
    train, test = _kdd_frame(140, {"neptune": 60}), _kdd_frame(70, {"neptune": 30})
    result = nsl_kdd.evaluate_isolation_forest(train, test, contamination=0.3)
    assert 0.0 <= result["precision"] <= 1.0 and 0.0 <= result["recall"] <= 1.0
    assert result["n_test"] == 100 and result["n_attacks_true"] == 30
    assert len(result["score"]) == 100


def test_isolation_forest_catches_an_obvious_volumetric_outlier():
    """Attacks at 2500x normal byte volume: should score well above chance,
    proving the pipeline isn't silently no-oping."""
    train, test = _kdd_frame(240, {"neptune": 60}), _kdd_frame(120, {"neptune": 30})
    assert nsl_kdd.evaluate_isolation_forest(train, test, contamination=0.2)["recall"] > 0.5


def test_random_forest_runs_offline():
    train, test = _kdd_frame(140, {"neptune": 60}), _kdd_frame(70, {"neptune": 30})
    result = nsl_kdd.evaluate_random_forest(train, test, n_estimators=10)
    assert result["recall"] == 1.0, "trivially separable — the supervised model must get it"
    assert ((result["score"] >= 0) & (result["score"] <= 1)).all()


def test_novel_labels_and_seen_unseen_recall():
    train = _kdd_frame(100, {"neptune": 40})
    test = _kdd_frame(50, {"neptune": 20, "apache2": 10})
    novel = nsl_kdd.novel_attack_labels(train, test)
    assert novel == {"apache2"}
    result = nsl_kdd.evaluate_random_forest(train, test, n_estimators=10)
    breakdown = nsl_kdd.recall_by(result, novel)
    assert set(breakdown["seen"].index) == {"seen in training", "unseen in training"}
    assert breakdown["seen_counts"]["unseen in training"] == 10


def test_pr_curve_spans_recall():
    train, test = _kdd_frame(140, {"neptune": 60}), _kdd_frame(70, {"neptune": 30})
    curve = nsl_kdd.pr_curve(nsl_kdd.evaluate_isolation_forest(train, test, contamination=0.3))
    assert {"recall", "precision"} == set(curve.columns)
    assert curve["recall"].max() == 1.0 and curve["recall"].min() == 0.0
