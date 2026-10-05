#!/usr/bin/env python3
"""Run the rule engine + anomaly detector against whatever events are
already in the SQLite store, correlate the alerts into incidents, and
(re)write the alerts and incidents tables.

Usage: python3 scripts/run_detection.py [--contamination 0.03] [--window 3]
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from socdash import pipeline  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(pipeline.DEFAULT_DB_PATH), help="SQLite file path")
    parser.add_argument("--contamination", type=float, default=0.03, help="Isolation Forest contamination")
    parser.add_argument("--window", type=float, default=3.0, help="Correlation window in hours")
    args = parser.parse_args()

    result = pipeline.detect_and_store(
        db_path=args.db, anomaly_contamination=args.contamination, link_window_hours=args.window,
    )
    print(f"Rule-based alerts:    {result['rule_alerts']}")
    print(f"Anomaly-based alerts: {result['anomaly_alerts']}")
    print(f"Total written:        {result['total_alerts']}")
    print(f"Incidents:            {result['incidents']}")


if __name__ == "__main__":
    main()
