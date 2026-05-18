"""Tests for live_state status snapshots written before the first M15 cycle."""

from __future__ import annotations

from datetime import datetime, timezone

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
