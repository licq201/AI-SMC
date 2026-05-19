# SMC Orderflow Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dashboard-friendly SMC orderflow summary that shows structure, zones, liquidity, entry, risk, learning timeline, and key levels in Chinese without changing trading behavior.

**Architecture:** Build a pure summary module under `src/smc/strategy/` that converts existing live diagnostics into a stable `smc_orderflow` dictionary. Wire that dictionary into `scripts/live_demo.py::save_state`, then upgrade `dashboard/index.html` to render a radar card with fallback to existing `smc_trace`.

**Tech Stack:** Python 3.11, existing `smc` dataclasses/Pydantic models, pytest, FastAPI dashboard server, single-file Alpine.js/Tailwind dashboard.

---

## File Structure

- Create `src/smc/strategy/smc_orderflow.py`
  - Responsible for building a stable, serializable SMC orderflow summary from existing diagnostics.
  - Must be pure Python with no MT5, filesystem, network, or heavy AI calls.
- Create `tests/smc/unit/strategy/test_smc_orderflow.py`
  - Unit tests for readiness, radar statuses, timeline text, key-level extraction, and missing-data behavior.
- Modify `scripts/live_demo.py`
  - Call `build_smc_orderflow()` inside `save_state()` after `smc_trace` is built.
  - Must not change action selection, order sending, risk gates, or EA payload semantics.
- Modify `tests/smc/unit/monitor/test_live_state_status.py`
  - Assert `save_state()`/live-state helper path includes `smc_orderflow` when diagnostics exist, or add a focused test if the current helper shape is easier.
- Modify `dashboard/index.html`
  - Replace or augment the existing “SMC 阶段追踪” card with “SMC 订单流雷达”.
  - Add computed helpers for status colors, readiness label, key-level formatting, and fallback behavior.
- Modify `tests/dashboard/`
  - Add or update dashboard fixture/test to verify frontend-visible data fields remain compatible.
- Modify `docs/用户操作手册.md`
  - Add a short section explaining how to read “SMC 订单流雷达”.

---

## Task 1: Build Pure SMC Orderflow Summary

**Files:**
- Create: `src/smc/strategy/smc_orderflow.py`
- Test: `tests/smc/unit/strategy/test_smc_orderflow.py`

- [ ] **Step 1: Write failing tests for the orderflow summary**

Create `tests/smc/unit/strategy/test_smc_orderflow.py` with:

```python
from __future__ import annotations

from smc.strategy.smc_orderflow import build_smc_orderflow


def test_orderflow_waits_on_m15_entry_when_zones_exist() -> None:
    orderflow = build_smc_orderflow(
        smc_trace={
            "current_stage": "m15_entry",
            "decision": {"action": "HOLD", "reason": "No trade setup", "setup_count": 0},
        },
        smc_diagnostic={
            "htf_bias_direction": "bullish",
            "htf_bias_confidence": 0.72,
            "htf_bias_rationale": "Tier 1: D1 and H4 both bullish.",
            "h1_zones_count": 2,
            "zone_rejects": {"entry_none": 2, "confluence_low": 0, "trigger_filter": 0},
            "zone_details": [
                {"high": 2355.0, "low": 2351.0, "direction": "long", "dist_from_price": 4.2, "in_expanded_zone": True},
                {"high": 2348.0, "low": 2344.0, "direction": "long", "dist_from_price": 9.0, "in_expanded_zone": False},
            ],
            "current_price": 2350.8,
            "min_confluence": 0.6,
        },
        range_diagnostic={},
        best_setup=None,
        current_price=2350.8,
    )

    assert orderflow["summary"]["bias"] == "bullish"
    assert orderflow["summary"]["readiness"] == "waiting"
    assert "M15" in orderflow["summary"]["headline"]
    assert orderflow["radar"][0]["key"] == "structure"
    assert orderflow["radar"][0]["status"] == "passed"
    assert orderflow["radar"][1]["key"] == "zone"
    assert orderflow["radar"][1]["status"] == "passed"
    assert orderflow["radar"][3]["key"] == "entry"
    assert orderflow["radar"][3]["status"] == "waiting"
    assert any(level["kind"] == "current_price" for level in orderflow["key_levels"])
    assert any(level["kind"] == "zone" for level in orderflow["key_levels"])


def test_orderflow_blocks_when_h1_zones_missing() -> None:
    orderflow = build_smc_orderflow(
        smc_trace={
            "current_stage": "h1_zone",
            "decision": {"action": "HOLD", "reason": "No H1 zones", "setup_count": 0},
        },
        smc_diagnostic={
            "htf_bias_direction": "bearish",
            "htf_bias_confidence": 0.63,
            "htf_bias_rationale": "Tier 2: H4 bearish confirms.",
            "stage_reject": "no_h1_zones",
            "current_price": 2362.1,
        },
        range_diagnostic={},
        best_setup=None,
        current_price=2362.1,
    )

    zone = next(item for item in orderflow["radar"] if item["key"] == "zone")
    entry = next(item for item in orderflow["radar"] if item["key"] == "entry")

    assert orderflow["summary"]["readiness"] == "blocked"
    assert zone["status"] == "blocked"
    assert "没有找到" in zone["detail"]
    assert entry["status"] == "skipped"


def test_orderflow_ready_when_best_setup_exists() -> None:
    orderflow = build_smc_orderflow(
        smc_trace={
            "current_stage": "decision",
            "decision": {"action": "BUY", "reason": "V1 setup accepted", "setup_count": 1},
        },
        smc_diagnostic={
            "htf_bias_direction": "bullish",
            "htf_bias_confidence": 0.81,
            "h1_zones_count": 1,
            "zone_rejects": {},
            "current_price": 2354.0,
            "min_confluence": 0.6,
        },
        range_diagnostic={},
        best_setup={
            "direction": "long",
            "entry": 2354.0,
            "sl": 2348.0,
            "tp1": 2366.0,
            "trigger": "fvg_fill_in_zone",
            "confluence": 0.74,
            "exec_rr_ratio": 2.0,
        },
        current_price=2354.0,
    )

    risk = next(item for item in orderflow["radar"] if item["key"] == "risk")

    assert orderflow["summary"]["readiness"] == "ready"
    assert "可交易候选" in orderflow["summary"]["headline"]
    assert risk["status"] == "passed"
    assert "2.00" in risk["detail"]
    assert any(level["kind"] == "entry" for level in orderflow["key_levels"])


def test_orderflow_unknown_when_inputs_missing() -> None:
    orderflow = build_smc_orderflow(
        smc_trace=None,
        smc_diagnostic=None,
        range_diagnostic=None,
        best_setup=None,
        current_price=None,
    )

    assert orderflow["summary"]["readiness"] == "unknown"
    assert orderflow["radar"]
    assert all(item["status"] == "unknown" for item in orderflow["radar"])
    assert orderflow["timeline"]
    assert orderflow["key_levels"] == []
```

- [ ] **Step 2: Run tests and verify they fail because module is missing**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/smc/unit/strategy/test_smc_orderflow.py -q
```

Expected: FAIL with `ModuleNotFoundError: No module named 'smc.strategy.smc_orderflow'`.

- [ ] **Step 3: Implement `build_smc_orderflow()`**

Create `src/smc/strategy/smc_orderflow.py`:

```python
"""Dashboard-friendly SMC orderflow summary.

This module converts existing live diagnostics into a stable, compact shape
for dashboard display. It must not perform trading decisions, I/O, MT5 calls,
network requests, or AI calls.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

__all__ = ["build_smc_orderflow"]

_RADAR_KEYS = (
    ("structure", "结构"),
    ("zone", "交易区"),
    ("liquidity", "流动性"),
    ("entry", "入场"),
    ("risk", "风险"),
)


def _num(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _status_item(key: str, label: str, status: str, title: str, detail: str) -> dict[str, str]:
    return {"key": key, "label": label, "status": status, "title": title, "detail": detail}


def _bias_label(bias: str | None) -> str:
    return {"bullish": "偏多", "bearish": "偏空", "neutral": "中性"}.get(str(bias or ""), "未知")


def _direction_label(direction: str | None) -> str:
    return {"long": "多头", "short": "空头", "buy": "多头", "sell": "空头"}.get(str(direction or "").lower(), "未知方向")


def _trigger_label(trigger: str | None) -> str:
    mapping = {
        "choch_in_zone": "CHoCH 入场",
        "fvg_fill_in_zone": "FVG 回补",
        "ob_test_rejection": "订单块回踩",
        "bos_in_zone": "BOS 入场",
        "fvg_sweep_continuation": "FVG 扫流动性延续",
    }
    return mapping.get(str(trigger or ""), str(trigger or "未知触发"))


def _build_unknown() -> dict[str, Any]:
    return {
        "summary": {
            "bias": "unknown",
            "readiness": "unknown",
            "headline": "暂无本周期 SMC 订单流摘要。",
            "blocking_reason": "等待下一轮行情分析写入数据",
        },
        "radar": [
            _status_item(key, label, "unknown", "暂无数据", "本周期尚未生成该层 SMC 摘要。")
            for key, label in _RADAR_KEYS
        ],
        "timeline": [
            {
                "timeframe": "D1/H4",
                "label": "大周期结构",
                "status": "unknown",
                "explanation": "等待 D1/H4 结构检测结果。",
            },
            {
                "timeframe": "H1",
                "label": "交易区",
                "status": "unknown",
                "explanation": "等待 H1 订单块/FVG 交易区检测结果。",
            },
            {
                "timeframe": "M15",
                "label": "入场触发",
                "status": "unknown",
                "explanation": "等待 M15 入场确认结果。",
            },
        ],
        "key_levels": [],
        "debug": {"source": "smc_orderflow", "generated_at": datetime.now(timezone.utc).isoformat()},
    }


def _zone_levels(zone_details: list[dict[str, Any]]) -> list[dict[str, Any]]:
    levels: list[dict[str, Any]] = []
    for zone in zone_details[:6]:
        high = zone.get("high")
        low = zone.get("low")
        if high is None or low is None:
            continue
        direction = str(zone.get("direction") or "")
        levels.append({
            "kind": "zone",
            "label": "H1 " + _direction_label(direction) + "交易区",
            "low": _num(low),
            "high": _num(high),
            "side": "below" if direction == "long" else "above" if direction == "short" else "unknown",
            "detail": "距当前价 " + str(zone.get("dist_from_price", "未知")) + "，"
            + ("价格已接近扩展区" if zone.get("in_expanded_zone") else "价格尚未接近"),
        })
    return levels


def build_smc_orderflow(
    *,
    smc_trace: dict[str, Any] | None,
    smc_diagnostic: dict[str, Any] | None,
    range_diagnostic: dict[str, Any] | None,
    best_setup: dict[str, Any] | None,
    current_price: float | None,
) -> dict[str, Any]:
    """Build a stable SMC orderflow summary for dashboard rendering."""
    if not smc_trace and not smc_diagnostic and not best_setup and current_price is None:
        return _build_unknown()

    smc = dict(smc_diagnostic or {})
    trace = dict(smc_trace or {})
    best = dict(best_setup or {})
    range_diag = dict(range_diagnostic or {})

    bias = str(smc.get("htf_bias_direction") or "unknown")
    bias_readable = _bias_label(bias)
    stage_reject = str(smc.get("stage_reject") or "")
    setup_count = int((trace.get("decision") or {}).get("setup_count") or smc.get("final_count") or 0)
    zone_count = int(smc.get("h1_zones_count") or 0)
    zone_rejects = dict(smc.get("zone_rejects") or {})
    zone_details = list(smc.get("zone_details") or [])

    has_best_setup = bool(best)
    if has_best_setup:
        readiness = "ready"
        headline = "SMC 已形成可交易候选：" + _direction_label(best.get("direction")) + "，触发为 " + _trigger_label(best.get("trigger")) + "。"
        blocking_reason = ""
    elif stage_reject in {"htf_bias_neutral", "legacy_ranging_gate", "no_h1_zones"}:
        readiness = "blocked"
        headline = "SMC 条件被阻断：" + ("大周期方向不清晰。" if stage_reject != "no_h1_zones" else "H1 没有可用交易区。")
        blocking_reason = stage_reject
    else:
        readiness = "waiting"
        headline = "大周期" + bias_readable + "，" + ("H1 有候选交易区，" if zone_count else "等待 H1 交易区，") + "等待 M15 入场确认。"
        blocking_reason = "等待 M15 CHoCH / BOS / FVG 回补确认"

    htf_conf = _num(smc.get("htf_bias_confidence"))
    structure_status = "blocked" if stage_reject in {"htf_bias_neutral", "legacy_ranging_gate"} else "passed" if bias in {"bullish", "bearish"} else "unknown"
    zone_status = "blocked" if stage_reject == "no_h1_zones" else "passed" if zone_count > 0 else "waiting"
    entry_none = int(zone_rejects.get("entry_none") or 0)
    conf_low = int(zone_rejects.get("confluence_low") or 0)
    trigger_filter = int(zone_rejects.get("trigger_filter") or 0)
    entry_status = "passed" if has_best_setup or setup_count > 0 else "skipped" if zone_status == "blocked" else "waiting"
    risk_status = "passed" if has_best_setup else "waiting" if readiness == "waiting" else "skipped"

    liquidity_detail = "暂未检测到明确扫流动性摘要。"
    detect = dict(range_diag.get("detect") or {})
    if detect:
        source = detect.get("final_source") or detect.get("source") or detect.get("method")
        liquidity_detail = "区间/流动性来源：" + str(source or "暂无明确来源") + "。"

    radar = [
        _status_item(
            "structure",
            "结构",
            structure_status,
            "大周期" + bias_readable,
            (smc.get("htf_bias_rationale") or "等待 D1/H4 BOS/CHoCH 结构确认。"),
        ),
        _status_item(
            "zone",
            "交易区",
            zone_status,
            ("找到 " + str(zone_count) + " 个 H1 候选区") if zone_count else "暂无 H1 交易区",
            "优先关注与大周期方向一致的订单块/FVG。" if zone_count else "没有找到与大周期方向一致的 H1 订单块或 FVG。",
        ),
        _status_item("liquidity", "流动性", "waiting", "观察流动性位置", liquidity_detail),
        _status_item(
            "entry",
            "入场",
            entry_status,
            "M15 入场确认" if entry_status == "passed" else "等待 M15 入场",
            "无触发 " + str(entry_none) + "，共振不足 " + str(conf_low) + "，触发器不匹配 " + str(trigger_filter) + "。",
        ),
        _status_item(
            "risk",
            "风险",
            risk_status,
            "风险条件通过" if has_best_setup else "等待风险计算",
            ("RR " + f"{_num(best.get('exec_rr_ratio') or best.get('planned_rr_ratio')):.2f}" + "，共振 " + f"{_num(best.get('confluence')):.2f}")
            if has_best_setup
            else "形成候选 setup 后再计算 RR、共振和风控。",
        ),
    ]

    timeline = [
        {
            "timeframe": "D1/H4",
            "label": "大周期结构",
            "status": structure_status,
            "explanation": "D1/H4 当前" + bias_readable + "，置信度 " + f"{htf_conf * 100:.0f}%。",
        },
        {
            "timeframe": "H1",
            "label": "交易区",
            "status": zone_status,
            "explanation": ("H1 找到 " + str(zone_count) + " 个候选交易区。") if zone_count else "H1 暂无可用订单块/FVG 交易区。",
        },
        {
            "timeframe": "M15",
            "label": "入场触发",
            "status": entry_status,
            "explanation": "已形成入场触发。" if entry_status == "passed" else "价格尚未在交易区内形成 M15 反转或延续确认。",
        },
    ]

    key_levels: list[dict[str, Any]] = []
    price = current_price if current_price is not None else smc.get("current_price")
    if price is not None:
        key_levels.append({
            "kind": "current_price",
            "label": "当前价",
            "price": _num(price),
            "side": "current",
            "detail": "本轮分析价格",
        })
    key_levels.extend(_zone_levels(zone_details))
    if has_best_setup:
        key_levels.extend([
            {"kind": "entry", "label": "计划入场", "price": _num(best.get("entry")), "side": "current", "detail": _trigger_label(best.get("trigger"))},
            {"kind": "stop_loss", "label": "止损", "price": _num(best.get("sl")), "side": "risk", "detail": "系统计划止损"},
            {"kind": "take_profit", "label": "止盈", "price": _num(best.get("tp1")), "side": "reward", "detail": "系统计划止盈"},
        ])

    return {
        "summary": {
            "bias": bias,
            "readiness": readiness,
            "headline": headline,
            "blocking_reason": blocking_reason,
        },
        "radar": radar,
        "timeline": timeline,
        "key_levels": key_levels[:8],
        "debug": {"source": "smc_orderflow", "generated_at": datetime.now(timezone.utc).isoformat()},
    }
```

- [ ] **Step 4: Run the new unit tests**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/smc/unit/strategy/test_smc_orderflow.py -q
```

Expected: `4 passed`.

- [ ] **Step 5: Commit Task 1**

Run:

```powershell
git add -- src/smc/strategy/smc_orderflow.py tests/smc/unit/strategy/test_smc_orderflow.py
git commit -m "feat: add SMC orderflow summary"
```

Expected: commit succeeds.

---

## Task 2: Wire Orderflow Into Live State

**Files:**
- Modify: `scripts/live_demo.py`
- Modify or create focused test: `tests/smc/unit/monitor/test_live_state_status.py`

- [ ] **Step 1: Write failing test for `smc_orderflow` in saved state**

Open `tests/smc/unit/monitor/test_live_state_status.py`. Add a focused test near existing `smc_trace` assertions:

```python
def test_live_state_includes_smc_orderflow_summary() -> None:
    from smc.strategy.smc_orderflow import build_smc_orderflow

    state = {
        "price": 2350.8,
        "smc_diagnostic": {
            "htf_bias_direction": "bullish",
            "htf_bias_confidence": 0.72,
            "h1_zones_count": 2,
            "zone_rejects": {"entry_none": 2},
            "current_price": 2350.8,
        },
        "range_diagnostic": {},
        "best_setup": None,
        "smc_trace": {
            "current_stage": "m15_entry",
            "decision": {"action": "HOLD", "reason": "No trade setup", "setup_count": 0},
        },
    }

    state["smc_orderflow"] = build_smc_orderflow(
        smc_trace=state.get("smc_trace"),
        smc_diagnostic=state.get("smc_diagnostic"),
        range_diagnostic=state.get("range_diagnostic"),
        best_setup=state.get("best_setup"),
        current_price=state.get("price"),
    )

    assert state["smc_orderflow"]["summary"]["readiness"] == "waiting"
    assert state["smc_orderflow"]["radar"][0]["label"] == "结构"
```

If the file already has a better helper for `save_state()`, use that helper and assert `state["smc_orderflow"]` directly. Do not require MT5.

- [ ] **Step 2: Run the focused test**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/smc/unit/monitor/test_live_state_status.py -q
```

Expected before wiring: the new helper-only test may pass immediately. If it passes, add a direct assertion to the existing `save_state` test path so failure proves wiring is missing.

- [ ] **Step 3: Wire `build_smc_orderflow()` into `scripts/live_demo.py`**

Add import near the existing `build_smc_trace` import:

```python
from smc.strategy.smc_orderflow import build_smc_orderflow
```

Inside `save_state()`, immediately after:

```python
state["smc_trace"] = build_smc_trace(...)
```

add:

```python
    state["smc_orderflow"] = build_smc_orderflow(
        smc_trace=state.get("smc_trace"),
        smc_diagnostic=state.get("smc_diagnostic"),
        range_diagnostic=state.get("range_diagnostic"),
        best_setup=state.get("best_setup"),
        current_price=state.get("price"),
    )
```

Do not modify the decision code before `save_state()`. Do not change `best_setup` semantics.

- [ ] **Step 4: Run live-state and orderflow tests**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/smc/unit/strategy/test_smc_orderflow.py tests/smc/unit/monitor/test_live_state_status.py -q
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit Task 2**

Run:

```powershell
git add -- scripts/live_demo.py tests/smc/unit/monitor/test_live_state_status.py
git commit -m "feat: expose SMC orderflow in live state"
```

Expected: commit succeeds.

---

## Task 3: Upgrade Dashboard SMC Card

**Files:**
- Modify: `dashboard/index.html`

- [ ] **Step 1: Add frontend fallback data expectations**

In `dashboard/index.html`, keep the existing `smcTrace` getter. Add a new getter:

```javascript
get smcOrderflow() { return this.state?.smc_orderflow || null; },
```

Add helpers:

```javascript
smcOrderflowStatusColor(status) {
  if (status === "passed" || status === "ready") return "#10B981";
  if (status === "blocked") return "#EF4444";
  if (status === "waiting") return "#F59E0B";
  return "#94A3B8";
},
smcOrderflowStatusLabel(status) {
  const map = { passed: "通过", ready: "可交易", blocked: "阻断", waiting: "等待", skipped: "跳过", unknown: "暂无" };
  return map[status] || "暂无";
},
smcReadinessLabel(readiness) {
  const map = { ready: "可交易候选", waiting: "等待确认", blocked: "已阻断", unknown: "暂无数据" };
  return map[readiness] || "暂无数据";
},
formatLevel(level) {
  if (!level) return "—";
  if (level.low !== undefined && level.high !== undefined) return "$" + this.formatNum(level.low) + " - $" + this.formatNum(level.high);
  if (level.price !== undefined) return "$" + this.formatNum(level.price);
  return "—";
},
```

- [ ] **Step 2: Replace the visible SMC card markup**

Replace the card block starting at `<!-- 卡片 3.5: SMC 学习追踪 -->` with a new card that:

```html
<!-- 卡片 3.5: SMC 订单流雷达 -->
<template x-if="smcOrderflow || smcTrace">
  <div class="card p-5 md:p-6 border-l-4" :style="{ borderLeftColor: smcOrderflowStatusColor(smcOrderflow?.summary?.readiness || smcTrace?.current_stage) }">
    <div class="flex items-center justify-between gap-4 mb-4 flex-wrap">
      <div>
        <div class="text-xs uppercase tracking-wider text-muted">SMC 订单流雷达</div>
        <div class="mt-1 text-sm text-muted" x-text="smcOrderflow?.summary?.headline || '按 D1/H4 → H1 → M15 → 环境过滤 → AI 复核展开'"></div>
      </div>
      <span class="px-2 py-1 rounded text-xs font-medium bg-slate-700 text-text"
            x-text="smcReadinessLabel(smcOrderflow?.summary?.readiness || 'unknown')"></span>
    </div>

    <template x-if="smcOrderflow">
      <div>
        <div class="grid grid-cols-1 md:grid-cols-5 gap-3">
          <template x-for="item in smcOrderflow.radar" :key="item.key">
            <div class="p-3 rounded-lg card-hi border-l-4" :style="{ borderLeftColor: smcOrderflowStatusColor(item.status) }">
              <div class="flex items-center justify-between gap-2">
                <div class="text-sm font-medium" x-text="item.label"></div>
                <span class="text-xs" :style="{ color: smcOrderflowStatusColor(item.status) }" x-text="smcOrderflowStatusLabel(item.status)"></span>
              </div>
              <div class="mt-2 text-xs font-medium" x-text="item.title"></div>
              <div class="mt-1 text-xs text-muted leading-relaxed" x-text="item.detail"></div>
            </div>
          </template>
        </div>

        <details class="mt-4">
          <summary class="text-xs text-muted hover:text-text select-none">学习每一层 SMC 判断</summary>
          <div class="mt-3 grid grid-cols-1 md:grid-cols-3 gap-3">
            <template x-for="step in smcOrderflow.timeline" :key="step.timeframe + step.label">
              <div class="p-3 rounded-lg card-hi">
                <div class="flex items-center justify-between">
                  <div class="text-xs num text-muted" x-text="step.timeframe"></div>
                  <span class="text-xs" :style="{ color: smcOrderflowStatusColor(step.status) }" x-text="smcOrderflowStatusLabel(step.status)"></span>
                </div>
                <div class="mt-1 text-sm font-medium" x-text="step.label"></div>
                <div class="mt-2 text-xs text-muted leading-relaxed" x-text="step.explanation"></div>
              </div>
            </template>
          </div>
        </details>

        <details x-show="smcOrderflow.key_levels && smcOrderflow.key_levels.length" class="mt-4">
          <summary class="text-xs text-muted hover:text-text select-none">关键价位地图</summary>
          <div class="mt-3 grid grid-cols-1 md:grid-cols-2 gap-2">
            <template x-for="level in smcOrderflow.key_levels" :key="level.kind + level.label + formatLevel(level)">
              <div class="flex items-center justify-between gap-3 p-3 rounded-lg card-hi">
                <div>
                  <div class="text-sm font-medium" x-text="level.label"></div>
                  <div class="text-xs text-muted mt-0.5" x-text="level.detail"></div>
                </div>
                <div class="num text-sm text-text whitespace-nowrap" x-text="formatLevel(level)"></div>
              </div>
            </template>
          </div>
        </details>
      </div>
    </template>

    <template x-if="!smcOrderflow && smcTrace">
      <div class="grid grid-cols-1 md:grid-cols-5 gap-3">
        <template x-for="stage in smcTrace.stages" :key="stage.name">
          <div class="p-3 rounded-lg card-hi border-l-4" :style="{ borderLeftColor: smcStageColor(stage.status) }">
            <div class="flex items-center justify-between gap-2">
              <div class="text-sm font-medium" x-text="stage.label"></div>
              <span class="text-xs" :style="{ color: smcStageColor(stage.status) }" x-text="smcStatusLabel(stage.status)"></span>
            </div>
            <div class="mt-2 text-xs text-muted leading-relaxed" x-text="stage.explanation"></div>
          </div>
        </template>
      </div>
    </template>
  </div>
</template>
```

- [ ] **Step 3: Parse-check inline scripts**

Run:

```powershell
node -e "const fs=require('fs'); const html=fs.readFileSync('dashboard/index.html','utf8'); const scripts=[...html.matchAll(/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/gi)].map(m=>m[1]); for (const s of scripts) new Function(s); console.log('inline scripts ok:', scripts.length);"
```

Expected: `inline scripts ok: 2`.

- [ ] **Step 4: Commit Task 3**

Run:

```powershell
git add -- dashboard/index.html
git commit -m "feat: render SMC orderflow radar"
```

Expected: commit succeeds.

---

## Task 4: Add Dashboard and Browser Verification

**Files:**
- Modify or add: `tests/dashboard/test_smc_orderflow_rendering.py` if there is a suitable pattern
- Otherwise use existing dashboard tests and add API-shape checks only

- [ ] **Step 1: Inspect existing dashboard test style**

Run:

```powershell
Get-ChildItem tests\dashboard
Get-Content tests\dashboard\test_server_symbol_routing.py -TotalCount 120
```

Use the existing style. Do not introduce a browser test framework if the dashboard tests are server/API focused.

- [ ] **Step 2: Add API/fixture compatibility test**

If a frontend rendering unit test is not practical, create `tests/dashboard/test_smc_orderflow_contract.py`:

```python
from __future__ import annotations


def test_smc_orderflow_contract_has_dashboard_required_fields() -> None:
    payload = {
        "summary": {"bias": "bullish", "readiness": "waiting", "headline": "等待 M15 入场确认。", "blocking_reason": "等待确认"},
        "radar": [
            {"key": "structure", "label": "结构", "status": "passed", "title": "大周期偏多", "detail": "D1/H4 结构偏多。"},
            {"key": "zone", "label": "交易区", "status": "passed", "title": "找到 H1 候选区", "detail": "订单块/FVG 可用。"},
            {"key": "liquidity", "label": "流动性", "status": "waiting", "title": "观察流动性位置", "detail": "等待扫流动性。"},
            {"key": "entry", "label": "入场", "status": "waiting", "title": "等待 M15 入场", "detail": "尚未确认。"},
            {"key": "risk", "label": "风险", "status": "waiting", "title": "等待风险计算", "detail": "形成候选后计算。"},
        ],
        "timeline": [
            {"timeframe": "D1/H4", "label": "大周期结构", "status": "passed", "explanation": "偏多。"}
        ],
        "key_levels": [
            {"kind": "current_price", "label": "当前价", "price": 2350.8, "side": "current", "detail": "本轮分析价格"}
        ],
    }

    assert payload["summary"]["readiness"] in {"ready", "waiting", "blocked", "unknown"}
    assert {item["key"] for item in payload["radar"]} == {"structure", "zone", "liquidity", "entry", "risk"}
    for item in payload["radar"]:
        assert {"key", "label", "status", "title", "detail"} <= set(item)
    assert {"timeframe", "label", "status", "explanation"} <= set(payload["timeline"][0])
    assert {"kind", "label", "side", "detail"} <= set(payload["key_levels"][0])
```

- [ ] **Step 3: Run dashboard tests**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/dashboard -q
```

Expected: all dashboard tests pass.

- [ ] **Step 4: Browser-check local dashboard**

Start dashboard server if not already running:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe scripts\dashboard_server.py
```

Open `http://localhost:8765` in the in-app browser or normal browser.

Verify:

- `SMC 订单流雷达` is visible when `smc_orderflow` exists.
- Existing `SMC 阶段追踪` fallback still appears if `smc_orderflow` is absent.
- `学习每一层 SMC 判断` expands.
- `关键价位地图` expands when key levels exist.
- Browser console has no errors.

- [ ] **Step 5: Commit Task 4**

Run:

```powershell
git add -- tests/dashboard
git commit -m "test: cover SMC orderflow dashboard contract"
```

Expected: commit succeeds.

---

## Task 5: Update User Documentation

**Files:**
- Modify: `docs/用户操作手册.md`

- [ ] **Step 1: Add user-facing section**

Add this section after the existing “SMC 阶段追踪” section or near dashboard explanations:

```markdown
### SMC 订单流雷达

“SMC 订单流雷达”用于把每一轮行情分析拆成 5 个判断层：

| 模块 | 你应该看什么 |
|---|---|
| 结构 | D1/H4 是偏多、偏空，还是方向不清晰 |
| 交易区 | H1 是否有可用订单块或 FVG 区域 |
| 流动性 | 上方/下方是否有等高、等低或扫流动性迹象 |
| 入场 | M15 是否出现 CHoCH、BOS、FVG 回补等触发 |
| 风险 | 候选 setup 是否满足 RR、共振和风控要求 |

推荐阅读顺序：

1. 先看顶部一句话结论，判断是“可交易候选”“等待确认”还是“已阻断”。
2. 再看红黄绿模块，找出当前卡在哪一层。
3. 展开“学习每一层 SMC 判断”，理解 D1/H4、H1、M15 的推理链路。
4. 展开“关键价位地图”，核对当前价与订单块、FVG、流动性位置的关系。

注意：雷达显示的是系统对订单流的结构化分析，不是手动追单信号。只有系统通过入场、风险和风控后，才会形成可交易候选。
```

- [ ] **Step 2: Scan documentation for stale old wording**

Run:

```powershell
rg -n "SMC 阶段追踪|订单流雷达" docs\用户操作手册.md docs\dashboard_guide.md
```

Expected: docs mention `SMC 订单流雷达`; legacy `SMC 阶段追踪` may remain as explanatory history only if phrased as old/fallback.

- [ ] **Step 3: Commit Task 5**

Run:

```powershell
git add -- docs/用户操作手册.md
git commit -m "docs: explain SMC orderflow radar"
```

Expected: commit succeeds.

---

## Task 6: Final Verification

**Files:**
- No new source edits unless verification exposes a defect

- [ ] **Step 1: Run focused backend tests**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/smc/unit/strategy/test_smc_orderflow.py tests/smc/unit/strategy/test_smc_trace.py tests/smc/unit/monitor/test_live_state_status.py -q
```

Expected: all selected tests pass.

- [ ] **Step 2: Run dashboard tests**

Run:

```powershell
$env:POLARS_SKIP_CPU_CHECK='1'; .\.venv\Scripts\python.exe -m pytest tests/dashboard -q
```

Expected: all dashboard tests pass.

- [ ] **Step 3: Parse-check dashboard JavaScript**

Run:

```powershell
node -e "const fs=require('fs'); const html=fs.readFileSync('dashboard/index.html','utf8'); const scripts=[...html.matchAll(/<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/gi)].map(m=>m[1]); for (const s of scripts) new Function(s); console.log('inline scripts ok:', scripts.length);"
```

Expected: `inline scripts ok: 2`.

- [ ] **Step 4: Inspect git status**

Run:

```powershell
git status --short
```

Expected:

- Only intended files are modified or committed.
- Pre-existing runtime files under `data/XAUUSD/` may still appear modified; do not revert them.
- `.superpowers/` may remain untracked from brainstorming; do not stage it unless the user explicitly wants it.

- [ ] **Step 5: Summarize outcome**

Final response must include:

- Files changed.
- Tests run and pass/fail status.
- Any environment caveat, especially `POLARS_SKIP_CPU_CHECK=1`.
- Reminder that trading logic was not changed.

