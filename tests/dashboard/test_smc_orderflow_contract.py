"""Contract tests for dashboard-facing ``state.smc_orderflow`` payloads."""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from smc.strategy.smc_orderflow import build_smc_orderflow

_ROOT = Path(__file__).resolve().parent.parent.parent
_SERVER_PATH = _ROOT / "scripts" / "dashboard_server.py"
_READINESS_VALUES = {"ready", "waiting", "blocked", "unknown"}
_SUMMARY_KEYS = {"bias", "readiness", "headline", "blocking_reason"}
_RADAR_KEYS = {"structure", "zone", "liquidity", "entry", "risk"}
_RADAR_ITEM_KEYS = {"key", "label", "status", "title", "detail"}
_TIMELINE_ITEM_KEYS = {"timeframe", "label", "status", "explanation"}
_KEY_LEVEL_ITEM_KEYS = {"kind", "label", "side", "detail"}


def _load_server():
    src = str(_ROOT / "src")
    if src not in sys.path:
        sys.path.insert(0, src)
    spec = importlib.util.spec_from_file_location("dashboard_server_smc_orderflow", _SERVER_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_srv = _load_server()


def _write_state(directory: Path, smc_orderflow: dict) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    payload = {
        "timestamp": "2026-05-19T00:00:00Z",
        "price": 3350.0,
        "smc_orderflow": smc_orderflow,
    }
    (directory / "live_state.json").write_text(json.dumps(payload), encoding="utf-8")


def _sample_smc_orderflow() -> dict:
    return build_smc_orderflow(
        smc_trace={"decision": {"setup_count": 1}},
        smc_diagnostic={
            "current_price": 3350.0,
            "final_count": 1,
            "h1_zones_count": 1,
            "htf_bias_confidence": 0.82,
            "htf_bias_direction": "bullish",
            "htf_bias_rationale": "D1 BOS up; H4 CHoCH confirmed.",
            "zone_details": [
                {
                    "direction": "long",
                    "low": 3330.0,
                    "high": 3342.0,
                    "dist_from_price": "8.0",
                    "in_expanded_zone": True,
                }
            ],
            "zone_rejects": {
                "entry_none": 0,
                "confluence_low": 0,
                "trigger_filter": 0,
            },
        },
        range_diagnostic={"detect": {"final_source": "recent_swing"}},
        best_setup={
            "direction": "long",
            "trigger": "choch_in_zone",
            "entry": 3348.0,
            "sl": 3332.0,
            "tp1": 3380.0,
            "exec_rr_ratio": 2.0,
            "confluence": 0.76,
        },
        current_price=3350.0,
    )


def test_api_state_smc_orderflow_contract_shape(tmp_path: Path) -> None:
    _write_state(tmp_path / "XAUUSD", _sample_smc_orderflow())

    with patch.object(_srv, "DATA", tmp_path):
        client = TestClient(_srv.app)
        response = client.get("/api/state?symbol=XAUUSD")

    assert response.status_code == 200
    smc_orderflow = response.json()["state"]["smc_orderflow"]

    summary = smc_orderflow["summary"]
    assert _SUMMARY_KEYS <= summary.keys()
    assert summary["readiness"] in _READINESS_VALUES

    radar = smc_orderflow["radar"]
    assert {item["key"] for item in radar} == _RADAR_KEYS
    for item in radar:
        assert _RADAR_ITEM_KEYS <= item.keys()

    timeline = smc_orderflow["timeline"]
    assert timeline
    for item in timeline:
        assert _TIMELINE_ITEM_KEYS <= item.keys()

    key_levels = smc_orderflow["key_levels"]
    assert key_levels
    for item in key_levels:
        assert _KEY_LEVEL_ITEM_KEYS <= item.keys()
        assert "price" in item or {"low", "high"} <= item.keys()
