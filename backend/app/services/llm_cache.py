"""
backend/app/services/llm_cache.py
TTL-bounded in-memory cache for LLM verdicts.

Keyed on the SHA-256 of the sanitised input text, so repeated messages (same
copied link, same SMS template sent to many users) skip the paid Gemini/Groq
call entirely. Entries are copied on read/write because callers mutate the
returned AnalysisResult.
"""

from __future__ import annotations

import hashlib
import threading
import time
from collections import OrderedDict
from typing import Optional

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)


class LLMVerdictCache:
    """Thread-safe, size- and TTL-bounded cache."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._ttl = 0
        self._max_size = 0
        self._store: OrderedDict[str, tuple[float, object]] = OrderedDict()

    def _config(self) -> None:
        settings = get_settings()
        self._ttl = int(settings.LLM_CACHE_TTL)
        self._max_size = max(1, int(settings.LLM_CACHE_SIZE))

    def _key(self, text: str) -> str:
        return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()

    def get(self, text: str) -> Optional[object]:
        self._config()
        if self._ttl <= 0:
            return None
        key = self._key(text)
        with self._lock:
            entry = self._store.get(key)
            if entry is None:
                return None
            if (time.monotonic() - entry[0]) >= self._ttl:
                self._store.pop(key, None)
                return None
            self._store.move_to_end(key)
            value = entry[1]
        return self._clone(value)

    def set(self, text: str, value: object) -> None:
        self._config()
        if self._ttl <= 0:
            return
        key = self._key(text)
        with self._lock:
            self._store[key] = (time.monotonic(), self._clone(value))
            self._store.move_to_end(key)
            while len(self._store) > self._max_size:
                self._store.popitem(last=False)

    def stats(self) -> dict:
        with self._lock:
            return {"cache_entries": len(self._store)}

    @staticmethod
    def _clone(value: object) -> object:
        """Return a deep copy so callers can safely mutate the result."""
        try:
            if hasattr(value, "model_copy"):
                return value.model_copy(deep=True)
        except Exception:
            pass
        return value


llm_cache = LLMVerdictCache()


def cache_stats() -> dict:
    return llm_cache.stats()
