#!/usr/bin/env python3
"""Generate synthetic SOC event data and write it to the SQLite store.

Usage: python3 scripts/generate_data.py [--days 5] [--scenarios 14] [--seed 42]
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from socdash import pipeline  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(pipeline.DEFAULT_DB_PATH), help="SQLite file path")
    parser.add_argument("--days", type=int, default=5, help="Span of history to generate")
    parser.add_argument("--base-per-hour", type=int, default=30, help="Background event rate at peak business hours")
    parser.add_argument("--scenarios", type=int, default=14, help="Number of standalone attack scenarios")
    parser.add_argument("--campaigns", type=int, default=1, help="Number of multi-stage kill-chain campaigns")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    result = pipeline.generate_and_store(
        db_path=args.db, days=args.days, base_per_hour=args.base_per_hour,
        scenario_count=args.scenarios, campaign_count=args.campaigns, seed=args.seed,
    )
    print(f"Wrote {result['events']} events spanning {result['start']} → {result['end']}")
    print(f"  -> {args.db}")


if __name__ == "__main__":
    main()
