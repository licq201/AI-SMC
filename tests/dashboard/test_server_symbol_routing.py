"""Tests for dashboard_server.py — symbol routing (Stage 4).

Uses FastAPI TestClient + tmp_path fixture to verify that every data-related
endpoint correctly resolves the `?symbol=` query param to the right directory,
falls back to XAUUSD for unknown symbols, and that /api/symbols returns the
full registry list.

Import strategy: dashboard_server.py lives in scripts/ which is not a package,
so we load it via importlib.util to avoid requiring changes to pythonpath or
adding an __init__.py to scripts/.
"""
from __future__ import annotations

import importlib.util
import json
import os
import logging
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# Module loader
# ---------------------------------------------------------------------------

_ROOT = Path(__file__).resolve().parent.parent.parent
_SERVER_PATH = _ROOT / "scripts" / "dashboard_server.py"


def _load_server():
    """Dynamically import scripts/dashboard_server.py as a module."""
    spec = importlib.util.spec_from_file_location("dashboard_server", _SERVER_PATH)
    mod = importlib.util.module_from_spec(spec)
    # Ensure src/ is on path so smc.* imports resolve
    src = str(_ROOT / "src")
    if src not in sys.path:
        sys.path.insert(0, src)
    spec.loader.exec_module(mod)
    return mod


# Load once at module level — shared across all tests via module-level reference
_srv = _load_server()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_state_file(directory: Path, data: dict | None = None) -> None:
    """Write a minimal live_state.json into `directory`."""
    directory.mkdir(parents=True, exist_ok=True)
    payload = data if data is not None else {"price": 3333.0, "timestamp": "2026-01-01T00:00:00Z"}
    (directory / "live_state.json").write_text(json.dumps(payload), encoding="utf-8")


def _make_journal_file(directory: Path, entries: list[dict] | None = None) -> None:
    """Write a minimal live_trades.jsonl into `directory/journal/`."""
    journal_dir = directory / "journal"
    journal_dir.mkdir(parents=True, exist_ok=True)
    lines = entries or [{"time": "2026-01-01T01:00:00Z", "action": "BUY", "entry": 3000.0}]
    text = "\n".join(json.dumps(e) for e in lines)
    (journal_dir / "live_trades.jsonl").write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------
# _symbol_data_root unit tests
# ---------------------------------------------------------------------------

class TestSymbolDataRoot:
    """Unit tests for the _symbol_data_root helper."""

    def test_xauusd_returns_correct_path(self, tmp_path: Path) -> None:
        with patch.object(_srv, "DATA", tmp_path):
            result = _srv._symbol_data_root("XAUUSD")
        assert result == tmp_path / "XAUUSD"

    def test_btcusd_returns_correct_path(self, tmp_path: Path) -> None:
        with patch.object(_srv, "DATA", tmp_path):
            result = _srv._symbol_data_root("BTCUSD")
        assert result == tmp_path / "BTCUSD"

    def test_unknown_symbol_falls_back_to_xauusd(self, tmp_path: Path) -> None:
        """Bogus symbol should fall back to XAUUSD with a warning (not raise)."""
        with patch.object(_srv, "DATA", tmp_path):
            result = _srv._symbol_data_root("BOGUS")
        assert result == tmp_path / "XAUUSD"

    def test_unknown_symbol_logs_warning(self, tmp_path: Path, caplog) -> None:
        with patch.object(_srv, "DATA", tmp_path), \
             caplog.at_level(logging.WARNING, logger="dashboard_server"):
            _srv._symbol_data_root("BOGUS_SYM")
        assert "BOGUS_SYM" in caplog.text


class TestMt5SymbolRouting:
    def test_xauusd_uses_env_broker_symbol_override(self, monkeypatch) -> None:
        monkeypatch.setenv("SMC_MT5_SYMBOL", "XAUUSD+")
        from smc.config import SMCConfig

        cfg = SMCConfig(_env_file=None, instrument="XAUUSD")

        assert _srv._mt5_symbol_for("XAUUSD", cfg) == "XAUUSD+"

    def test_btcusd_keeps_registry_mt5_path_without_override(self, monkeypatch) -> None:
        monkeypatch.delenv("SMC_MT5_SYMBOL", raising=False)
        from smc.config import SMCConfig

        cfg = SMCConfig(_env_file=None)

        assert _srv._mt5_symbol_for("BTCUSD", cfg) == "Bitcoin\\BTCUSD"

    def test_dashboard_sets_polars_cpu_check_skip(self) -> None:
        assert os.environ.get("POLARS_SKIP_CPU_CHECK") == "1"

    def test_dashboard_source_reconfigures_stdio_utf8(self) -> None:
        text = _SERVER_PATH.read_text(encoding="utf-8")

        assert "stream.reconfigure(encoding=\"utf-8\"" in text


# ---------------------------------------------------------------------------
# /api/state endpoint
# ---------------------------------------------------------------------------

class TestGetState:
    def test_state_btcusd(self, tmp_path: Path) -> None:
        btc_dir = tmp_path / "BTCUSD"
        _make_state_file(btc_dir, {"price": 99999.0, "timestamp": "2026-01-01T00:00:00Z"})
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/state?symbol=BTCUSD")
        assert r.status_code == 200
        body = r.json()
        assert body["state"]["price"] == 99999.0

    def test_state_no_symbol_defaults_to_xauusd(self, tmp_path: Path) -> None:
        xau_dir = tmp_path / "XAUUSD"
        _make_state_file(xau_dir, {"price": 3400.0, "timestamp": "2026-01-01T00:00:00Z"})
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/state")
        assert r.status_code == 200
        body = r.json()
        assert body["state"]["price"] == 3400.0

    def test_state_unknown_symbol_falls_back_to_xauusd(self, tmp_path: Path) -> None:
        xau_dir = tmp_path / "XAUUSD"
        _make_state_file(xau_dir, {"price": 3401.0, "timestamp": "2026-01-01T00:00:00Z"})
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/state?symbol=BOGUS")
        assert r.status_code == 200
        body = r.json()
        assert body["state"]["price"] == 3401.0

    def test_state_missing_file_returns_null_state(self, tmp_path: Path) -> None:
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/state?symbol=XAUUSD")
        assert r.status_code == 200
        assert r.json()["state"] is None


# ---------------------------------------------------------------------------
# /signal compatibility endpoint
# ---------------------------------------------------------------------------

class TestSignalCompatibility:
    def test_signal_endpoint_accepts_broker_suffixed_xauusd(self, tmp_path: Path) -> None:
        """EA misconfigured to dashboard port 8765 should not receive 404."""
        xau_dir = tmp_path / "XAUUSD"
        _make_state_file(xau_dir, {
            "timestamp": "2026-01-01T00:00:00+00:00",
            "cycle": 77,
            "action": "BUY",
            "trading_mode": "trending",
            "best_setup": {
                "direction": "long",
                "entry": 2350.0,
                "sl": 2348.0,
                "tp1": 2354.0,
                "position_size_lots": 0.3,
                "confluence": 0.7,
            },
        })
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/signal?symbol=XAUUSD%2B")
        assert r.status_code == 200
        body = r.json()
        assert body["symbol"] == "XAUUSD"
        assert body["signals"][0]["action"] == "BUY"


# ---------------------------------------------------------------------------
# /api/symbols endpoint
# ---------------------------------------------------------------------------

class TestListSymbols:
    def test_returns_both_symbols(self) -> None:
        """Registry is populated by the instruments package; must contain XAU + BTC."""
        client = TestClient(_srv.app)
        r = client.get("/api/symbols")
        assert r.status_code == 200
        body = r.json()
        assert "symbols" in body
        assert "XAUUSD" in body["symbols"]
        assert "BTCUSD" in body["symbols"]

    def test_symbols_are_sorted(self) -> None:
        client = TestClient(_srv.app)
        body = client.get("/api/symbols").json()
        assert body["symbols"] == sorted(body["symbols"])


# ---------------------------------------------------------------------------
# /api/journal endpoint
# ---------------------------------------------------------------------------

class TestGetJournal:
    def test_journal_btcusd_with_limit(self, tmp_path: Path) -> None:
        btc_dir = tmp_path / "BTCUSD"
        entries = [
            {"time": f"2026-01-01T0{i}:00:00Z", "action": "BUY", "entry": 90000 + i}
            for i in range(10)
        ]
        _make_journal_file(btc_dir, entries)
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/journal?symbol=BTCUSD&limit=5")
        assert r.status_code == 200
        body = r.json()
        # limit=5 → returns the last 5 entries
        assert len(body["trades"]) == 5

    def test_journal_no_symbol_defaults_xauusd(self, tmp_path: Path) -> None:
        xau_dir = tmp_path / "XAUUSD"
        _make_journal_file(xau_dir, [{"time": "2026-01-01T01:00:00Z", "action": "BUY", "entry": 3000.0}])
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/journal")
        assert r.status_code == 200
        body = r.json()
        assert len(body["trades"]) == 1

    def test_journal_missing_returns_empty(self, tmp_path: Path) -> None:
        with patch.object(_srv, "DATA", tmp_path):
            client = TestClient(_srv.app)
            r = client.get("/api/journal?symbol=BTCUSD")
        assert r.status_code == 200
        assert r.json()["trades"] == []
