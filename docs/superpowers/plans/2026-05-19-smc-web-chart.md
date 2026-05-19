# SMC Web Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增独立网页 `dashboard/chart.html`，从 MT5 实时拉取 OHLCV，通过 TradingView Lightweight Charts 渲染 K 线，并叠加 OB 矩形、FVG 矩形、BOS/CHoCH 水平线、EQH/EQL 流动性线和 Swing 标记。

**Architecture:** 在现有 FastAPI 服务（port 8765）新增 `/api/candles` 和 `/api/smc` 两个端点。纯函数序列化逻辑放在 `src/smc/monitor/chart_feeds.py`（遵循 `dashboard_feeds.py` 已有模式），端点调用 MT5Adapter → SMCDetector → chart_feeds 三步流水线。前端用 Canvas 叠加层绘制矩形/线，Lightweight Charts 的 `setMarkers` 绘制 Swing 标记，无需第三方插件。

**Tech Stack:** FastAPI (已有), Polars (已有), SMCDetector (已有), MT5Adapter (已有), TradingView Lightweight Charts v4.2 (CDN), HTML5 Canvas, Alpine.js (不引入，用原生 JS)

---

## File Map

| 动作 | 路径 | 职责 |
|------|------|------|
| Create | `src/smc/monitor/chart_feeds.py` | 纯函数：`serialize_smc(snapshot, bars)` |
| Create | `tests/smc/unit/monitor/test_chart_feeds.py` | 序列化单元测试 |
| Modify | `scripts/dashboard_server.py` | 新增 `_fetch_bars()` helper + `/api/candles` + `/api/smc` |
| Create | `dashboard/chart.html` | 独立 SMC 图表页面（K 线 + 4 类 SMC 叠加） |

---

## Task 1: `chart_feeds.py` — 序列化 Helper

**Files:**
- Create: `src/smc/monitor/chart_feeds.py`
- Create: `tests/smc/unit/monitor/test_chart_feeds.py`

- [ ] **Step 1.1: 写失败测试**

```python
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
```

- [ ] **Step 1.2: 运行确认失败**

```
pytest tests/smc/unit/monitor/test_chart_feeds.py -v
```
预期：`ModuleNotFoundError: No module named 'smc.monitor.chart_feeds'`

- [ ] **Step 1.3: 实现 `chart_feeds.py`**

```python
# src/smc/monitor/chart_feeds.py
"""SMC web-chart serialization helpers for dashboard_server.py.

Public API
----------
serialize_smc(snapshot, bars) → dict
    Convert SMCSnapshot + raw OHLCV DataFrame into a JSON-serializable dict
    whose shape matches what dashboard/chart.html expects.

TF_MAP / tf_bar_duration
    Timeframe string → enum / timedelta mapping shared with the endpoint layer.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import polars as pl

from smc.data.schemas import Timeframe
from smc.smc_core.types import SMCSnapshot

__all__ = ["serialize_smc", "TF_MAP", "tf_bar_duration"]

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


def _to_unix(dt: datetime) -> int:
    """Return unix timestamp (seconds) for *dt*, treating naive as UTC."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def serialize_smc(snapshot: SMCSnapshot, bars: pl.DataFrame) -> dict[str, Any]:
    """Convert *snapshot* + raw OHLCV *bars* into a JSON-serializable dict.

    Keys returned
    -------------
    candles          list[{time, open, high, low, close}]
    order_blocks     list[{ts_start, ts_end, high, low, ob_type, mitigated}]
    fvgs             list[{ts, high, low, fvg_type, filled_pct, fully_filled}]
    structure_breaks list[{ts, price, break_type, direction}]
    liquidity_levels list[{price, level_type, touches, swept}]
    swing_points     list[{ts, price, swing_type}]
    """
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
    """Return the per-timeframe swing_length parameter for SMCDetector."""
    return _SWING_LENGTHS.get(tf_str, 10)
```

- [ ] **Step 1.4: 运行确认通过**

```
pytest tests/smc/unit/monitor/test_chart_feeds.py -v
```
预期：8 tests PASSED

- [ ] **Step 1.5: Commit**

```bash
git add src/smc/monitor/chart_feeds.py tests/smc/unit/monitor/test_chart_feeds.py
git commit -m "feat(chart): add chart_feeds serialization helpers"
```

---

## Task 2: 新增 `/api/candles` 和 `/api/smc` 端点

**Files:**
- Modify: `scripts/dashboard_server.py`（在现有最后一个 `@app.post` 和 `@app.get("/")` 之间插入）

- [ ] **Step 2.1: 在 `dashboard_server.py` 顶部 imports 区插入新 imports**

在文件开头已有的 `from datetime import datetime, timezone` 那行**后面**插入：

```python
from datetime import timedelta
```

（`timezone` 已经 import 了，只需加 `timedelta`）

- [ ] **Step 2.2: 在 `@app.get("/")` 路由之前插入 `_fetch_bars` helper 和两个端点**

找到文件末尾：
```python
@app.get("/")
def index() -> FileResponse:
```

在这一行**前面**插入以下全部代码：

```python
# ---------------------------------------------------------------------------
# Chart data — /api/candles and /api/smc
# ---------------------------------------------------------------------------

def _fetch_bars(symbol: str, tf_str: str, limit: int) -> "pl.DataFrame":
    """Fetch recent OHLCV bars from a live MT5 terminal.

    Raises
    ------
    HTTPException(400)  Unknown timeframe string.
    HTTPException(503)  MT5 mock mode, missing credentials, or connection failure.
    """
    import polars as pl  # noqa: F811 — local import keeps server startup fast
    from smc.config import SMCConfig
    from smc.monitor.chart_feeds import TF_MAP, tf_bar_duration

    cfg = SMCConfig()

    if cfg.mt5_mock:
        raise HTTPException(
            status_code=503,
            detail=(
                "MT5 not connected: SMC_MT5_MOCK=1. "
                "Set SMC_MT5_MOCK=0 on Windows VPS with MT5 running."
            ),
        )
    if not cfg.has_mt5_credentials():
        raise HTTPException(
            status_code=503,
            detail=(
                "MT5 credentials not configured. "
                "Set SMC_MT5_LOGIN, SMC_MT5_PASSWORD, SMC_MT5_SERVER in .env"
            ),
        )
    if tf_str not in TF_MAP:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown timeframe {tf_str!r}. Valid: {sorted(TF_MAP)}",
        )

    from smc.data.adapters.mt5_adapter import MT5Adapter

    tf_enum   = TF_MAP[tf_str]
    duration  = tf_bar_duration[tf_str]
    end       = datetime.now(timezone.utc)
    start     = end - duration * (limit + 60)   # 60-bar safety buffer

    try:
        with MT5Adapter(
            login=cfg.mt5_login,
            password=cfg.mt5_password.get_secret_value(),
            server=cfg.mt5_server,
            path=cfg.mt5_path or None,
            instrument=symbol,
        ) as adapter:
            df = adapter.fetch(instrument=symbol, timeframe=tf_enum, start=start, end=end)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"MT5 fetch failed: {exc}") from exc

    if len(df) == 0:
        raise HTTPException(status_code=503, detail="MT5 returned empty data.")

    return df.tail(limit)


@app.get("/api/candles")
def get_candles(
    symbol: str = Query(default="XAUUSD"),
    tf:     str = Query(default="H1"),
    limit:  int = Query(default=200, ge=10, le=1000),
) -> JSONResponse:
    """Return recent OHLCV bars as Lightweight-Charts-compatible JSON.

    Response shape::

        {"symbol": "XAUUSD", "timeframe": "H1",
         "candles": [{"time": <unix_s>, "open": …, "high": …, "low": …, "close": …}, …]}
    """
    df = _fetch_bars(symbol, tf, limit)
    candles = []
    for row in df.iter_rows(named=True):
        ts = row["ts"]
        t  = int(ts.timestamp()) if isinstance(ts, datetime) else int(ts)
        candles.append({
            "time":  t,
            "open":  round(float(row["open"]),  5),
            "high":  round(float(row["high"]),  5),
            "low":   round(float(row["low"]),   5),
            "close": round(float(row["close"]), 5),
        })
    return JSONResponse({"symbol": symbol, "timeframe": tf, "candles": candles})


@app.get("/api/smc")
def get_smc(
    symbol: str = Query(default="XAUUSD"),
    tf:     str = Query(default="H1"),
    limit:  int = Query(default=300, ge=50, le=2000),
) -> JSONResponse:
    """Return OHLCV bars + all SMC signals for chart.html.

    Runs SMCDetector on freshly-fetched MT5 bars and returns:
    candles, order_blocks, fvgs, structure_breaks, liquidity_levels, swing_points.

    Response shape::

        {"symbol": …, "timeframe": …, "generated_at": …,
         "candles": […], "order_blocks": […], "fvgs": […],
         "structure_breaks": […], "liquidity_levels": […], "swing_points": […]}
    """
    from smc.monitor.chart_feeds import TF_MAP, serialize_smc, swing_length_for
    from smc.smc_core.detector import SMCDetector

    df      = _fetch_bars(symbol, tf, limit)
    tf_enum = TF_MAP[tf]

    try:
        detector = SMCDetector(swing_length=swing_length_for(tf))
        snapshot = detector.detect(df, tf_enum)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"SMC detection failed: {exc}") from exc

    payload = serialize_smc(snapshot, df)
    payload["symbol"]       = symbol
    payload["timeframe"]    = tf
    payload["generated_at"] = datetime.now(timezone.utc).isoformat()
    return JSONResponse(payload)
```

- [ ] **Step 2.3: 手动验证端点存在（mock 模式下）**

```bash
# 启动服务（SMC_MT5_MOCK=1 默认）
python scripts/dashboard_server.py &

# 预期 503（mock 模式无 MT5）
curl -s http://localhost:8765/api/candles?symbol=XAUUSD^&tf=H1 | python -m json.tool
# → {"detail": "MT5 not connected: SMC_MT5_MOCK=1..."}

curl -s http://localhost:8765/api/smc?symbol=XAUUSD^&tf=H1 | python -m json.tool
# → {"detail": "MT5 not connected: SMC_MT5_MOCK=1..."}
```

Windows VPS（`SMC_MT5_MOCK=0`）下预期 200 + JSON。

- [ ] **Step 2.4: Commit**

```bash
git add scripts/dashboard_server.py
git commit -m "feat(chart): add /api/candles and /api/smc endpoints to dashboard_server"
```

---

## Task 3: `dashboard/chart.html` — 完整 SMC 图表页面

**Files:**
- Create: `dashboard/chart.html`

- [ ] **Step 3.1: 创建完整页面**

```html
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>AI-SMC · SMC 图表</title>
<script src="https://cdn.tailwindcss.com"></script>
<script src="https://unpkg.com/lightweight-charts@4.2.0/dist/lightweight-charts.standalone.production.js"></script>
<style>
  *, *::before, *::after { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0; height: 100%;
    background: #0F172A; color: #F1F5F9;
    font-family: ui-sans-serif, system-ui, -apple-system, "PingFang SC", sans-serif;
  }
  #chart-wrap { position: relative; width: 100%; height: calc(100vh - 52px); }
  #lw-chart   { width: 100%; height: 100%; }
  #overlay    {
    position: absolute; inset: 0;
    pointer-events: none; z-index: 10;
  }
  #legend {
    position: absolute; top: 8px; left: 8px; z-index: 20;
    pointer-events: none;
  }
  .tf-btn {
    background: transparent; color: #94A3B8;
    border: 1px solid rgba(148,163,184,0.25);
    border-radius: 5px; padding: 3px 10px; font-size: 12px; cursor: pointer;
    transition: background 0.12s, color 0.12s, border-color 0.12s;
  }
  .tf-btn.active { background: #3B82F6; color: #fff; border-color: #3B82F6; }
  .tog-label {
    display: flex; align-items: center; gap: 4px;
    font-size: 12px; cursor: pointer; user-select: none;
  }
  input[type=checkbox] { accent-color: currentColor; }
</style>
</head>
<body>

<!-- ── Toolbar ──────────────────────────────────────────────────────────── -->
<nav style="height:52px;background:#1E293B;border-bottom:1px solid rgba(148,163,184,0.12);
            display:flex;align-items:center;gap:10px;padding:0 14px;flex-shrink:0;">

  <a href="/" style="font-size:12px;color:#94A3B8;text-decoration:none;white-space:nowrap;">← 监控</a>
  <span style="font-size:15px;font-weight:600;white-space:nowrap;">SMC 图表</span>

  <!-- Symbol -->
  <select id="sel-sym"
    style="background:#0F172A;color:#F1F5F9;border:1px solid rgba(148,163,184,0.2);
           border-radius:6px;padding:3px 8px;font-size:12px;">
    <option value="XAUUSD">XAUUSD</option>
    <option value="BTCUSD">BTCUSD</option>
  </select>

  <!-- Timeframes -->
  <div style="display:flex;gap:4px;">
    <button class="tf-btn" data-tf="M15">M15</button>
    <button class="tf-btn active" data-tf="H1">H1</button>
    <button class="tf-btn" data-tf="H4">H4</button>
    <button class="tf-btn" data-tf="D1">D1</button>
  </div>

  <!-- Signal toggles -->
  <label class="tog-label">
    <input type="checkbox" id="tog-ob"     checked style="accent-color:#10B981;">
    <span style="color:#10B981;">OB</span>
  </label>
  <label class="tog-label">
    <input type="checkbox" id="tog-fvg"    checked style="accent-color:#06B6D4;">
    <span style="color:#06B6D4;">FVG</span>
  </label>
  <label class="tog-label">
    <input type="checkbox" id="tog-struct" checked style="accent-color:#818CF8;">
    <span style="color:#818CF8;">BOS/CHoCH</span>
  </label>
  <label class="tog-label">
    <input type="checkbox" id="tog-liq"    checked style="accent-color:#F59E0B;">
    <span style="color:#F59E0B;">EQH/EQL</span>
  </label>

  <div style="flex:1;"></div>

  <span id="status" style="font-size:11px;color:#64748B;white-space:nowrap;"></span>
  <button onclick="loadData()"
    style="background:#3B82F6;color:#fff;border:none;border-radius:6px;
           padding:5px 14px;font-size:13px;cursor:pointer;">
    刷新
  </button>
</nav>

<!-- ── Chart area ───────────────────────────────────────────────────────── -->
<div id="chart-wrap">
  <div id="lw-chart"></div>
  <canvas id="overlay"></canvas>
  <div id="legend"></div>
</div>

<script>
'use strict';

// ─── App state ────────────────────────────────────────────────────────────
const S = {
  symbol:    'XAUUSD',
  tf:        'H1',
  data:      null,   // last /api/smc response
  chart:     null,
  series:    null,
};

// ─── Limits per timeframe ─────────────────────────────────────────────────
const TF_LIMITS = { M15: 500, H1: 400, H4: 300, D1: 250 };

// ─── Colors ───────────────────────────────────────────────────────────────
const C = {
  obBull:    { fill: 'rgba(16,185,129,0.13)',  stroke: '#10B981' },
  obBear:    { fill: 'rgba(239,68,68,0.13)',   stroke: '#EF4444' },
  fvgBull:   { fill: 'rgba(6,182,212,0.13)',   stroke: '#06B6D4' },
  fvgBear:   { fill: 'rgba(251,146,60,0.13)',  stroke: '#FB923C' },
  bos:       '#60A5FA',
  choch:     '#818CF8',
  liq:       '#F59E0B',
  swingText: '#F59E0B',
};

// ─── Chart init ───────────────────────────────────────────────────────────
const chartEl   = document.getElementById('lw-chart');
const overlayEl = document.getElementById('overlay');
const wrapEl    = document.getElementById('chart-wrap');

const chart = LightweightCharts.createChart(chartEl, {
  width:  wrapEl.clientWidth,
  height: wrapEl.clientHeight,
  layout: {
    background: { type: 'solid', color: '#0F172A' },
    textColor:  '#94A3B8',
  },
  grid: {
    vertLines: { color: 'rgba(148,163,184,0.07)' },
    horzLines: { color: 'rgba(148,163,184,0.07)' },
  },
  crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
  rightPriceScale: { borderColor: 'rgba(148,163,184,0.2)' },
  timeScale: {
    borderColor:    'rgba(148,163,184,0.2)',
    timeVisible:    true,
    secondsVisible: false,
  },
});
S.chart = chart;

const series = chart.addCandlestickSeries({
  upColor:        '#10B981', downColor:        '#EF4444',
  borderUpColor:  '#10B981', borderDownColor:  '#EF4444',
  wickUpColor:    '#10B981', wickDownColor:    '#EF4444',
});
S.series = series;

// ─── Resize ───────────────────────────────────────────────────────────────
new ResizeObserver(() => {
  chart.resize(wrapEl.clientWidth, wrapEl.clientHeight);
  redraw();
}).observe(wrapEl);

chart.timeScale().subscribeVisibleTimeRangeChange(redraw);

// ─── Toolbar wiring ───────────────────────────────────────────────────────
document.getElementById('sel-sym').addEventListener('change', e => {
  S.symbol = e.target.value;
  loadData();
});

document.querySelectorAll('.tf-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tf-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    S.tf = btn.dataset.tf;
    loadData();
  });
});

['tog-ob', 'tog-fvg', 'tog-struct', 'tog-liq'].forEach(id => {
  document.getElementById(id).addEventListener('change', redraw);
});

// ─── Data loading ─────────────────────────────────────────────────────────
async function loadData() {
  setStatus('加载中…', '#64748B');
  try {
    const limit = TF_LIMITS[S.tf] || 300;
    const url   = `/api/smc?symbol=${S.symbol}&tf=${S.tf}&limit=${limit}`;
    const resp  = await fetch(url);
    if (!resp.ok) {
      const err = await resp.json().catch(() => ({ detail: resp.statusText }));
      setStatus(`错误: ${err.detail || resp.statusText}`, '#EF4444');
      return;
    }
    S.data = await resp.json();
    renderCandles();
    redraw();
    updateLegend();
    setStatus(`更新于 ${new Date().toLocaleTimeString('zh-CN')}`, '#94A3B8');
  } catch (e) {
    setStatus(`连接失败: ${e.message}`, '#EF4444');
  }
}

function setStatus(msg, color) {
  const el = document.getElementById('status');
  el.textContent  = msg;
  el.style.color  = color;
}

// ─── Render candles + swing markers ──────────────────────────────────────
function renderCandles() {
  if (!S.data) return;
  series.setData(S.data.candles);

  const markers = (S.data.swing_points || []).map(sp => ({
    time:     sp.ts,
    position: sp.swing_type === 'high' ? 'aboveBar' : 'belowBar',
    color:    C.swingText,
    shape:    sp.swing_type === 'high' ? 'arrowDown' : 'arrowUp',
    text:     sp.swing_type === 'high' ? 'SH' : 'SL',
    size:     1,
  }));
  series.setMarkers(markers);
  chart.timeScale().fitContent();
}

// ─── Canvas overlay ───────────────────────────────────────────────────────
function redraw() {
  if (!S.data) return;

  overlayEl.width  = wrapEl.clientWidth;
  overlayEl.height = wrapEl.clientHeight;
  const ctx = overlayEl.getContext('2d');
  ctx.clearRect(0, 0, overlayEl.width, overlayEl.height);

  const showOB     = document.getElementById('tog-ob').checked;
  const showFVG    = document.getElementById('tog-fvg').checked;
  const showStruct = document.getElementById('tog-struct').checked;
  const showLiq    = document.getElementById('tog-liq').checked;

  // px helpers
  const tx = t  => chart.timeScale().timeToCoordinate(t);
  const py = p  => series.priceToCoordinate(p);
  // right edge = chart width minus the right price-scale (~65 px)
  const RIGHT = wrapEl.clientWidth - 68;

  // last candle's unix time (right-extend unmitigated zones to here)
  const candles = S.data.candles || [];
  const lastT   = candles.length ? candles[candles.length - 1].time : null;

  ctx.textBaseline = 'top';

  // ── Order Blocks ─────────────────────────────────────────────────
  if (showOB) {
    for (const ob of (S.data.order_blocks || [])) {
      if (ob.mitigated) continue;
      const x1 = tx(ob.ts_start);
      const x2 = lastT ? RIGHT : tx(ob.ts_end);
      const y1 = py(ob.high);
      const y2 = py(ob.low);
      if (x1 == null || y1 == null || y2 == null) continue;

      const col    = ob.ob_type === 'bullish' ? C.obBull : C.obBear;
      const xL     = Math.min(x1, x2 ?? RIGHT);
      const w      = Math.max(2, (x2 ?? RIGHT) - xL);
      const yT     = Math.min(y1, y2);
      const h      = Math.max(2, Math.abs(y1 - y2));

      ctx.fillStyle   = col.fill;
      ctx.fillRect(xL, yT, w, h);
      ctx.strokeStyle = col.stroke;
      ctx.lineWidth   = 1;
      ctx.setLineDash([]);
      ctx.strokeRect(xL, yT, w, h);

      ctx.fillStyle = col.stroke;
      ctx.font      = '10px ui-monospace, monospace';
      ctx.fillText(ob.ob_type === 'bullish' ? 'OB ▲' : 'OB ▼', xL + 3, yT + 3);
    }
  }

  // ── FVGs ─────────────────────────────────────────────────────────
  if (showFVG) {
    for (const fvg of (S.data.fvgs || [])) {
      if (fvg.fully_filled) continue;
      const x1 = tx(fvg.ts);
      const y1 = py(fvg.high);
      const y2 = py(fvg.low);
      if (x1 == null || y1 == null || y2 == null) continue;

      const col = fvg.fvg_type === 'bullish' ? C.fvgBull : C.fvgBear;
      const yT  = Math.min(y1, y2);
      const h   = Math.max(2, Math.abs(y1 - y2));
      const w   = Math.max(2, RIGHT - x1);

      ctx.fillStyle   = col.fill;
      ctx.fillRect(x1, yT, w, h);
      ctx.strokeStyle = col.stroke;
      ctx.lineWidth   = 1;
      ctx.setLineDash([4, 3]);
      ctx.strokeRect(x1, yT, w, h);
      ctx.setLineDash([]);

      const pct = Math.round(fvg.filled_pct * 100);
      ctx.fillStyle = col.stroke;
      ctx.font      = '10px ui-monospace, monospace';
      ctx.fillText(`FVG ${pct}%`, x1 + 3, yT + 3);
    }
  }

  // ── BOS / CHoCH ──────────────────────────────────────────────────
  if (showStruct) {
    for (const sb of (S.data.structure_breaks || [])) {
      const x = tx(sb.ts);
      const y = py(sb.price);
      if (x == null || y == null) continue;

      const isChoch = sb.break_type === 'choch';
      const color   = isChoch ? C.choch : C.bos;
      const arrow   = sb.direction === 'bullish' ? '↑' : '↓';
      const label   = `${sb.break_type.toUpperCase()} ${arrow}`;

      ctx.strokeStyle = color;
      ctx.lineWidth   = isChoch ? 1.5 : 1;
      ctx.setLineDash(isChoch ? [] : [6, 3]);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(RIGHT, y);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = color;
      ctx.font      = `${isChoch ? 'bold ' : ''}10px ui-monospace, monospace`;
      const lw = ctx.measureText(label).width;
      ctx.fillText(label, RIGHT - lw - 4, y - 12);
    }
  }

  // ── EQH / EQL ────────────────────────────────────────────────────
  if (showLiq) {
    for (const lv of (S.data.liquidity_levels || [])) {
      if (lv.swept) continue;
      const y = py(lv.price);
      if (y == null) continue;

      const isHigh = lv.level_type === 'equal_highs';
      ctx.strokeStyle = C.liq;
      ctx.lineWidth   = 1;
      ctx.setLineDash([2, 5]);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(RIGHT, y);
      ctx.stroke();
      ctx.setLineDash([]);

      const label = `${isHigh ? 'EQH' : 'EQL'} ×${lv.touches}`;
      ctx.fillStyle = C.liq;
      ctx.font      = '10px ui-monospace, monospace';
      ctx.fillText(label, 4, y - 12);
    }
  }
}

// ─── Legend counts ────────────────────────────────────────────────────────
function updateLegend() {
  if (!S.data) return;
  const d = S.data;
  const activeOB    = (d.order_blocks     || []).filter(x => !x.mitigated).length;
  const activeFVG   = (d.fvgs             || []).filter(x => !x.fully_filled).length;
  const bosCount    = (d.structure_breaks || []).filter(x => x.break_type === 'bos').length;
  const chochCount  = (d.structure_breaks || []).filter(x => x.break_type === 'choch').length;
  const liqCount    = (d.liquidity_levels || []).filter(x => !x.swept).length;
  const swingCount  = (d.swing_points     || []).length;

  document.getElementById('legend').innerHTML = `
    <div style="
      display:flex;gap:10px;font-size:11px;font-family:ui-monospace,monospace;
      background:rgba(15,23,42,0.75);padding:5px 10px;
      border-radius:5px;border:1px solid rgba(148,163,184,0.1);backdrop-filter:blur(4px);">
      <span style="color:#10B981;">OB ${activeOB}</span>
      <span style="color:#06B6D4;">FVG ${activeFVG}</span>
      <span style="color:#60A5FA;">BOS ${bosCount}</span>
      <span style="color:#818CF8;">CHoCH ${chochCount}</span>
      <span style="color:#F59E0B;">LIQ ${liqCount}</span>
      <span style="color:#F59E0B;">SW ${swingCount}</span>
    </div>`;
}

// ─── Bootstrap ────────────────────────────────────────────────────────────
loadData();
</script>

</body>
</html>
```

- [ ] **Step 3.2: 添加到 dashboard_server 的静态文件路由**

在 `scripts/dashboard_server.py` 中，在现有 `@app.get("/")` 路由**下方**追加：

```python
@app.get("/chart")
def chart_page() -> FileResponse:
    """Serve the standalone SMC chart page."""
    path = ROOT / "dashboard" / "chart.html"
    if not path.exists():
        raise HTTPException(status_code=404, detail="dashboard/chart.html not found")
    return FileResponse(path, media_type="text/html")
```

- [ ] **Step 3.3: 在 `dashboard/index.html` 中加入跳转入口**

在现有 `index.html` 的 Tab 切换区域找到：
```html
<button @click="tab = 'settings'"
```

在这一行**前面**插入一个外部链接按钮：

```html
      <a href="/chart" target="_blank"
        class="px-4 py-1.5 text-sm rounded-md transition text-muted hover:text-text"
        style="text-decoration:none;">📊 图表</a>
```

- [ ] **Step 3.4: 浏览器验证**

```bash
# 启动 dashboard server
python scripts/dashboard_server.py

# 打开页面
start http://localhost:8765/chart
```

在 mock 模式下，页面应显示"错误: MT5 not connected: SMC_MT5_MOCK=1..."。  
在 Windows VPS（MT5 运行，`SMC_MT5_MOCK=0`）下，应显示 K 线图 + SMC 叠加层。

验证清单：
- [ ] K 线图正常渲染，颜色为绿涨/红跌
- [ ] Swing High/Low 标记（橙色箭头）出现在对应 K 线上
- [ ] Bullish OB = 绿色半透明矩形，Bearish OB = 红色
- [ ] FVG 矩形带百分比标签
- [ ] BOS 蓝色虚线，CHoCH 紫色实线
- [ ] EQH/EQL 黄色点线
- [ ] 时间框架切换（M15/H1/H4/D1）正常重新加载
- [ ] 信号 toggle checkbox 即时显示/隐藏各层
- [ ] 图例计数准确
- [ ] 窗口缩放时叠加层正确跟随

- [ ] **Step 3.5: Commit**

```bash
git add dashboard/chart.html scripts/dashboard_server.py dashboard/index.html
git commit -m "feat(chart): add SMC web chart page with OB/FVG/BOS/EQH overlays"
```

---

## 自查

### Spec 覆盖

| 需求 | Task |
|------|------|
| MT5 实时 K 线数据 | Task 2 `_fetch_bars` |
| 独立新页面 `/chart` | Task 3 `chart.html` + Task 3.2 路由 |
| Order Block（OB） | Task 3 `redraw()` OB 段 |
| FVG 失衡区 | Task 3 `redraw()` FVG 段 |
| BOS / CHoCH 结构 | Task 3 `redraw()` struct 段 |
| EQH / EQL 流动性 | Task 3 `redraw()` liq 段 |
| Swing High/Low 标记 | Task 3 `renderCandles()` setMarkers |
| 时间框架切换 | Task 3 toolbar tf-btn |
| 信号 toggle | Task 3 checkbox + `redraw()` |
| Mock 模式优雅降级 | Task 2 `_fetch_bars` 503 |

### Placeholder 扫描

无 TBD / TODO / "similar to" / "implement later"。所有代码完整。

### 类型一致性

| 名称 | 定义 | 使用 |
|------|------|------|
| `serialize_smc(snapshot, bars)` | Task 1 Step 1.3 | Task 2 Step 2.2 endpoint |
| `TF_MAP` | Task 1 Step 1.3 | Task 2 Step 2.2 `_fetch_bars` |
| `tf_bar_duration` | Task 1 Step 1.3 | Task 2 Step 2.2 `_fetch_bars` |
| `swing_length_for(tf_str)` | Task 1 Step 1.3 | Task 2 Step 2.2 `/api/smc` |
| `_fetch_bars(symbol, tf_str, limit)` | Task 2 Step 2.2 | Task 2 Step 2.2 endpoints |
| JS `S.data.order_blocks[i].ts_start` | Task 1 serialize 输出 | Task 3 `redraw()` OB 段 |
| JS `S.data.fvgs[i].filled_pct` | Task 1 serialize 输出 | Task 3 `redraw()` FVG 段 |
