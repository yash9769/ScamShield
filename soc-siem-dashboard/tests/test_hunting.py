import sqlite3
import statistics
from datetime import datetime

import pytest

from socdash import hunting, pipeline


@pytest.fixture(scope="module")
def db_path(tmp_path_factory):
    path = tmp_path_factory.mktemp("hunt") / "soc.db"
    pipeline.run_pipeline(db_path=path, days=2, scenario_count=6, campaign_count=1, seed=9, end=datetime(2026, 1, 3))
    return path


def test_entropy():
    assert hunting.entropy("aaaa") == 0
    assert hunting.entropy("ab") == pytest.approx(1.0)
    assert hunting.entropy("") is None


def test_domain_label():
    assert hunting.domain_label("aws.amazon.com") == "amazon"
    assert hunting.domain_label("xq3kz9pl.net") == "xq3kz9pl"
    assert hunting.domain_label(None) is None


def test_select_works_and_returns_a_frame(db_path):
    result = hunting.run_query(db_path, "SELECT event_type, COUNT(*) AS n FROM events GROUP BY event_type")
    assert set(result.frame.columns) == {"event_type", "n"}
    assert result.frame["n"].sum() > 0
    assert not result.truncated


def test_custom_sql_functions_are_available(db_path):
    frame = hunting.run_query(db_path, "SELECT entropy('ab') AS e, domain_label('a.b.com') AS d, "
                                       "is_internal('10.10.1.1') AS i, is_internal('8.8.8.8') AS x").frame
    assert frame.iloc[0].tolist() == [1.0, "b", 1, 0]


def test_stddev_aggregate_matches_statistics(db_path):
    frame = hunting.run_query(db_path, "SELECT stddev(bytes_sent) AS s FROM events WHERE bytes_sent IS NOT NULL").frame
    raw = [r[0] for r in sqlite3.connect(db_path).execute("SELECT bytes_sent FROM events WHERE bytes_sent IS NOT NULL")]
    assert frame["s"].iloc[0] == pytest.approx(statistics.stdev(raw))


@pytest.mark.parametrize("sql", [
    "DELETE FROM events",
    "UPDATE alerts SET status = 'closed'",
    "DROP TABLE incidents",
    "INSERT INTO events (event_id, ts, event_type) VALUES ('x', 'now', 'auth')",
    "CREATE TABLE stolen AS SELECT * FROM events",
    "ATTACH DATABASE '/tmp/other.db' AS other",
    "PRAGMA journal_mode = WAL",
])
def test_writes_and_escapes_are_refused(db_path, sql):
    before = sqlite3.connect(db_path).execute("SELECT COUNT(*) FROM events").fetchone()[0]
    with pytest.raises(hunting.HuntError):
        hunting.run_query(db_path, sql)
    assert sqlite3.connect(db_path).execute("SELECT COUNT(*) FROM events").fetchone()[0] == before


def test_stacked_statements_are_refused(db_path):
    with pytest.raises(hunting.HuntError):
        hunting.run_query(db_path, "SELECT 1; DELETE FROM events")


def test_runaway_queries_are_stopped(db_path):
    with pytest.raises(hunting.HuntError, match="time budget"):
        hunting.run_query(db_path, "SELECT COUNT(*) FROM events a, events b, events c", timeout_s=0.5)


def test_row_cap_flags_truncation(db_path):
    result = hunting.run_query(db_path, "SELECT * FROM events", max_rows=10)
    assert len(result.frame) == 10
    assert result.truncated


def test_ground_truth_reads_as_null(db_path):
    """The labels exist in the table for evaluation, but hunting them would be cheating."""
    frame = hunting.run_query(db_path, "SELECT COUNT(scenario_tag) AS tagged, COUNT(*) AS total FROM events").frame
    assert frame["tagged"].iloc[0] == 0
    assert frame["total"].iloc[0] > 0
    assert sqlite3.connect(db_path).execute("SELECT COUNT(scenario_tag) FROM events").fetchone()[0] > 0


@pytest.mark.parametrize("hunt", hunting.SAVED_HUNTS, ids=lambda h: h.name)
def test_every_saved_hunt_runs(db_path, hunt):
    hunting.run_query(db_path, hunt.sql)
