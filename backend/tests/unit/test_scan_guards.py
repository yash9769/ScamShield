"""
backend/tests/unit/test_scan_guards.py
Unit tests for the APK pipeline hardening added during the security audit:

- ZIP-bomb / archive validation guards (_validate_archive)
- Risk engine score clamping to the 0-100 contract
"""

from __future__ import annotations

import io
import zipfile

import pytest
from fastapi import HTTPException

from app.routes.scan import _validate_archive
from app.services.risk_engine import RiskEngine


def _make_zip(members: dict[str, bytes], compress_type: int = zipfile.ZIP_DEFLATED) -> bytes:
    """Build an in-memory zip with {filename: content} members."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=compress_type) as zf:
        for name, content in members.items():
            zf.writestr(name, content)
    return buf.getvalue()


class TestArchiveValidation:
    def test_valid_apk_passes(self, tmp_path):
        p = tmp_path / "ok.apk"
        p.write_bytes(_make_zip({"classes.dex": b"\x00" * 1024, "AndroidManifest.xml": b"\x01" * 512}))
        # Must not raise.
        _validate_archive(str(p))

    def test_non_zip_is_rejected(self, tmp_path):
        p = tmp_path / "fake.apk"
        p.write_bytes(b"this is definitely not a zip archive")
        with pytest.raises(HTTPException) as exc:
            _validate_archive(str(p))
        assert exc.value.status_code == 400

    def test_high_compression_ratio_is_rejected(self, tmp_path):
        """A classic zip bomb: tiny compressed size, huge uncompressed size."""
        p = tmp_path / "bomb.apk"
        # 100 MB of zeros compresses to a few KB → ratio far above the 250 cap.
        p.write_bytes(_make_zip({"classes.dex": b"\x00" * (100 * 1024 * 1024)}))
        with pytest.raises(HTTPException) as exc:
            _validate_archive(str(p))
        assert exc.value.status_code == 413
        assert "compression ratio" in exc.value.detail

    def test_too_many_entries_is_rejected(self, tmp_path):
        p = tmp_path / "many.apk"
        # 5001 tiny members > the 5000 entry cap.
        p.write_bytes(_make_zip({f"f{i}": b"x" for i in range(5001)}, compress_type=zipfile.ZIP_STORED))
        with pytest.raises(HTTPException) as exc:
            _validate_archive(str(p))
        assert exc.value.status_code == 413
        assert "too many entries" in exc.value.detail


class TestRiskEngineClamping:
    def test_score_never_exceeds_100(self):
        """Summed evidence weights must be clamped to the documented 0-100 range."""
        engine = RiskEngine()
        # Fabricate findings whose weighted sum far exceeds 100.
        data = {
            "yara": {"matches": [{"rule": "android_trojan_1"}, {"rule": "sms_sniffer_2"},
                                   {"rule": "banker_3"}, {"rule": "spyware_4"}]},
            "androguard": {
                "permissions": ["android.permission.SEND_SMS", "android.permission.READ_SMS"],
                "capability_indicators": ["Landroid/telephony/SmsManager;", "Ldalvik/system/DexClassLoader;"],
                "certificates": [{"subject": "CN=Android Debug"}],
                "is_signed": True,
                "is_signed_v1": True,
                "is_signed_v2": False,
            },
            "secrets": {"findings": {"AWS_KEY": 3, "GITHUB_TOKEN": 1}},
            "osint": {"virustotal": {"malicious": 30, "suspicious": 20, "status": "found"}},
        }
        result = engine.calculate_risk(data)
        assert 0 <= result["score"] <= 100
