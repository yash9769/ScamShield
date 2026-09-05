"""
server/test_accounts.py

Tests for accounts, cross-device sync, family protection and trends.

The isolation tests are the important ones here: this module introduced the
first multi-user surface in ScamShield, so "user B cannot see user A's data"
is the property most worth pinning down against future refactors.
"""

import os
import pathlib
import tempfile

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("ADMIN_API_KEY", "test-key")
os.environ.setdefault("SESSION_SECRET_KEY", "test-session-secret")

import accounts  # noqa: E402


@pytest.fixture()
def client(monkeypatch):
    """A client backed by throwaway databases, so tests never touch real data."""
    accounts.ACCOUNTS_DB_PATH = pathlib.Path(tempfile.mktemp(suffix=".db"))
    accounts.init_accounts_db()

    import main as m

    m.DB_PATH = pathlib.Path(tempfile.mktemp(suffix=".db"))
    m.init_audit_db()
    m.init_scam_reports_db()

    with TestClient(m.app) as c:
        yield c


def _register(client, email, password="hunter2pass"):
    resp = client.post(
        "/account/register",
        json={"email": email, "password": password, "display_name": email.split("@")[0]},
    )
    assert resp.status_code == 200, resp.text
    return {"Authorization": f"Bearer {resp.json()['token']}"}


# ── Accounts ──────────────────────────────────────────────────────────────────

class TestAccounts:
    def test_register_normalizes_email_and_returns_session(self, client):
        resp = client.post(
            "/account/register",
            json={"email": "Asha@Example.COM", "password": "hunter2pass"},
        )
        assert resp.status_code == 200
        assert resp.json()["email"] == "asha@example.com"
        assert resp.json()["auth_provider"] == "password"
        assert resp.json()["token"]

    def test_duplicate_registration_is_rejected(self, client):
        _register(client, "asha@example.com")
        resp = client.post(
            "/account/register", json={"email": "asha@example.com", "password": "hunter2pass"}
        )
        assert resp.status_code == 409

    def test_password_must_mix_letters_and_digits(self, client):
        resp = client.post(
            "/account/register", json={"email": "a@b.com", "password": "alllettersonly"}
        )
        assert resp.status_code == 422

    def test_login_round_trip(self, client):
        _register(client, "asha@example.com")
        resp = client.post(
            "/account/login", json={"email": "asha@example.com", "password": "hunter2pass"}
        )
        assert resp.status_code == 200

    def test_wrong_password_and_unknown_user_are_indistinguishable(self, client):
        """Same status and message either way, so the endpoint can't be used to
        enumerate which addresses have accounts."""
        _register(client, "asha@example.com")
        wrong = client.post(
            "/account/login", json={"email": "asha@example.com", "password": "wrongpass1"}
        )
        unknown = client.post(
            "/account/login", json={"email": "nobody@example.com", "password": "wrongpass1"}
        )
        assert wrong.status_code == unknown.status_code == 401
        assert wrong.json()["detail"] == unknown.json()["detail"]

    def test_me_requires_a_valid_token(self, client):
        assert client.get("/account/me").status_code == 401
        assert client.get("/account/me", headers={"Authorization": "Bearer garbage"}).status_code == 401

    def test_me_returns_the_signed_in_user(self, client):
        headers = _register(client, "asha@example.com")
        resp = client.get("/account/me", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["email"] == "asha@example.com"

    def test_google_endpoint_rejects_unverifiable_tokens(self, client):
        """Without a verified ID token this endpoint would be an auth bypass,
        so an unusable token must never mint a session."""
        resp = client.post("/account/google", json={"id_token": "not-a-real-token"})
        assert resp.status_code in (401, 503)


# ── Sync ──────────────────────────────────────────────────────────────────────

class TestSync:
    def test_push_then_pull_from_another_device(self, client):
        headers = _register(client, "asha@example.com")
        push = client.post(
            "/sync/scans",
            headers=headers,
            json={
                "device_id": "dev-1",
                "since": 0,
                "scans": [{
                    "id": "s1", "input_text": "URGENT KYC", "classification": "scam",
                    "risk_score": 91, "summary": "Bank scam", "source": "SMS",
                }],
            },
        )
        assert push.status_code == 200
        assert push.json()["accepted"] == 1

        pull = client.post(
            "/sync/scans", headers=headers, json={"device_id": "dev-2", "since": 0, "scans": []}
        )
        assert len(pull.json()["scans"]) == 1
        assert pull.json()["scans"][0]["classification"] == "scam"

    def test_scans_are_isolated_between_users(self, client):
        a = _register(client, "asha@example.com")
        b = _register(client, "raj@example.com")
        client.post(
            "/sync/scans",
            headers=a,
            json={"since": 0, "scans": [{"id": "s1", "summary": "private"}]},
        )
        resp = client.post("/sync/scans", headers=b, json={"since": 0, "scans": []})
        assert resp.json()["scans"] == []

    def test_resending_the_same_id_updates_rather_than_duplicates(self, client):
        headers = _register(client, "asha@example.com")
        for score in (50, 95):
            client.post(
                "/sync/scans",
                headers=headers,
                json={"since": 0, "scans": [{"id": "s1", "risk_score": score, "summary": "x"}]},
            )
        resp = client.post("/sync/scans", headers=headers, json={"since": 0, "scans": []})
        assert len(resp.json()["scans"]) == 1
        assert resp.json()["scans"][0]["risk_score"] == 95

    def test_deletes_travel_as_tombstones(self, client):
        """A delete that was only an absence would be resurrected by the next
        device to sync, so it has to be an explicit flag."""
        headers = _register(client, "asha@example.com")
        client.post("/sync/scans", headers=headers,
                    json={"since": 0, "scans": [{"id": "s1", "summary": "x"}]})
        client.post("/sync/scans", headers=headers,
                    json={"since": 0, "scans": [{"id": "s1", "summary": "x", "deleted": True}]})
        resp = client.post("/sync/scans", headers=headers, json={"since": 0, "scans": []})
        assert resp.json()["scans"][0]["deleted"] is True

    def test_oversized_batches_are_rejected(self, client):
        headers = _register(client, "asha@example.com")
        scans = [{"id": f"b{i}", "summary": "x"} for i in range(accounts.MAX_SYNC_BATCH + 50)]
        resp = client.post("/sync/scans", headers=headers, json={"since": 0, "scans": scans})
        assert resp.status_code == 422

    def test_sync_requires_authentication(self, client):
        assert client.post("/sync/scans", json={"since": 0, "scans": []}).status_code == 401


# ── Family protection ─────────────────────────────────────────────────────────

class TestFamily:
    def test_no_family_is_a_normal_empty_state(self, client):
        headers = _register(client, "asha@example.com")
        resp = client.get("/family", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["id"] is None

    def test_create_join_and_alert_flow(self, client):
        daughter = _register(client, "daughter@example.com")
        father = _register(client, "father@example.com")

        created = client.post("/family/create", headers=daughter, json={"name": "Sharma Family"})
        assert created.status_code == 200
        code = created.json()["invite_code"]

        joined = client.post(
            "/family/join", headers=father, json={"invite_code": code, "role": "protected"}
        )
        assert joined.status_code == 200
        assert len(joined.json()["members"]) == 2

        alert = client.post(
            "/family/alert",
            headers=father,
            json={"classification": "scam", "risk_score": 93, "summary": "Fake bank KYC call"},
        )
        assert alert.status_code == 200

        seen = client.get("/family", headers=daughter).json()
        assert len(seen["alerts"]) == 1
        assert seen["alerts"][0]["summary"] == "Fake bank KYC call"
        assert seen["alerts"][0]["acknowledged"] is False

    def test_cannot_be_in_two_families(self, client):
        headers = _register(client, "asha@example.com")
        client.post("/family/create", headers=headers, json={"name": "One"})
        assert client.post("/family/create", headers=headers, json={"name": "Two"}).status_code == 409

    def test_invalid_invite_code_is_rejected(self, client):
        headers = _register(client, "asha@example.com")
        resp = client.post("/family/join", headers=headers, json={"invite_code": "not-a-code"})
        assert resp.status_code == 404

    def test_outsiders_cannot_see_or_touch_a_family(self, client):
        member = _register(client, "member@example.com")
        outsider = _register(client, "outsider@example.com")

        client.post("/family/create", headers=member, json={"name": "Private"})
        client.post("/family/alert", headers=member,
                    json={"classification": "scam", "risk_score": 90, "summary": "secret"})
        alert_id = client.get("/family", headers=member).json()["alerts"][0]["id"]

        assert client.get("/family", headers=outsider).json()["id"] is None
        assert client.post("/family/alert", headers=outsider,
                           json={"classification": "scam", "risk_score": 1,
                                 "summary": "x"}).status_code == 404
        # Knowing an alert id must not be enough to acknowledge it.
        assert client.post(f"/family/alert/{alert_id}/ack", headers=outsider).status_code == 404
        assert client.get("/family", headers=member).json()["alerts"][0]["acknowledged"] is False

    def test_acknowledging_an_alert(self, client):
        headers = _register(client, "asha@example.com")
        client.post("/family/create", headers=headers, json={"name": "Fam"})
        client.post("/family/alert", headers=headers,
                    json={"classification": "scam", "risk_score": 90, "summary": "x"})
        alert_id = client.get("/family", headers=headers).json()["alerts"][0]["id"]

        assert client.post(f"/family/alert/{alert_id}/ack", headers=headers).status_code == 200
        assert client.get("/family", headers=headers).json()["alerts"][0]["acknowledged"] is True

    def test_last_member_leaving_dissolves_the_group(self, client):
        a = _register(client, "a@example.com")
        b = _register(client, "b@example.com")
        code = client.post("/family/create", headers=a, json={"name": "Fam"}).json()["invite_code"]
        client.post("/family/join", headers=b, json={"invite_code": code})

        client.post("/family/leave", headers=a)
        client.post("/family/leave", headers=b)

        c_headers = _register(client, "c@example.com")
        assert client.post("/family/join", headers=c_headers,
                           json={"invite_code": code}).status_code == 404


# ── Trends & UPI reputation ───────────────────────────────────────────────────

class TestTrendsAndUpi:
    def test_upi_handles_normalize_to_one_record(self, client):
        for value in (" Fraud@OKAXIS ", "fraud@okaxis", "FRAUD@okaxis"):
            client.post("/report", json={"indicator_type": "upi", "indicator_value": value,
                                         "category": "upi fraud"})
        resp = client.get("/reputation/upi/fraud@okaxis")
        assert resp.json()["report_count"] == 3
        assert resp.json()["reported"] is True

    def test_unreported_upi_handle_is_clean(self, client):
        resp = client.get("/reputation/upi/clean@okhdfcbank")
        assert resp.status_code == 200
        assert resp.json()["reported"] is False
        assert resp.json()["report_count"] == 0

    def test_trends_aggregate_by_category(self, client):
        client.post("/report", json={"indicator_type": "upi", "indicator_value": "a@okaxis",
                                     "category": "upi fraud"})
        client.post("/report", json={"indicator_type": "phone", "indicator_value": "9876543210",
                                     "category": "lottery"})
        resp = client.get("/trends?days=7")
        assert resp.status_code == 200
        categories = {t["category"]: t["reports"] for t in resp.json()["trends"]}
        assert categories["upi fraud"] == 1
        assert categories["lottery"] == 1
        assert resp.json()["total_reports"] == 2

    def test_trend_window_is_clamped(self, client):
        assert client.get("/trends?days=9999").json()["window_days"] == 90
        assert client.get("/trends?days=-5").json()["window_days"] == 1

    def test_trends_never_leak_the_reported_indicators(self, client):
        """The feed says what is going around, not where to find it."""
        client.post("/report", json={"indicator_type": "upi", "indicator_value": "scammer@okaxis",
                                     "category": "upi fraud"})
        body = client.get("/trends?days=7").text
        assert "scammer@okaxis" not in body
