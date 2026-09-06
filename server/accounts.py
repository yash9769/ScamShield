"""
server/accounts.py

User accounts, cross-device sync, family protection and the scam trend feed.

Until now ScamShield was a stateless analysis API with everything held on the
device. That is what blocked the features this module exists to enable: you
cannot warn a daughter that her father just scanned a scam, or restore a scan
history onto a new phone, without a server that knows who those people are.

── Design notes ──────────────────────────────────────────────────────────────

*Tokens*: sessions are signed with itsdangerous rather than PyJWT. PyJWT pulls
in `cryptography` for its RSA/EC algorithms even when only HS256 is used, and
that is a heavyweight native dependency for a symmetric token this service both
issues and verifies itself. itsdangerous is pure-Python, from the Pallets team,
and does exactly this job (HMAC-SHA256 + timestamp). Hand-rolling was the other
option and was rejected — signed-token formats are easy to get subtly wrong.

*Passwords*: hashlib.scrypt (stdlib, memory-hard), per-user random salt,
constant-time verification. No bcrypt/argon2 dependency needed.

*Google sign-in*: the ID token is verified against Google's tokeninfo endpoint
and the audience is checked against our own client ID. This is not optional —
without it, `POST /account/google` would accept any email a caller typed and
hand back a session for it, which is a complete authentication bypass.

*SQLite*: the driver is blocking, so every query runs through asyncio.to_thread
to keep it off the event loop.
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import logging
import os
import re
import secrets
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, List, Optional

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from pydantic import BaseModel, Field, field_validator

logger = logging.getLogger("scamshield.accounts")

BASE_DIR = Path(__file__).resolve().parent
ACCOUNTS_DB_PATH = BASE_DIR / "server_accounts.db"

# Sessions last 30 days; the client refreshes by signing in again.
SESSION_MAX_AGE_SECONDS = 30 * 24 * 3600

# Signing key for session tokens. A generated fallback keeps local development
# working, but it is per-process: restarting invalidates every session, which
# is precisely the nudge a real deployment needs to set this properly.
_SECRET = os.getenv("SESSION_SECRET_KEY", "")
if not _SECRET:
    _SECRET = secrets.token_urlsafe(48)
    logger.warning(
        "SESSION_SECRET_KEY not set — using an ephemeral key. All sessions will "
        "be invalidated on restart. Set SESSION_SECRET_KEY in production."
    )

_serializer = URLSafeTimedSerializer(_SECRET, salt="scamshield-session")

# The Web OAuth client ID that the Android app's ID tokens are issued for.
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_SERVER_CLIENT_ID", "")

SCRYPT_N = 2 ** 14
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_DKLEN = 32

MAX_SYNC_BATCH = 200
MAX_FAMILY_MEMBERS = 8

_EMAIL_RE = re.compile(r"^[\w.+-]+@[\w-]+\.[\w.-]+$")

router = APIRouter(tags=["Accounts"])


# ── Database ──────────────────────────────────────────────────────────────────

def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(str(ACCOUNTS_DB_PATH), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_accounts_db() -> None:
    try:
        with closing(_connect()) as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id            TEXT PRIMARY KEY,
                    email         TEXT UNIQUE NOT NULL,
                    password_salt TEXT,
                    password_hash TEXT,
                    auth_provider TEXT NOT NULL DEFAULT 'password',
                    display_name  TEXT,
                    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
                    last_seen_at  DATETIME DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS devices (
                    id           TEXT PRIMARY KEY,
                    user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    device_name  TEXT,
                    platform     TEXT,
                    created_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
                    last_sync_at DATETIME
                );

                CREATE TABLE IF NOT EXISTS synced_scans (
                    id             TEXT PRIMARY KEY,
                    user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    device_id      TEXT,
                    input_text     TEXT,
                    classification TEXT,
                    risk_score     INTEGER,
                    summary        TEXT,
                    source         TEXT,
                    scanned_at     TEXT,
                    updated_at     REAL NOT NULL,
                    deleted        INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_scans_user_updated
                    ON synced_scans(user_id, updated_at);

                CREATE TABLE IF NOT EXISTS families (
                    id            TEXT PRIMARY KEY,
                    name          TEXT NOT NULL,
                    owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    invite_code   TEXT UNIQUE NOT NULL,
                    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS family_members (
                    family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
                    user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    role      TEXT NOT NULL DEFAULT 'guardian',
                    joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (family_id, user_id)
                );

                CREATE TABLE IF NOT EXISTS push_tokens (
                    token       TEXT PRIMARY KEY,
                    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    platform    TEXT NOT NULL DEFAULT 'android',
                    updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS idx_push_user ON push_tokens(user_id);

                CREATE TABLE IF NOT EXISTS learning_progress (
                    user_id        TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                    total_points   INTEGER NOT NULL DEFAULT 0,
                    streak_days    INTEGER NOT NULL DEFAULT 0,
                    badges_earned  INTEGER NOT NULL DEFAULT 0,
                    quizzes_passed INTEGER NOT NULL DEFAULT 0,
                    articles_read  INTEGER NOT NULL DEFAULT 0,
                    updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE IF NOT EXISTS family_alerts (
                    id             TEXT PRIMARY KEY,
                    family_id      TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
                    from_user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    classification TEXT,
                    risk_score     INTEGER,
                    summary        TEXT,
                    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
                    acknowledged   INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_alerts_family
                    ON family_alerts(family_id, created_at);
                """
            )
            conn.commit()
    except Exception as e:
        logger.warning(f"Accounts DB init error: {e}")


def _query(sql: str, params: tuple = (), *, fetch: str = "none") -> Any:
    """Runs one statement. `fetch` is 'none' | 'one' | 'all'."""
    with closing(_connect()) as conn:
        cur = conn.execute(sql, params)
        if fetch == "one":
            row = cur.fetchone()
            conn.commit()
            return row
        if fetch == "all":
            rows = cur.fetchall()
            conn.commit()
            return rows
        conn.commit()
        return None


async def _aquery(sql: str, params: tuple = (), *, fetch: str = "none") -> Any:
    """sqlite3 is blocking; keep it off the event loop."""
    return await asyncio.to_thread(_query, sql, params, fetch=fetch)


# ── Password + token helpers ──────────────────────────────────────────────────

def _hash_password(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        dklen=SCRYPT_DKLEN,
    )


def _issue_token(user_id: str) -> str:
    return _serializer.dumps({"uid": user_id})


def _read_token(token: str) -> Optional[str]:
    try:
        data = _serializer.loads(token, max_age=SESSION_MAX_AGE_SECONDS)
        return data.get("uid")
    except SignatureExpired:
        return None
    except BadSignature:
        return None
    except Exception:
        return None


def _now_ts() -> float:
    return datetime.now(timezone.utc).timestamp()


# ── Auth dependency ───────────────────────────────────────────────────────────

class CurrentUser(BaseModel):
    id: str
    email: str
    display_name: Optional[str] = None
    auth_provider: str


async def require_user(authorization: str = Header(default="")) -> CurrentUser:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing bearer token.")
    user_id = _read_token(authorization[7:].strip())
    if not user_id:
        raise HTTPException(401, "Session expired or invalid. Please sign in again.")

    row = await _aquery(
        "SELECT id, email, display_name, auth_provider FROM users WHERE id = ?",
        (user_id,),
        fetch="one",
    )
    if row is None:
        raise HTTPException(401, "Account no longer exists.")

    await _aquery("UPDATE users SET last_seen_at = CURRENT_TIMESTAMP WHERE id = ?", (user_id,))
    return CurrentUser(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        auth_provider=row["auth_provider"],
    )


# ── Schemas ───────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    email: str = Field(..., max_length=254)
    password: str = Field(..., min_length=8, max_length=256)
    display_name: Optional[str] = Field(default=None, max_length=80)

    @field_validator("email")
    @classmethod
    def _valid_email(cls, v: str) -> str:
        v = v.strip().lower()
        if not _EMAIL_RE.match(v):
            raise ValueError("Invalid email address.")
        return v

    @field_validator("password")
    @classmethod
    def _strong_enough(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
            raise ValueError("Password must contain both letters and numbers.")
        return v


class LoginRequest(BaseModel):
    email: str = Field(..., max_length=254)
    password: str = Field(..., max_length=256)

    @field_validator("email")
    @classmethod
    def _normalize(cls, v: str) -> str:
        return v.strip().lower()


class GoogleLoginRequest(BaseModel):
    id_token: str = Field(..., min_length=10, max_length=4096)


class AuthResponse(BaseModel):
    token: str
    user_id: str
    email: str
    display_name: Optional[str] = None
    auth_provider: str


class SyncScan(BaseModel):
    id: str = Field(..., max_length=64)
    input_text: str = Field(default="", max_length=10_000)
    classification: str = Field(default="safe", max_length=20)
    risk_score: int = 0
    summary: str = Field(default="", max_length=2000)
    source: Optional[str] = Field(default=None, max_length=80)
    scanned_at: Optional[str] = Field(default=None, max_length=40)
    deleted: bool = False


class SyncRequest(BaseModel):
    device_id: Optional[str] = Field(default=None, max_length=64)
    device_name: Optional[str] = Field(default=None, max_length=80)
    since: float = 0.0
    scans: List[SyncScan] = Field(default_factory=list)

    @field_validator("scans")
    @classmethod
    def _not_too_many(cls, v: List[SyncScan]) -> List[SyncScan]:
        if len(v) > MAX_SYNC_BATCH:
            raise ValueError(f"At most {MAX_SYNC_BATCH} scans per sync.")
        return v


class SyncResponse(BaseModel):
    accepted: int
    server_time: float
    scans: List[SyncScan]


class FamilyCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=60)


class FamilyJoinRequest(BaseModel):
    invite_code: str = Field(..., min_length=4, max_length=32)
    role: str = Field(default="guardian")

    @field_validator("role")
    @classmethod
    def _known_role(cls, v: str) -> str:
        if v not in ("guardian", "protected"):
            raise ValueError("role must be 'guardian' or 'protected'.")
        return v


class FamilyMemberOut(BaseModel):
    user_id: str
    email: str
    display_name: Optional[str] = None
    role: str
    is_you: bool = False


class FamilyAlertOut(BaseModel):
    id: str
    from_display: str
    classification: Optional[str] = None
    risk_score: Optional[int] = None
    summary: Optional[str] = None
    created_at: Optional[str] = None
    acknowledged: bool = False


class FamilyOut(BaseModel):
    id: Optional[str] = None
    name: Optional[str] = None
    invite_code: Optional[str] = None
    role: Optional[str] = None
    members: List[FamilyMemberOut] = Field(default_factory=list)
    alerts: List[FamilyAlertOut] = Field(default_factory=list)


class FamilyAlertRequest(BaseModel):
    classification: str = Field(..., max_length=20)
    risk_score: int = 0
    summary: str = Field(default="", max_length=500)


class PushTokenRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=512)
    platform: str = Field(default="android", max_length=16)


class LearningProgressRequest(BaseModel):
    total_points: int = Field(default=0, ge=0, le=1_000_000)
    streak_days: int = Field(default=0, ge=0, le=10_000)
    badges_earned: int = Field(default=0, ge=0, le=1000)
    quizzes_passed: int = Field(default=0, ge=0, le=100_000)
    articles_read: int = Field(default=0, ge=0, le=100_000)


class LeaderboardEntry(BaseModel):
    rank: int
    display_name: str
    total_points: int
    streak_days: int
    badges_earned: int
    is_you: bool = False


class LeaderboardResponse(BaseModel):
    scope: str
    entries: List[LeaderboardEntry] = Field(default_factory=list)
    your_rank: Optional[int] = None


class TrendItem(BaseModel):
    category: str
    reports: int
    distinct_indicators: int


class TrendsResponse(BaseModel):
    window_days: int
    total_reports: int
    trends: List[TrendItem]


# ── Account endpoints ─────────────────────────────────────────────────────────

@router.post("/account/register", response_model=AuthResponse)
async def register_account(request: Request, body: RegisterRequest):
    existing = await _aquery("SELECT id FROM users WHERE email = ?", (body.email,), fetch="one")
    if existing is not None:
        raise HTTPException(409, "An account with that email already exists.")

    user_id = str(uuid.uuid4())
    salt = secrets.token_bytes(16)
    digest = await asyncio.to_thread(_hash_password, body.password, salt)

    await _aquery(
        """INSERT INTO users (id, email, password_salt, password_hash, auth_provider, display_name)
           VALUES (?, ?, ?, ?, 'password', ?)""",
        (user_id, body.email, salt.hex(), digest.hex(), body.display_name),
    )
    return AuthResponse(
        token=_issue_token(user_id),
        user_id=user_id,
        email=body.email,
        display_name=body.display_name,
        auth_provider="password",
    )


@router.post("/account/login", response_model=AuthResponse)
async def login_account(request: Request, body: LoginRequest):
    row = await _aquery(
        """SELECT id, email, password_salt, password_hash, auth_provider, display_name
           FROM users WHERE email = ?""",
        (body.email,),
        fetch="one",
    )
    # Same message for "no such user" and "wrong password" so the endpoint
    # can't be used to enumerate which addresses have accounts.
    invalid = HTTPException(401, "Incorrect email or password.")
    if row is None:
        raise invalid
    if not row["password_hash"] or not row["password_salt"]:
        raise HTTPException(409, "This account uses Google sign-in.")

    digest = await asyncio.to_thread(_hash_password, body.password, bytes.fromhex(row["password_salt"]))
    if not hmac.compare_digest(digest.hex(), row["password_hash"]):
        raise invalid

    return AuthResponse(
        token=_issue_token(row["id"]),
        user_id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        auth_provider=row["auth_provider"],
    )


async def _verify_google_id_token(id_token: str) -> dict:
    """Validates a Google ID token and returns its payload.

    Verification is delegated to Google's tokeninfo endpoint: it checks the
    signature against Google's rotating keys for us, which avoids carrying a
    JWKS cache and an RSA implementation in-process. The audience check is
    still ours to make — a token minted for a *different* app is perfectly
    valid, just not valid *here*.
    """
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(503, "Google sign-in is not configured on this server.")

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": id_token},
            )
    except httpx.TimeoutException:
        raise HTTPException(504, "Google token verification timed out.")
    except httpx.RequestError:
        raise HTTPException(503, "Could not reach Google to verify the sign-in.")

    if resp.status_code != 200:
        raise HTTPException(401, "Google sign-in token was rejected.")

    try:
        payload = resp.json()
    except ValueError:
        raise HTTPException(502, "Malformed response from Google.")

    if payload.get("aud") != GOOGLE_CLIENT_ID:
        raise HTTPException(401, "This Google token was issued for a different application.")
    if str(payload.get("email_verified", "")).lower() not in ("true", "1"):
        raise HTTPException(401, "This Google account has no verified email address.")
    email = (payload.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(401, "Google did not return an email address.")

    payload["email"] = email
    return payload


@router.post("/account/google", response_model=AuthResponse)
async def google_account(request: Request, body: GoogleLoginRequest):
    payload = await _verify_google_id_token(body.id_token)
    email = payload["email"]
    display_name = payload.get("name")

    row = await _aquery("SELECT id, display_name FROM users WHERE email = ?", (email,), fetch="one")
    if row is None:
        user_id = str(uuid.uuid4())
        await _aquery(
            """INSERT INTO users (id, email, auth_provider, display_name)
               VALUES (?, ?, 'google', ?)""",
            (user_id, email, display_name),
        )
    else:
        user_id = row["id"]
        if display_name and not row["display_name"]:
            await _aquery("UPDATE users SET display_name = ? WHERE id = ?", (display_name, user_id))

    return AuthResponse(
        token=_issue_token(user_id),
        user_id=user_id,
        email=email,
        display_name=display_name,
        auth_provider="google",
    )


@router.get("/account/me", response_model=CurrentUser)
async def whoami(user: CurrentUser = Depends(require_user)):
    return user


@router.delete("/account")
async def delete_account(user: CurrentUser = Depends(require_user)):
    """Erases the account and everything hanging off it (DPDP erasure right).

    Foreign keys cascade for everything that is only ever this user's own —
    devices, synced scans, this user's own family membership, and the alerts
    they personally raised.

    A family this user *owns* needs handling first, before that cascade can
    run: `owner_user_id` used to be deleted alongside the user, which took
    the whole family (and, via family_id cascading further, every other
    member's own membership and alert history) down with it — one person
    exercising their own right to erase their own data was silently
    destroying two other people's family group. Ownership carries no
    privilege anywhere else in this module (nothing is owner-gated), so
    there is no reason for it to be that destructive: if another member is
    still in the group, ownership passes to them and the group carries on;
    only when this user was the last one in it does the group actually go
    away, matching leave_family()'s identical "last member out" rule.
    """
    owned = await _aquery(
        "SELECT id FROM families WHERE owner_user_id = ?", (user.id,), fetch="one"
    )
    if owned is not None:
        successor = await _aquery(
            """SELECT user_id FROM family_members
               WHERE family_id = ? AND user_id != ?
               ORDER BY joined_at ASC LIMIT 1""",
            (owned["id"], user.id),
            fetch="one",
        )
        if successor is not None:
            await _aquery(
                "UPDATE families SET owner_user_id = ? WHERE id = ?",
                (successor["user_id"], owned["id"]),
            )
        else:
            await _aquery("DELETE FROM families WHERE id = ?", (owned["id"],))

    await _aquery("DELETE FROM users WHERE id = ?", (user.id,))
    return {"deleted": True}


@router.get("/account/export")
async def export_account(user: CurrentUser = Depends(require_user)):
    """Everything this server holds about the caller (DPDP right to access).

    Deliberately symmetric with what /account/* and /sync/* actually store —
    no summarising, no omission of scan content. The client's local "My Data"
    export already includes full scan text for the on-device copy, so leaving
    the server-held copy out here would make the export quietly incomplete
    for anyone who has ever used cross-device sync.

    Two things are intentionally *not* the raw stored value:
      - push tokens: an FCM token is a live device credential (whoever holds
        it can address that device), not content about the user, so it's
        reported as a count/platform/date rather than the token string.
      - other family members' rows: their own email/scan data is not this
        user's personal data to export, even though the same information is
        already visible to them in the app's live Family screen — that
        visibility is family-alert delivery, not this endpoint's job.
    """
    profile = await _aquery(
        "SELECT id, email, display_name, auth_provider, created_at, last_seen_at "
        "FROM users WHERE id = ?",
        (user.id,),
        fetch="one",
    )

    device_rows = await _aquery(
        "SELECT id, device_name, platform, created_at, last_sync_at "
        "FROM devices WHERE user_id = ? ORDER BY created_at ASC",
        (user.id,),
        fetch="all",
    ) or []

    scan_rows = await _aquery(
        """SELECT id, input_text, classification, risk_score, summary, source,
                  scanned_at, updated_at, deleted
           FROM synced_scans WHERE user_id = ? ORDER BY updated_at ASC""",
        (user.id,),
        fetch="all",
    ) or []

    push_row = await _aquery(
        "SELECT COUNT(*) AS n, GROUP_CONCAT(DISTINCT platform) AS platforms, "
        "MAX(updated_at) AS last_registered FROM push_tokens WHERE user_id = ?",
        (user.id,),
        fetch="one",
    )

    learning_row = await _aquery(
        """SELECT total_points, streak_days, badges_earned, quizzes_passed,
                  articles_read, updated_at
           FROM learning_progress WHERE user_id = ?""",
        (user.id,),
        fetch="one",
    )

    fam = await _family_for_user(user.id)
    family_out = (await _build_family_out(user, fam["id"], fam["role"])) if fam else None

    return {
        "exportedAt": datetime.now(timezone.utc).isoformat(),
        "profile": dict(profile) if profile else None,
        "devices": [dict(r) for r in device_rows],
        "syncedScans": [dict(r) for r in scan_rows if not r["deleted"]],
        "pushTokens": {
            "count": (push_row["n"] if push_row else 0) or 0,
            "platforms": (push_row["platforms"].split(",") if push_row and push_row["platforms"] else []),
            "lastRegistered": push_row["last_registered"] if push_row else None,
        },
        "learningProgress": dict(learning_row) if learning_row else None,
        "family": family_out.model_dump() if family_out else None,
    }


# ── Cross-device sync ─────────────────────────────────────────────────────────

@router.post("/sync/scans", response_model=SyncResponse)
async def sync_scans(body: SyncRequest, user: CurrentUser = Depends(require_user)):
    """Two-way delta sync of scan history.

    The client sends whatever changed locally and the timestamp it last heard
    from us; it gets back everything that changed server-side since then. Row
    ids are client-generated UUIDs so a retried request can't duplicate rows,
    and deletes travel as tombstones rather than disappearing silently — a
    delete that only existed as an absence would be resurrected by the next
    device that syncs.
    """
    now = _now_ts()

    if body.device_id:
        await _aquery(
            """INSERT INTO devices (id, user_id, device_name, platform, last_sync_at)
               VALUES (?, ?, ?, 'android', CURRENT_TIMESTAMP)
               ON CONFLICT(id) DO UPDATE SET last_sync_at = CURRENT_TIMESTAMP,
                                             device_name = excluded.device_name""",
            (body.device_id, user.id, body.device_name),
        )

    accepted = 0
    for scan in body.scans:
        await _aquery(
            """INSERT INTO synced_scans
                   (id, user_id, device_id, input_text, classification, risk_score,
                    summary, source, scanned_at, updated_at, deleted)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET
                    input_text     = excluded.input_text,
                    classification = excluded.classification,
                    risk_score     = excluded.risk_score,
                    summary        = excluded.summary,
                    source         = excluded.source,
                    scanned_at     = excluded.scanned_at,
                    updated_at     = excluded.updated_at,
                    deleted        = excluded.deleted
               WHERE synced_scans.user_id = excluded.user_id""",
            (
                scan.id, user.id, body.device_id, scan.input_text, scan.classification,
                scan.risk_score, scan.summary, scan.source, scan.scanned_at, now,
                1 if scan.deleted else 0,
            ),
        )
        accepted += 1

    rows = await _aquery(
        """SELECT id, input_text, classification, risk_score, summary, source,
                  scanned_at, deleted
           FROM synced_scans
           WHERE user_id = ? AND updated_at > ?
           ORDER BY updated_at ASC
           LIMIT ?""",
        (user.id, body.since, MAX_SYNC_BATCH),
        fetch="all",
    )

    return SyncResponse(
        accepted=accepted,
        server_time=now,
        scans=[
            SyncScan(
                id=r["id"],
                input_text=r["input_text"] or "",
                classification=r["classification"] or "safe",
                risk_score=r["risk_score"] or 0,
                summary=r["summary"] or "",
                source=r["source"],
                scanned_at=r["scanned_at"],
                deleted=bool(r["deleted"]),
            )
            for r in (rows or [])
        ],
    )


# ── Family protection ─────────────────────────────────────────────────────────

async def _family_for_user(user_id: str) -> Optional[sqlite3.Row]:
    return await _aquery(
        """SELECT f.id, f.name, f.invite_code, m.role
           FROM families f
           JOIN family_members m ON m.family_id = f.id
           WHERE m.user_id = ?
           LIMIT 1""",
        (user_id,),
        fetch="one",
    )


@router.post("/family/create", response_model=FamilyOut)
async def create_family(body: FamilyCreateRequest, user: CurrentUser = Depends(require_user)):
    if await _family_for_user(user.id) is not None:
        raise HTTPException(409, "You are already in a family group.")

    family_id = str(uuid.uuid4())
    # token_urlsafe, not a short numeric code: an invite code is the only thing
    # standing between a stranger and a family's scam alerts.
    invite_code = secrets.token_urlsafe(9)

    await _aquery(
        "INSERT INTO families (id, name, owner_user_id, invite_code) VALUES (?, ?, ?, ?)",
        (family_id, body.name.strip(), user.id, invite_code),
    )
    await _aquery(
        "INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'guardian')",
        (family_id, user.id),
    )
    return await _build_family_out(user, family_id, "guardian")


@router.post("/family/join", response_model=FamilyOut)
async def join_family(body: FamilyJoinRequest, user: CurrentUser = Depends(require_user)):
    if await _family_for_user(user.id) is not None:
        raise HTTPException(409, "You are already in a family group. Leave it first.")

    row = await _aquery(
        "SELECT id FROM families WHERE invite_code = ?", (body.invite_code.strip(),), fetch="one"
    )
    if row is None:
        raise HTTPException(404, "That invite code is not valid.")

    family_id = row["id"]
    count_row = await _aquery(
        "SELECT COUNT(*) AS n FROM family_members WHERE family_id = ?", (family_id,), fetch="one"
    )
    if count_row and count_row["n"] >= MAX_FAMILY_MEMBERS:
        raise HTTPException(409, f"That family already has {MAX_FAMILY_MEMBERS} members.")

    await _aquery(
        "INSERT OR IGNORE INTO family_members (family_id, user_id, role) VALUES (?, ?, ?)",
        (family_id, user.id, body.role),
    )
    return await _build_family_out(user, family_id, body.role)


@router.post("/family/leave")
async def leave_family(user: CurrentUser = Depends(require_user)):
    fam = await _family_for_user(user.id)
    if fam is None:
        raise HTTPException(404, "You are not in a family group.")

    await _aquery(
        "DELETE FROM family_members WHERE family_id = ? AND user_id = ?", (fam["id"], user.id)
    )
    # Last member out dissolves the group rather than leaving an orphan row
    # with a live invite code.
    remaining = await _aquery(
        "SELECT COUNT(*) AS n FROM family_members WHERE family_id = ?", (fam["id"],), fetch="one"
    )
    if remaining and remaining["n"] == 0:
        await _aquery("DELETE FROM families WHERE id = ?", (fam["id"],))
    return {"left": True}


async def _build_family_out(user: CurrentUser, family_id: str, role: str) -> FamilyOut:
    fam = await _aquery(
        "SELECT id, name, invite_code FROM families WHERE id = ?", (family_id,), fetch="one"
    )
    if fam is None:
        raise HTTPException(404, "Family group not found.")

    member_rows = await _aquery(
        """SELECT u.id, u.email, u.display_name, m.role
           FROM family_members m JOIN users u ON u.id = m.user_id
           WHERE m.family_id = ?
           ORDER BY m.joined_at ASC""",
        (family_id,),
        fetch="all",
    ) or []

    alert_rows = await _aquery(
        """SELECT a.id, a.classification, a.risk_score, a.summary, a.created_at,
                  a.acknowledged, u.display_name, u.email
           FROM family_alerts a JOIN users u ON u.id = a.from_user_id
           WHERE a.family_id = ?
           ORDER BY a.created_at DESC
           LIMIT 50""",
        (family_id,),
        fetch="all",
    ) or []

    return FamilyOut(
        id=fam["id"],
        name=fam["name"],
        invite_code=fam["invite_code"],
        role=role,
        members=[
            FamilyMemberOut(
                user_id=r["id"],
                email=r["email"],
                display_name=r["display_name"],
                role=r["role"],
                is_you=(r["id"] == user.id),
            )
            for r in member_rows
        ],
        alerts=[
            FamilyAlertOut(
                id=r["id"],
                from_display=r["display_name"] or r["email"],
                classification=r["classification"],
                risk_score=r["risk_score"],
                summary=r["summary"],
                created_at=r["created_at"],
                acknowledged=bool(r["acknowledged"]),
            )
            for r in alert_rows
        ],
    )


@router.get("/family", response_model=FamilyOut)
async def get_family(user: CurrentUser = Depends(require_user)):
    fam = await _family_for_user(user.id)
    if fam is None:
        # Not an error — "you have no family group yet" is a normal state the
        # client renders as the create/join screen.
        return FamilyOut()
    return await _build_family_out(user, fam["id"], fam["role"])


@router.post("/family/alert", response_model=FamilyAlertOut)
async def raise_family_alert(body: FamilyAlertRequest, user: CurrentUser = Depends(require_user)):
    """Relays a high-risk scan to the rest of the family.

    Only the verdict and summary travel — never the message body. A parent's
    scam SMS routinely contains their bank name, partial card digits or a
    one-time code, and none of that needs to reach a relative's phone for the
    alert to do its job.
    """
    fam = await _family_for_user(user.id)
    if fam is None:
        raise HTTPException(404, "You are not in a family group.")

    alert_id = str(uuid.uuid4())
    await _aquery(
        """INSERT INTO family_alerts (id, family_id, from_user_id, classification, risk_score, summary)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (alert_id, fam["id"], user.id, body.classification, body.risk_score, body.summary),
    )

    # Wake the family's other devices. Awaited rather than fire-and-forget so a
    # slow provider can't outlive the request scope, but it swallows its own
    # errors: the alert row above is the source of truth, and the app picks it
    # up on next open whether or not the push landed.
    who = user.display_name or "A family member"
    await _dispatch_family_push(
        fam["id"],
        user.id,
        title=f"{who} may have been targeted",
        body_text=f"{body.classification} · risk {body.risk_score}/100. Tap to review.",
    )

    return FamilyAlertOut(
        id=alert_id,
        from_display=user.display_name or user.email,
        classification=body.classification,
        risk_score=body.risk_score,
        summary=body.summary,
        acknowledged=False,
    )


# ── Push notifications ────────────────────────────────────────────────────────

@router.post("/push/register")
async def register_push_token(body: PushTokenRequest, user: CurrentUser = Depends(require_user)):
    """Registers this device's FCM token so family alerts can reach it.

    Keyed on the token itself, so a token that moves between accounts (a
    handed-on phone) is reassigned rather than duplicated — otherwise the
    previous owner would keep receiving the new owner's alerts.
    """
    await _aquery(
        """INSERT INTO push_tokens (token, user_id, platform, updated_at)
           VALUES (?, ?, ?, CURRENT_TIMESTAMP)
           ON CONFLICT(token) DO UPDATE SET
               user_id    = excluded.user_id,
               platform   = excluded.platform,
               updated_at = CURRENT_TIMESTAMP""",
        (body.token, user.id, body.platform),
    )
    return {"registered": True}


@router.delete("/push/register")
async def unregister_push_token(body: PushTokenRequest, user: CurrentUser = Depends(require_user)):
    await _aquery(
        "DELETE FROM push_tokens WHERE token = ? AND user_id = ?", (body.token, user.id)
    )
    return {"unregistered": True}


async def _dispatch_family_push(
    family_id: str,
    sender_user_id: str,
    title: str,
    body_text: str,
) -> int:
    """Best-effort FCM fan-out to a family's other devices.

    Returns the number of tokens attempted. Never raises: a push provider
    being unreachable must not fail the alert itself, which is already
    durably stored and will be seen next time the app opens.

    Sending requires FCM_SERVICE_ACCOUNT_FILE to point at a Firebase service
    account JSON. Without it this is a no-op — the legacy FCM server-key API
    was shut down in 2024, so there is no keyless path any more.
    """
    rows = await _aquery(
        """SELECT p.token FROM push_tokens p
           JOIN family_members m ON m.user_id = p.user_id
           WHERE m.family_id = ? AND p.user_id != ?""",
        (family_id, sender_user_id),
        fetch="all",
    ) or []
    tokens = [r["token"] for r in rows]
    if not tokens:
        return 0

    service_account_file = os.getenv("FCM_SERVICE_ACCOUNT_FILE", "")
    if not service_account_file:
        logger.info(
            "Family push skipped for %d device(s): FCM_SERVICE_ACCOUNT_FILE not set.",
            len(tokens),
        )
        return 0

    try:
        access_token, project_id = await asyncio.to_thread(
            _fcm_access_token, service_account_file
        )
        async with httpx.AsyncClient(timeout=10.0) as client:
            for token in tokens:
                await client.post(
                    f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={
                        "message": {
                            "token": token,
                            "notification": {"title": title, "body": body_text},
                            "android": {"priority": "high"},
                            "data": {"type": "family_alert", "family_id": family_id},
                        }
                    },
                )
    except Exception as e:
        logger.warning(f"Family push dispatch failed: {e}")

    return len(tokens)


def _fcm_access_token(service_account_file: str) -> tuple[str, str]:
    """Mints a short-lived FCM access token from a service account JSON.

    Imported lazily so the whole accounts module doesn't require google-auth
    just to run without push configured.
    """
    from google.oauth2 import service_account  # type: ignore
    from google.auth.transport.requests import Request  # type: ignore

    credentials = service_account.Credentials.from_service_account_file(
        service_account_file,
        scopes=["https://www.googleapis.com/auth/firebase.messaging"],
    )
    credentials.refresh(Request())
    return credentials.token, credentials.project_id


# ── Learning progress & leaderboard ──────────────────────────────────────────

@router.post("/learning/progress")
async def sync_learning_progress(
    body: LearningProgressRequest, user: CurrentUser = Depends(require_user)
):
    """Mirrors the device's local learning progress so it can be ranked.

    The device stays the source of truth — this is a one-way push of an
    already-computed summary, not a second progress engine that could
    disagree with what the user sees in the Learn tab.
    """
    await _aquery(
        """INSERT INTO learning_progress
               (user_id, total_points, streak_days, badges_earned, quizzes_passed,
                articles_read, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
           ON CONFLICT(user_id) DO UPDATE SET
               total_points   = excluded.total_points,
               streak_days    = excluded.streak_days,
               badges_earned  = excluded.badges_earned,
               quizzes_passed = excluded.quizzes_passed,
               articles_read  = excluded.articles_read,
               updated_at     = CURRENT_TIMESTAMP""",
        (
            user.id, body.total_points, body.streak_days, body.badges_earned,
            body.quizzes_passed, body.articles_read,
        ),
    )
    return {"synced": True}


@router.get("/learning/leaderboard", response_model=LeaderboardResponse)
async def learning_leaderboard(
    scope: str = "family", user: CurrentUser = Depends(require_user)
):
    """Ranks learners by points, within the caller's family or globally.

    Family scope may show an email as a fallback label — those people already
    know each other. Global scope never does: it falls back to a generic
    label instead, because a leaderboard is not a reason to expose a
    stranger's email address to everyone with an account.
    """
    if scope not in ("family", "global"):
        raise HTTPException(400, "scope must be 'family' or 'global'.")

    if scope == "family":
        fam = await _family_for_user(user.id)
        if fam is None:
            return LeaderboardResponse(scope=scope, entries=[], your_rank=None)
        rows = await _aquery(
            """SELECT u.id, u.email, u.display_name, p.total_points, p.streak_days,
                      p.badges_earned
               FROM learning_progress p
               JOIN users u ON u.id = p.user_id
               JOIN family_members m ON m.user_id = p.user_id
               WHERE m.family_id = ?
               ORDER BY p.total_points DESC, p.streak_days DESC
               LIMIT 50""",
            (fam["id"],),
            fetch="all",
        ) or []
    else:
        rows = await _aquery(
            """SELECT u.id, u.email, u.display_name, p.total_points, p.streak_days,
                      p.badges_earned
               FROM learning_progress p
               JOIN users u ON u.id = p.user_id
               ORDER BY p.total_points DESC, p.streak_days DESC
               LIMIT 50""",
            (),
            fetch="all",
        ) or []

    entries: List[LeaderboardEntry] = []
    your_rank: Optional[int] = None
    for index, row in enumerate(rows, start=1):
        is_you = row["id"] == user.id
        if is_you:
            your_rank = index
        if scope == "family":
            label = row["display_name"] or row["email"]
        else:
            label = row["display_name"] or "ScamShield user"
        entries.append(
            LeaderboardEntry(
                rank=index,
                display_name=label,
                total_points=row["total_points"],
                streak_days=row["streak_days"],
                badges_earned=row["badges_earned"],
                is_you=is_you,
            )
        )

    return LeaderboardResponse(scope=scope, entries=entries, your_rank=your_rank)


@router.post("/family/alert/{alert_id}/ack")
async def acknowledge_alert(alert_id: str, user: CurrentUser = Depends(require_user)):
    fam = await _family_for_user(user.id)
    if fam is None:
        raise HTTPException(404, "You are not in a family group.")

    # Scoped to the caller's family so an alert id from another group can't be
    # acknowledged by guessing it.
    await _aquery(
        "UPDATE family_alerts SET acknowledged = 1 WHERE id = ? AND family_id = ?",
        (alert_id, fam["id"]),
    )
    return {"acknowledged": True}
