"""Small live_state snapshots for runtime states outside a full strategy cycle."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from smc.strategy.smc_trace import build_smc_trace

__all__ = ["build_waiting_state"]


def build_waiting_state(
    *,
    cycle: int,
    now: datetime,
    next_bar_close: datetime,
    symbol: str,
    ai_enabled: bool,
    ai_regime_enabled: bool,
    current_price: float | None = None,
) -> dict[str, Any]:
    """Build a fresh dashboard state while live_demo waits for M15 close."""
    reason = "等待下一根 M15 K 线收盘后计算交易信号"
    state: dict[str, Any] = {
        "cycle": cycle,
        "timestamp": now.isoformat(),
        "runtime_status": "waiting_next_m15",
        "symbol": symbol,
        "price": current_price,
        "action": "HOLD",
        "reason": reason,
        "regime": "waiting",
        "ai_direction": "waiting",
        "ai_confidence": 0.0,
        "setups_count": 0,
        "volatility": "waiting",
        "trading_mode": "waiting",
        "blocked_reason": None,
        "range_bounds": None,
        "range_diagnostic": {},
        "smc_diagnostic": {
            "stage_reject": None,
            "final_count": 0,
            "runtime_status": "waiting_next_m15",
        },
        "position_size": 0.0,
        "htf_bias_conf": 0.0,
        "htf_bias_tier": "neutral",
        "next_bar_close": next_bar_close.isoformat(),
        "ai_enabled": ai_enabled,
        "ai_regime_enabled": ai_regime_enabled,
    }
    state["smc_trace"] = build_smc_trace(
        smc_diagnostic=state["smc_diagnostic"],
        range_diagnostic=state["range_diagnostic"],
        setups_count=0,
        action="HOLD",
        reason=reason,
        ai_analysis={
            "ai_source": "waiting",
            "ai_direction": "waiting",
            "ai_confidence": 0.0,
        },
    )
    return state
