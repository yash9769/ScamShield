from __future__ import annotations
"""DPDP-motivated regression tests for server/main.py.

Covers the privacy/security controls added while implementing DPDP Act
alignment: admin-endpoint authorization, audit-log erasure and retention
cleanup, the /scan-batch size/count caps, and that logged data stays
redacted. Run:  cd server && python -m pytest test_dpdp_privacy.py -q
"""

import io
import zipfile
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

import main
from main import app, DB_PATH

main.limiter.enabled = False
client = TestClient(app)

ADMIN_KEY = main.ADMIN_API_KEY  # test-only fallback value when run under pytest


def _make_apk(extra_files: dict | None = None) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("AndroidManifest.xml", "<manifest/>")
        z.writestr("classes.dex", "dex\n035\x00placeholder-bytecode")
        for name, content in (extra_files or {}).items():
            z.writestr(name, content)
    return buf.getvalue()


# ── Admin-endpoint authorization ─────────────────────────────────────────────

def test_dashboard_requires_admin_auth():
    r = client.get("/dashboard")
    assert r.status_code == 401


def test_audit_logs_requires_admin_auth():
    r = client.get("/api/audit-logs")
    assert r.status_code == 401


def test_audit_logs_rejects_wrong_key():
    r = client.get("/api/audit-logs", headers={"X-Admin-Key": "not-the-real-key"})
    assert r.status_code == 401


def test_audit_logs_accepts_correct_key_via_header():
    r = client.get("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY})
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_audit_logs_accepts_bearer_token():
    r = client.get("/api/audit-logs", headers={"Authorization": f"Bearer {ADMIN_KEY}"})
    assert r.status_code == 200


def test_delete_audit_logs_requires_admin_auth():
    r = client.delete("/api/audit-logs")
    assert r.status_code == 401


# ── Right to erasure: purging the audit log ──────────────────────────────────

def test_delete_audit_logs_empties_the_table():
    client.post("/analyze", json={"text": "erasure probe message"})
    before = client.get("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY}).json()
    assert len(before) > 0

    r = client.delete("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY})
    assert r.status_code == 200
    assert r.json()["deleted"] >= len(before)

    after = client.get("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY}).json()
    assert after == []


# ── Retention cleanup ─────────────────────────────────────────────────────────

def test_cleanup_is_a_noop_when_retention_not_configured():
    assert main.AUDIT_LOG_RETENTION_DAYS == ""
    assert main.cleanup_audit_logs() == 0


def test_cleanup_deletes_rows_older_than_configured_retention(monkeypatch):
    import sqlite3
    conn = sqlite3.connect(str(DB_PATH))
    cur = conn.cursor()
    cur.execute("DELETE FROM audit_logs")
    old_ts = (datetime.now() - timedelta(days=100)).strftime("%Y-%m-%d %H:%M:%S")
    recent_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cur.execute(
        "INSERT INTO audit_logs (timestamp, event_type, target, risk_score, risk_level) VALUES (?,?,?,?,?)",
        (old_ts, "text", "old row", 0, "safe"),
    )
    cur.execute(
        "INSERT INTO audit_logs (timestamp, event_type, target, risk_score, risk_level) VALUES (?,?,?,?,?)",
        (recent_ts, "text", "recent row", 0, "safe"),
    )
    conn.commit()
    conn.close()

    monkeypatch.setattr(main, "AUDIT_LOG_RETENTION_DAYS", "30")
    deleted = main.cleanup_audit_logs()
    assert deleted == 1

    remaining = client.get("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY}).json()
    targets = [row["target"] for row in remaining]
    assert "old row" not in targets
    assert "recent row" in targets


def test_cleanup_ignores_invalid_retention_value(monkeypatch):
    monkeypatch.setattr(main, "AUDIT_LOG_RETENTION_DAYS", "not-a-number")
    assert main.cleanup_audit_logs() == 0


# ── Logged content stays redacted (no secrets persisted) ─────────────────────

def test_analyzed_text_containing_a_secret_pattern_is_redacted_in_audit_log():
    client.delete("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY})
    fake_key = "AIzaSyDUMMYFAKEKEYFORTESTS0000000000"
    client.post("/analyze", json={"text": f"my key is {fake_key} do not share"})
    logs = client.get("/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY}).json()
    assert len(logs) == 1
    assert fake_key not in logs[0]["target"]
    assert "[REDACTED_SECRET]" in logs[0]["target"]


# ── /scan-batch size and count caps ──────────────────────────────────────────

def test_scan_batch_rejects_too_many_files():
    apk = _make_apk()
    files = [(f"f{i}.apk", apk, "application/octet-stream") for i in range(main.MAX_BATCH_FILES + 1)]
    r = client.post(
        "/scan-batch",
        files=[("files", f) for f in files],
    )
    assert r.status_code == 400


def test_scan_batch_skips_oversized_file_without_crashing(monkeypatch):
    monkeypatch.setattr(main, "MAX_APK_SIZE", 10)  # tiny cap, easy to exceed
    apk = _make_apk({"classes2.dex": "well over ten bytes of content"})
    r = client.post(
        "/scan-batch",
        files=[("files", ("big.apk", apk, "application/octet-stream"))],
    )
    assert r.status_code == 200
    body = r.json()
    assert body["results"][0]["status"] == "skipped"
    assert "100MB" in body["results"][0]["reason"] or "exceeds" in body["results"][0]["reason"].lower()


def test_scan_batch_within_limits_still_scans_normally():
    apk = _make_apk({"classes2.dex": "batch probe content"})
    r = client.post(
        "/scan-batch",
        files=[("files", ("ok.apk", apk, "application/octet-stream"))],
    )
    assert r.status_code == 200
    body = r.json()
    assert body["results"][0]["status"] == "scanned"
