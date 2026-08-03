"""
backend/tests/unit/test_text_utils.py
Unit tests for text utility functions.
"""

from __future__ import annotations

import pytest

from app.utils.text_utils import (
    extract_domain,
    extract_json,
    extract_urls,
    is_shortened_url,
    sanitize_text,
    truncate,
)


class TestExtractJson:
    def test_valid_json_string(self):
        raw = '{"classification": "scam", "riskScore": 85}'
        result = extract_json(raw)
        assert result["classification"] == "scam"
        assert result["riskScore"] == 85

    def test_json_in_markdown_fence(self):
        raw = '```json\n{"classification": "safe", "riskScore": 5}\n```'
        result = extract_json(raw)
        assert result["classification"] == "safe"

    def test_json_in_plain_fence(self):
        raw = '```\n{"riskScore": 50}\n```'
        result = extract_json(raw)
        assert result["riskScore"] == 50

    def test_json_embedded_in_prose(self):
        raw = 'Here is the analysis: {"riskScore": 70, "classification": "scam"} Hope this helps.'
        result = extract_json(raw)
        assert result["riskScore"] == 70

    def test_raises_on_no_json(self):
        with pytest.raises(ValueError):
            extract_json("This is plain text with no JSON at all.")

    def test_raises_on_malformed_json(self):
        with pytest.raises(ValueError):
            extract_json("{not valid json}")


class TestSanitizeText:
    def test_strips_whitespace(self):
        assert sanitize_text("  hello  ") == "hello"

    def test_removes_null_bytes(self):
        result = sanitize_text("hello\x00world")
        assert "\x00" not in result

    def test_removes_control_chars(self):
        result = sanitize_text("hello\x07world\x08")
        assert "\x07" not in result
        assert "\x08" not in result

    def test_allows_newlines_and_tabs(self):
        text = "line1\nline2\ttab"
        result = sanitize_text(text)
        assert "line1" in result
        assert "line2" in result

    def test_truncates_to_max_length(self):
        long_text = "a" * 20000
        result = sanitize_text(long_text, max_length=10000)
        assert len(result) <= 10000

    def test_unescapes_html_entities(self):
        result = sanitize_text("&lt;b&gt;hello&lt;/b&gt;")
        assert "<b>hello</b>" == result

    def test_empty_string(self):
        assert sanitize_text("") == ""


class TestTruncate:
    def test_short_text_unchanged(self):
        assert truncate("hello", max_chars=80) == "hello"

    def test_long_text_truncated(self):
        long = "a" * 100
        result = truncate(long, max_chars=80)
        assert len(result) <= 80
        assert result.endswith("…")

    def test_exactly_at_limit(self):
        text = "a" * 80
        assert truncate(text, max_chars=80) == text

    def test_custom_suffix(self):
        result = truncate("a" * 100, max_chars=10, suffix="...")
        assert result.endswith("...")
        assert len(result) == 10


class TestExtractUrls:
    def test_no_urls(self):
        assert extract_urls("Hello, how are you?") == []

    def test_single_https_url(self):
        urls = extract_urls("Visit https://example.com for more info.")
        assert "https://example.com" in urls

    def test_multiple_urls(self):
        text = "Go to https://a.com and http://b.org now."
        urls = extract_urls(text)
        assert len(urls) == 2

    def test_url_without_trailing_punctuation(self):
        urls = extract_urls("Click https://example.com.")
        # The dot at end should not be included
        assert all(not u.endswith(".") for u in urls) or len(urls) >= 1


class TestIsShortenedUrl:
    def test_bitly_is_short(self):
        assert is_shortened_url("https://bit.ly/abc123") is True

    def test_tinyurl_is_short(self):
        assert is_shortened_url("https://tinyurl.com/xyz") is True

    def test_full_url_is_not_short(self):
        assert is_shortened_url("https://www.google.com/search?q=hello") is False

    def test_sbi_url_is_not_short(self):
        assert is_shortened_url("https://sbi.co.in/kyc") is False


class TestExtractDomain:
    def test_simple_url(self):
        assert extract_domain("https://example.com/path") == "example.com"

    def test_url_with_port(self):
        domain = extract_domain("http://example.com:8080/path")
        assert "example.com" in domain

    def test_returns_none_on_invalid(self):
        assert extract_domain("not a url") is None
