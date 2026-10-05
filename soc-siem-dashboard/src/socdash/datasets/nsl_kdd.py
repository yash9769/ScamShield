"""NSL-KDD loader, plus two detectors scored against its labels.

The synthetic dataset proves the pipeline catches the specific scenarios it
was built to inject — which is a weak test, since the generator and the
detectors were written by the same person with the same mental model of
what an attack looks like. NSL-KDD is a real, independently labeled
intrusion-detection benchmark; scoring the same unsupervised technique
(Isolation Forest) against it is a second, less self-serving check on
whether the *approach* generalizes at all, not just whether it catches what
it was tuned to catch.

A supervised Random Forest is scored alongside it as a reference point: it
gets to learn from labels, which unsupervised detection never has. KDDTest+
deliberately contains attack types that never appear in KDDTrain+, so
splitting recall into "seen in training" vs "unseen" shows the cost of that
advantage — supervision memorizes what it was shown.

Note on methodology: Isolation Forest is fit without labels; labels are used
only afterwards, to score predictions against ground truth. That's standard
practice for evaluating anomaly detectors, not a leak.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import requests
from sklearn.ensemble import IsolationForest, RandomForestClassifier
from sklearn.metrics import (
    average_precision_score,
    confusion_matrix,
    f1_score,
    precision_recall_curve,
    precision_score,
    recall_score,
)
from sklearn.preprocessing import OneHotEncoder

TRAIN_URL = "https://raw.githubusercontent.com/jmnwong/NSL-KDD-Dataset/master/KDDTrain%2B.txt"
TEST_URL = "https://raw.githubusercontent.com/jmnwong/NSL-KDD-Dataset/master/KDDTest%2B.txt"

DEFAULT_DATA_DIR = Path(__file__).resolve().parents[3] / "data" / "raw"

COLUMNS = [
    "duration", "protocol_type", "service", "flag", "src_bytes", "dst_bytes", "land",
    "wrong_fragment", "urgent", "hot", "num_failed_logins", "logged_in", "num_compromised",
    "root_shell", "su_attempted", "num_root", "num_file_creations", "num_shells",
    "num_access_files", "num_outbound_cmds", "is_host_login", "is_guest_login", "count",
    "srv_count", "serror_rate", "srv_serror_rate", "rerror_rate", "srv_rerror_rate",
    "same_srv_rate", "diff_srv_rate", "srv_diff_host_rate", "dst_host_count",
    "dst_host_srv_count", "dst_host_same_srv_rate", "dst_host_diff_srv_rate",
    "dst_host_same_src_port_rate", "dst_host_srv_diff_host_rate", "dst_host_serror_rate",
    "dst_host_srv_serror_rate", "dst_host_rerror_rate", "dst_host_srv_rerror_rate",
    "label", "difficulty",
]
CATEGORICAL_COLS = ["protocol_type", "service", "flag"]
NUMERIC_COLS = [c for c in COLUMNS if c not in CATEGORICAL_COLS + ["label", "difficulty"]]

# The standard KDD/NSL-KDD attack taxonomy. KDDTest+ includes attack types
# absent from KDDTrain+ — by design, to test generalization to unseen attacks.
ATTACK_CATEGORY = {
    "back": "DoS", "land": "DoS", "neptune": "DoS", "pod": "DoS", "smurf": "DoS",
    "teardrop": "DoS", "apache2": "DoS", "udpstorm": "DoS", "processtable": "DoS",
    "worm": "DoS", "mailbomb": "DoS",
    "satan": "Probe", "ipsweep": "Probe", "nmap": "Probe", "portsweep": "Probe",
    "mscan": "Probe", "saint": "Probe",
    "guess_passwd": "R2L", "ftp_write": "R2L", "imap": "R2L", "phf": "R2L",
    "multihop": "R2L", "warezmaster": "R2L", "warezclient": "R2L", "spy": "R2L",
    "xlock": "R2L", "xsnoop": "R2L", "snmpguess": "R2L", "snmpgetattack": "R2L",
    "httptunnel": "R2L", "sendmail": "R2L", "named": "R2L",
    "buffer_overflow": "U2R", "loadmodule": "U2R", "rootkit": "U2R", "perl": "U2R",
    "sqlattack": "U2R", "xterm": "U2R", "ps": "U2R",
}


class DatasetUnavailableError(RuntimeError):
    """Raised when NSL-KDD can't be fetched and isn't already cached locally."""


def _download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        resp = requests.get(url, timeout=60)
        resp.raise_for_status()
    except requests.RequestException as exc:
        raise DatasetUnavailableError(
            f"Couldn't download {url} ({exc}). If you're offline, place the file "
            f"manually at {dest} and reload."
        ) from exc
    dest.write_bytes(resp.content)


def _load_file(path: Path, url: str) -> pd.DataFrame:
    if not path.exists():
        _download(url, path)
    df = pd.read_csv(path, names=COLUMNS)
    df["binary_label"] = (df["label"] != "normal").astype(int)
    df["attack_category"] = df["label"].map(lambda x: ATTACK_CATEGORY.get(x, "normal" if x == "normal" else "Unknown"))
    return df


def load(data_dir: Path | str = DEFAULT_DATA_DIR) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Downloads (and caches under data_dir) KDDTrain+ and KDDTest+, returns
    (train_df, test_df) with binary_label and attack_category added."""
    data_dir = Path(data_dir)
    train = _load_file(data_dir / "KDDTrain+.txt", TRAIN_URL)
    test = _load_file(data_dir / "KDDTest+.txt", TEST_URL)
    return train, test


def _featurize(train: pd.DataFrame, test: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    encoder = OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    encoder.fit(pd.concat([train[CATEGORICAL_COLS], test[CATEGORICAL_COLS]], ignore_index=True))
    train_cat = encoder.transform(train[CATEGORICAL_COLS])
    test_cat = encoder.transform(test[CATEGORICAL_COLS])
    train_num = np.log1p(train[NUMERIC_COLS].clip(lower=0)).to_numpy()
    test_num = np.log1p(test[NUMERIC_COLS].clip(lower=0)).to_numpy()
    return np.hstack([train_num, train_cat]), np.hstack([test_num, test_cat])


def _results(test: pd.DataFrame, y_pred: np.ndarray, score: np.ndarray) -> dict:
    """Metrics plus the raw per-record arrays the dashboard breaks down.
    `score` is continuous (higher = more attack-like) so a precision-recall
    curve can sweep every threshold, not just the one y_pred used."""
    y_true = test["binary_label"].to_numpy()
    return {
        "precision": precision_score(y_true, y_pred, zero_division=0),
        "recall": recall_score(y_true, y_pred, zero_division=0),
        "f1": f1_score(y_true, y_pred, zero_division=0),
        "average_precision": average_precision_score(y_true, score),
        "confusion_matrix": confusion_matrix(y_true, y_pred, labels=[0, 1]).tolist(),
        "n_test": len(y_true),
        "n_attacks_true": int(y_true.sum()),
        "n_flagged": int(y_pred.sum()),
        "y_true": y_true,
        "y_pred": y_pred,
        "score": score,
        "label": test["label"].to_numpy(),
        "attack_category": test["attack_category"].to_numpy(),
    }


def evaluate_isolation_forest(
    train: pd.DataFrame,
    test: pd.DataFrame,
    contamination: float = 0.1,
    random_state: int = 42,
) -> dict:
    """Fits Isolation Forest on train (unlabeled) and scores it against
    test's ground-truth labels."""
    X_train, X_test = _featurize(train, test)
    model = IsolationForest(contamination=contamination, random_state=random_state, n_estimators=200)
    model.fit(X_train)
    y_pred = (model.predict(X_test) == -1).astype(int)
    return _results(test, y_pred, -model.decision_function(X_test))


def evaluate_random_forest(
    train: pd.DataFrame,
    test: pd.DataFrame,
    n_estimators: int = 100,
    random_state: int = 42,
) -> dict:
    """Supervised reference point: same features, but trained on labels."""
    X_train, X_test = _featurize(train, test)
    model = RandomForestClassifier(n_estimators=n_estimators, n_jobs=-1, random_state=random_state)
    model.fit(X_train, train["binary_label"])
    probability = model.predict_proba(X_test)[:, 1]
    return _results(test, (probability >= 0.5).astype(int), probability)


def novel_attack_labels(train: pd.DataFrame, test: pd.DataFrame) -> set[str]:
    """Attack types present in the test set but never seen in training."""
    return set(test.loc[test["binary_label"] == 1, "label"]) - set(train["label"])


def recall_by(result: dict, novel_labels: set[str]) -> dict[str, pd.Series]:
    """Recall over attack records only, broken down two ways: by KDD attack
    category (DoS / Probe / R2L / U2R), and by whether the attack type
    appeared in training."""
    attacks = pd.DataFrame({
        "label": result["label"], "category": result["attack_category"],
        "y_true": result["y_true"], "y_pred": result["y_pred"],
    })
    attacks = attacks[attacks["y_true"] == 1]
    seen = np.where(attacks["label"].isin(novel_labels), "unseen in training", "seen in training")
    return {
        "category": attacks.groupby("category")["y_pred"].mean(),
        "seen": attacks.groupby(seen)["y_pred"].mean(),
        "seen_counts": pd.Series(seen).value_counts(),
    }


def pr_curve(result: dict, max_points: int = 400) -> pd.DataFrame:
    """Precision/recall at every threshold, thinned to max_points for plotting."""
    precision, recall, _ = precision_recall_curve(result["y_true"], result["score"])
    curve = pd.DataFrame({"recall": recall, "precision": precision})
    step = max(1, len(curve) // max_points)
    return curve.iloc[::step].reset_index(drop=True)
