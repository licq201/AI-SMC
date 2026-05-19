# src/smc/monitor/chart_feeds.py
"""SMC web-chart serialization helpers for dashboard_server.py."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import polars as pl

from smc.data.schemas import Timeframe
from smc.smc_core.types import SMCSnapshot

__all__ = ["serialize_smc", "TF_MAP", "tf_bar_duration", "swing_length_for"]

TF_MAP: dict[str, Timeframe] = {
    "M15": Timeframe.M15,
    "H1":  Timeframe.H1,
    "H4":  Timeframe.H4,
    "D1":  Timeframe.D1,
}

tf_bar_duration: dict[str, timedelta] = {
    "M15": timedelta(minutes=15),
    "H1":  timedelta(hours=1),
    "H4":  timedelta(hours=4),
    "D1":  timedelta(days=1),
}

_SWING_LENGTHS: dict[str, int] = {
    "M15": 10, "H1": 10, "H4": 7, "D1": 5,
}


def _to_unix(dt: datetime | int) -> int:
    if isinstance(dt, int):
        return dt
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def serialize_smc(snapshot: SMCSnapshot, bars: pl.DataFrame) -> dict[str, Any]:
    candles: list[dict[str, Any]] = []
    for row in bars.iter_rows(named=True):
        ts = row["ts"]
        t = _to_unix(ts) if isinstance(ts, datetime) else int(ts)
        candles.append({
            "time":  t,
            "open":  round(float(row["open"]),  5),
            "high":  round(float(row["high"]),  5),
            "low":   round(float(row["low"]),   5),
            "close": round(float(row["close"]), 5),
        })

    order_blocks = [
        {
            "ts_start": _to_unix(ob.ts_start),
            "ts_end":   _to_unix(ob.ts_end),
            "high":     round(float(ob.high), 5),
            "low":      round(float(ob.low),  5),
            "ob_type":  ob.ob_type,
            "mitigated": ob.mitigated,
        }
        for ob in snapshot.order_blocks
    ]

    fvgs = [
        {
            "ts":          _to_unix(fvg.ts),
            "high":        round(float(fvg.high), 5),
            "low":         round(float(fvg.low),  5),
            "fvg_type":    fvg.fvg_type,
            "filled_pct":  round(float(fvg.filled_pct), 3),
            "fully_filled": fvg.fully_filled,
        }
        for fvg in snapshot.fvgs
    ]

    structure_breaks = [
        {
            "ts":         _to_unix(sb.ts),
            "price":      round(float(sb.price), 5),
            "break_type": sb.break_type,
            "direction":  sb.direction,
        }
        for sb in snapshot.structure_breaks
    ]

    liquidity_levels = [
        {
            "price":      round(float(lv.price), 5),
            "level_type": lv.level_type,
            "touches":    lv.touches,
            "swept":      lv.swept,
        }
        for lv in snapshot.liquidity_levels
    ]

    swing_points = [
        {
            "ts":         _to_unix(sp.ts),
            "price":      round(float(sp.price), 5),
            "swing_type": sp.swing_type,
        }
        for sp in snapshot.swing_points
    ]

    return {
        "candles":          candles,
        "order_blocks":     order_blocks,
        "fvgs":             fvgs,
        "structure_breaks": structure_breaks,
        "liquidity_levels": liquidity_levels,
        "swing_points":     swing_points,
    }


def swing_length_for(tf_str: str) -> int:
    return _SWING_LENGTHS.get(tf_str, 10)
