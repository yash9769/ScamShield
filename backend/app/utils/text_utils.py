"""
backend/app/utils/text_utils.py
Text processing utilities: JSON extraction, sanitisation, truncation.
"""

from __future__ import annotations

import html
import json
import re
from typing import Any


# ── JSON extraction ───────────────────────────────────────────────────────────

_CODE_FENCE_RE = re.compile(r"```(?:json)?\s*([\s\S]*?)\s*```", re.IGNORECASE)
_RAW_JSON_RE = re.compile(r"\{[\s\S]*\}", re.DOTALL)


def extract_json(text: str) -> dict[str, Any]:
    """
    Robustly extract a JSON object from a string that may contain
    markdown fences, prose, or raw JSON.

    Raises:
        ValueError: If no valid JSON object can be found.
    """
    # 1. Try direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # 2. Try content inside ```json ... ```
    fence_match = _CODE_FENCE_RE.search(text)
    if fence_match:
        try:
            return json.loads(fence_match.group(1))
        except json.JSONDecodeError:
            pass

    # 3. Try the first {...} block
    raw_match = _RAW_JSON_RE.search(text)
    if raw_match:
        try:
            return json.loads(raw_match.group(0))
        except json.JSONDecodeError:
            pass

    raise ValueError(f"Could not parse JSON from response: {text[:300]!r}")


# ── Text sanitisation ─────────────────────────────────────────────────────────

_CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
_MULTIPLE_SPACES_RE = re.compile(r" {2,}")


def sanitize_text(text: str, max_length: int = 10_000) -> str:
    """
    Sanitise user-supplied text before sending to AI services.

    - Unescape HTML entities
    - Strip null bytes and dangerous control characters
    - Collapse multiple spaces
    - Truncate to max_length
    """
    text = html.unescape(text)
    text = _CONTROL_CHARS_RE.sub("", text)
    text = _MULTIPLE_SPACES_RE.sub(" ", text)
    return text[:max_length].strip()


def truncate(text: str, max_chars: int = 80, suffix: str = "…") -> str:
    """Return text truncated to max_chars with a suffix if needed."""
    if len(text) <= max_chars:
        return text
    return text[: max_chars - len(suffix)] + suffix


# ── URL utilities ─────────────────────────────────────────────────────────────

_URL_RE = re.compile(
    r"https?://[^\s\]>\"')]+",
    re.IGNORECASE,
)

_SHORT_URL_DOMAINS = frozenset(
    {
        "bit.ly", "tinyurl.com", "goo.gl", "t.co", "ow.ly", "buff.ly",
        "is.gd", "rb.gy", "cutt.ly", "tiny.cc", "adf.ly", "shorturl.at",
        "clck.ru", "qr.ae", "b.link", "dlvr.it", "ift.tt",
    }
)


def extract_urls(text: str) -> list[str]:
    """Extract all HTTP/HTTPS URLs from text."""
    return _URL_RE.findall(text)


def is_shortened_url(url: str) -> bool:
    """Return True if the URL uses a known URL shortener."""
    try:
        # Strip scheme
        domain = url.split("//", 1)[1].split("/")[0].lower()
        # Remove www.
        domain = domain.removeprefix("www.")
        return domain in _SHORT_URL_DOMAINS
    except (IndexError, AttributeError):
        return False


def extract_domain(url: str) -> str | None:
    """Extract the domain from a URL string, or return None."""
    try:
        return url.split("//", 1)[1].split("/")[0].lower()
    except (IndexError, AttributeError):
        return None
