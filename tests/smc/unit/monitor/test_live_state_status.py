"""Tests for live_state status snapshots written before the first M15 cycle."""

from __future__ import annotations

from datetime import datetime, timezone
import importlib
import json
import sys
from types import SimpleNamespace

from smc.monitor.live_state_status import build_waiting_state


def test_build_waiting_state_is_fresh_hold_snapshot() -> None:
    now = datetime(2026, 5, 18, 15, 21, 12, tzinfo=timezone.utc)
    next_close = datetime(2026, 5, 18, 15, 30, 0, tzinfo=timezone.utc)

    state = build_waiting_state(
        cycle=1,
        now=now,
        next_bar_close=next_close,
        symbol="XAUUSD",
        ai_enabled=True,
        ai_regime_enabled=True,
    )

    assert state["timestamp"] == now.isoformat()
    assert state["runtime_status"] == "waiting_next_m15"
    assert state["action"] == "HOLD"
    assert state["reason"] == "等待下一根 M15 K 线收盘后计算交易信号"
    assert state["next_bar_close"] == next_close.isoformat()
    assert state["ai_enabled"] is True
    assert state["ai_regime_enabled"] is True
    assert state["smc_trace"]["current_stage"] == "decision"
    assert state["smc_trace"]["decision"]["action"] == "HOLD"


def test_build_waiting_state_keeps_latest_price_for_dashboard() -> None:
    now = datetime(2026, 5, 18, 15, 21, 12, tzinfo=timezone.utc)
    next_close = datetime(2026, 5, 18, 15, 30, 0, tzinfo=timezone.utc)

    state = build_waiting_state(
        cycle=1,
        now=now,
        next_bar_close=next_close,
        symbol="XAUUSD",
        ai_enabled=True,
        ai_regime_enabled=True,
        current_price=2350.8,
    )

    assert state["runtime_status"] == "waiting_next_m15"
    assert state["price"] == 2350.8


def test_live_demo_save_state_includes_smc_orderflow(monkeypatch, tmp_path) -> None:
    monkeypatch.setitem(sys.modules, "MetaTrader5", SimpleNamespace())
    monkeypatch.setattr(sys, "argv", ["live_demo.py"])
    monkeypatch.setattr("os.open", lambda *args, **kwargs: 123)
    monkeypatch.setattr("os.write", lambda *args, **kwargs: None)
    monkeypatch.setattr("os.close", lambda *args, **kwargs: None)
    monkeypatch.setattr("os.makedirs", lambda *args, **kwargs: None)
    monkeypatch.setattr("atexit.register", lambda *args, **kwargs: None)

    state_path = tmp_path / "live_state.json"

    try:
        sys.modules.pop("scripts.live_demo", None)
        live_demo = importlib.import_module("scripts.live_demo")
        monkeypatch.setattr(live_demo, "STATE_PATH", state_path)

        aggregator = SimpleNamespace(
            _last_setup_diagnostic={
                "htf_bias_direction": "bullish",
                "htf_bias_confidence": 0.72,
                "h1_zones_count": 1,
                "zone_rejects": {"entry_none": 1},
                "current_price": 2350.8,
                "min_confluence": 0.6,
            }
        )

        state = live_demo.save_state(
            cycle=1,
            price=2350.8,
            action="HOLD",
            reason="No M15 trigger",
            ai_analysis={"ai_direction": "bullish", "ai_confidence": 0.7},
            regime="trending",
            setups=[],
            best_setup=None,
            aggregator=aggregator,
        )
    finally:
        sys.modules.pop("scripts.live_demo", None)

    assert "smc_orderflow" in state
    assert state["smc_orderflow"]["summary"]["bias"] == "bullish"
    assert state["smc_orderflow"]["summary"]["readiness"] == "waiting"
    assert state["smc_orderflow"]["radar"]

    written_state = json.loads(state_path.read_text(encoding="utf-8"))
    assert "smc_orderflow" in written_state
    assert written_state["smc_orderflow"]["summary"]["bias"] == "bullish"
    assert written_state["smc_orderflow"]["summary"]["readiness"] == "waiting"
