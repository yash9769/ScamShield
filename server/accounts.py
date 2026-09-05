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

    Foreign keys cascade, so devices, synced scans, family memberships and
    alerts go with it.
    """
    await _aquery("DELETE FROM families WHERE owner_user_id = ?", (user.id,))
    await _aquery("DELETE FROM users WHERE id = ?", (user.id,))
    return {"deleted": True}


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
    return FamilyAlertOut(
        id=alert_id,
        from_display=user.display_name or user.email,
        classification=body.classification,
        risk_score=body.risk_score,
        summary=body.summary,
        acknowledged=False,
    )


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
