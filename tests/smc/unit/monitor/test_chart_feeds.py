# tests/smc/unit/monitor/test_chart_feeds.py
"""Unit tests for chart_feeds.serialize_smc."""
from __future__ import annotations

from datetime import datetime, timezone

import polars as pl
import pytest

from smc.data.schemas import Timeframe
from smc.smc_core.types import (
    FairValueGap,
    LiquidityLevel,
    OrderBlock,
    SMCSnapshot,
    StructureBreak,
    SwingPoint,
)


def _dt(unix: int) -> datetime:
    return datetime.fromtimestamp(unix, tz=timezone.utc)


def _snapshot() -> SMCSnapshot:
    t1 = _dt(1_716_192_000)
    t2 = _dt(1_716_195_600)
    return SMCSnapshot(
        ts=t2,
        timeframe=Timeframe.H1,
        trend_direction="bullish",
        swing_points=(
            SwingPoint(ts=t1, price=3_280.5, swing_type="high", strength=10),
            SwingPoint(ts=t2, price=3_220.0, swing_type="low",  strength=10),
        ),
        order_blocks=(
            OrderBlock(
                ts_start=t1, ts_end=t2,
                high=3_285.0, low=3_278.0,
                ob_type="bearish", timeframe=Timeframe.H1,
                mitigated=False,
            ),
        ),
        fvgs=(
            FairValueGap(
                ts=t1, high=3_270.0, low=3_265.0,
                fvg_type="bullish", timeframe=Timeframe.H1,
                filled_pct=0.3, fully_filled=False,
            ),
        ),
        structure_breaks=(
            StructureBreak(
                ts=t2, price=3_260.0,
                break_type="bos", direction="bullish",
                timeframe=Timeframe.H1,
            ),
        ),
        liquidity_levels=(
            LiquidityLevel(price=3_280.5, level_type="equal_highs", touches=3),
        ),
    )


def _bars() -> pl.DataFrame:
    return pl.DataFrame({
        "ts":    [_dt(1_716_192_000), _dt(1_716_195_600)],
        "open":  [3_230.0, 3_235.0],
        "high":  [3_245.0, 3_250.0],
        "low":   [3_225.0, 3_230.0],
        "close": [3_238.0, 3_242.0],
    })


# ── candles ──────────────────────────────────────────────────────────────

def test_candles_count():
    from smc.monitor.chart_feeds import serialize_smc
    r = serialize_smc(_snapshot(), _bars())
    assert len(r["candles"]) == 2


def test_candles_fields():
    from smc.monitor.chart_feeds import serialize_smc
    c = serialize_smc(_snapshot(), _bars())["candles"][0]
    assert c["time"] == 1_716_192_000
    assert c["open"]  == 3_230.0
    assert c["high"]  == 3_245.0
    assert c["low"]   == 3_225.0
    assert c["close"] == 3_238.0


# ── order_blocks ─────────────────────────────────────────────────────────

def test_ob_serialized():
    from smc.monitor.chart_feeds import serialize_smc
    obs = serialize_smc(_snapshot(), _bars())["order_blocks"]
    assert len(obs) == 1
    ob = obs[0]
    assert ob["ts_start"] == 1_716_192_000
    assert ob["ts_end"]   == 1_716_195_600
    assert ob["ob_type"]  == "bearish"
    assert ob["mitigated"] is False
    assert ob["high"] == 3_285.0
    assert ob["low"]  == 3_278.0


# ── fvgs ─────────────────────────────────────────────────────────────────

def test_fvg_serialized():
    from smc.monitor.chart_feeds import serialize_smc
    fvgs = serialize_smc(_snapshot(), _bars())["fvgs"]
    assert len(fvgs) == 1
    fvg = fvgs[0]
    assert fvg["fvg_type"]   == "bullish"
    assert fvg["filled_pct"] == pytest.approx(0.3)
    assert fvg["fully_filled"] is False


# ── structure_breaks ──────────────────────────────────────────────────────

def test_structure_break_serialized():
    from smc.monitor.chart_feeds import serialize_smc
    sbs = serialize_smc(_snapshot(), _bars())["structure_breaks"]
    assert len(sbs) == 1
    sb = sbs[0]
    assert sb["break_type"] == "bos"
    assert sb["direction"]  == "bullish"
    assert sb["price"]      == 3_260.0


# ── liquidity_levels ─────────────────────────────────────────────────────

def test_liquidity_serialized():
    from smc.monitor.chart_feeds import serialize_smc
    lvs = serialize_smc(_snapshot(), _bars())["liquidity_levels"]
    assert len(lvs) == 1
    lv = lvs[0]
    assert lv["level_type"] == "equal_highs"
    assert lv["touches"]    == 3
    assert lv["swept"]      is False


# ── swing_points ──────────────────────────────────────────────────────────

def test_swings_serialized():
    from smc.monitor.chart_feeds import serialize_smc
    sps = serialize_smc(_snapshot(), _bars())["swing_points"]
    assert len(sps) == 2
    highs = [sp for sp in sps if sp["swing_type"] == "high"]
    assert len(highs) == 1
    assert highs[0]["price"] == 3_280.5
    assert highs[0]["ts"]    == 1_716_192_000
