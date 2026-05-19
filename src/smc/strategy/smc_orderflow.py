"""Dashboard-friendly SMC orderflow summary.

This module converts existing live diagnostics into a stable, compact shape
for dashboard display. It must not perform trading decisions, I/O, MT5 calls,
network requests, or AI calls.
"""

from __future__ import annotations

from typing import Any

__all__ = ["build_smc_orderflow"]

_RADAR_ITEMS = (
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


def _int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _status_item(key: str, label: str, status: str, title: str, detail: str) -> dict[str, str]:
    return {
        "key": key,
        "label": label,
        "status": status,
        "title": title,
        "detail": detail,
    }


def _bias_label(bias: str | None) -> str:
    return {
        "bullish": "偏多",
        "bearish": "偏空",
        "neutral": "中性",
        "unknown": "未知",
    }.get(str(bias or "").lower(), "未知")


def _direction_label(direction: str | None) -> str:
    return {
        "long": "多头",
        "short": "空头",
        "buy": "多头",
        "sell": "空头",
    }.get(str(direction or "").lower(), "未知方向")


def _trigger_label(trigger: str | None) -> str:
    mapping = {
        "choch_in_zone": "CHoCH 入场",
        "fvg_fill_in_zone": "FVG 回补",
        "ob_test_rejection": "订单块回踩",
        "bos_in_zone": "BOS 入场",
        "fvg_sweep_continuation": "FVG 扫流动性延续",
    }
    return mapping.get(str(trigger or ""), str(trigger or "未知触发"))


def _debug() -> dict[str, str]:
    return {"source": "smc_orderflow"}


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
            for key, label in _RADAR_ITEMS
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
        "debug": _debug(),
    }


def _zone_levels(zone_details: list[dict[str, Any]]) -> list[dict[str, Any]]:
    levels: list[dict[str, Any]] = []
    for zone in zone_details[:6]:
        high = zone.get("high")
        low = zone.get("low")
        if high is None or low is None:
            continue

        direction = str(zone.get("direction") or "").lower()
        side = "below" if direction == "long" else "above" if direction == "short" else "unknown"
        proximity = "价格已接近扩展区" if zone.get("in_expanded_zone") else "价格尚未接近"
        levels.append(
            {
                "kind": "zone",
                "label": f"H1 {_direction_label(direction)}交易区",
                "low": _num(low),
                "high": _num(high),
                "side": side,
                "detail": f"距当前价 {zone.get('dist_from_price', '未知')}，{proximity}",
            }
        )
    return levels


def _liquidity_detail(range_diagnostic: dict[str, Any]) -> str:
    detect = dict(range_diagnostic.get("detect") or {})
    if not detect:
        return "暂未检测到明确扫流动性摘要。"
    source = detect.get("final_source") or detect.get("source") or detect.get("method")
    return f"区间/流动性来源：{source or '暂无明确来源'}。"


def _build_key_levels(
    *,
    current_price: float | None,
    smc: dict[str, Any],
    best_setup: dict[str, Any],
    zone_details: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    key_levels: list[dict[str, Any]] = []
    price = current_price if current_price is not None else smc.get("current_price")
    if price is not None:
        key_levels.append(
            {
                "kind": "current_price",
                "label": "当前价",
                "price": _num(price),
                "side": "current",
                "detail": "本轮分析价格",
            }
        )

    key_levels.extend(_zone_levels(zone_details))

    if best_setup:
        key_levels.extend(
            [
                {
                    "kind": "entry",
                    "label": "计划入场",
                    "price": _num(best_setup.get("entry")),
                    "side": "current",
                    "detail": _trigger_label(best_setup.get("trigger")),
                },
                {
                    "kind": "stop_loss",
                    "label": "止损",
                    "price": _num(best_setup.get("sl")),
                    "side": "risk",
                    "detail": "系统计划止损",
                },
                {
                    "kind": "take_profit",
                    "label": "止盈",
                    "price": _num(best_setup.get("tp1")),
                    "side": "reward",
                    "detail": "系统计划止盈",
                },
            ]
        )

    return key_levels[:8]


def build_smc_orderflow(
    *,
    smc_trace: dict[str, Any] | None,
    smc_diagnostic: dict[str, Any] | None,
    range_diagnostic: dict[str, Any] | None,
    best_setup: dict[str, Any] | None,
    current_price: float | None,
) -> dict[str, Any]:
    """Build a stable SMC orderflow summary for dashboard rendering."""
    if smc_diagnostic is None:
        return _build_unknown()

    smc = dict(smc_diagnostic or {})
    trace = dict(smc_trace or {})
    range_diag = dict(range_diagnostic or {})
    best = dict(best_setup or {})

    bias = str(smc.get("htf_bias_direction") or "unknown").lower()
    bias_readable = _bias_label(bias)
    stage_reject = str(smc.get("stage_reject") or "")
    decision = dict(trace.get("decision") or {})
    setup_count = _int(decision.get("setup_count") or smc.get("final_count"))
    zone_count = _int(smc.get("h1_zones_count"))
    zone_rejects = dict(smc.get("zone_rejects") or {})
    zone_details = list(smc.get("zone_details") or [])

    has_best_setup = bool(best)
    if has_best_setup:
        readiness = "ready"
        headline = (
            "SMC 已形成可交易候选："
            f"{_direction_label(best.get('direction'))}，触发为 {_trigger_label(best.get('trigger'))}。"
        )
        blocking_reason = ""
    elif stage_reject in {"htf_bias_neutral", "legacy_ranging_gate", "no_h1_zones"}:
        readiness = "blocked"
        headline = "SMC 条件被阻断：H1 没有可用交易区。" if stage_reject == "no_h1_zones" else "SMC 条件被阻断：大周期方向不清晰。"
        blocking_reason = stage_reject
    else:
        readiness = "waiting"
        zone_text = "H1 有候选交易区，" if zone_count else "等待 H1 交易区，"
        headline = f"大周期{bias_readable}，{zone_text}等待 M15 入场确认。"
        blocking_reason = "等待 M15 CHoCH / BOS / FVG 回补确认"

    htf_confidence = _num(smc.get("htf_bias_confidence"))
    structure_status = (
        "blocked"
        if stage_reject in {"htf_bias_neutral", "legacy_ranging_gate"}
        else "passed"
        if bias in {"bullish", "bearish"}
        else "unknown"
    )
    zone_status = "blocked" if stage_reject == "no_h1_zones" else "passed" if zone_count > 0 else "waiting"
    entry_status = "passed" if has_best_setup or setup_count > 0 else "skipped" if zone_status == "blocked" else "waiting"
    risk_status = "passed" if has_best_setup else "waiting" if readiness == "waiting" else "skipped"

    entry_none = _int(zone_rejects.get("entry_none"))
    confluence_low = _int(zone_rejects.get("confluence_low"))
    trigger_filter = _int(zone_rejects.get("trigger_filter"))

    radar = [
        _status_item(
            "structure",
            "结构",
            structure_status,
            f"大周期{bias_readable}",
            str(smc.get("htf_bias_rationale") or "等待 D1/H4 BOS/CHoCH 结构确认。"),
        ),
        _status_item(
            "zone",
            "交易区",
            zone_status,
            f"找到 {zone_count} 个 H1 候选区" if zone_count else "暂无 H1 交易区",
            "优先关注与大周期方向一致的订单块/FVG。"
            if zone_count
            else "没有找到与大周期方向一致的 H1 订单块或 FVG。",
        ),
        _status_item(
            "liquidity",
            "流动性",
            "waiting",
            "观察流动性位置",
            _liquidity_detail(range_diag),
        ),
        _status_item(
            "entry",
            "入场",
            entry_status,
            "M15 入场确认 (BOS/CHoCH/FVG)" if entry_status == "passed" else "等待 M15 触发 (BOS/CHoCH/FVG)",
            f"无触发 {entry_none}，共振不足 {confluence_low}，触发器不匹配 {trigger_filter}。",
        ),
        _status_item(
            "risk",
            "风险",
            risk_status,
            "风险条件通过" if has_best_setup else "等待风险计算",
            (
                f"RR {_num(best.get('exec_rr_ratio') or best.get('planned_rr_ratio')):.2f}，"
                f"共振 {_num(best.get('confluence')):.2f}"
            )
            if has_best_setup
            else "形成候选 setup 后再计算 RR、共振和风控。",
        ),
    ]

    timeline = [
        {
            "timeframe": "D1/H4",
            "label": "大周期结构",
            "status": structure_status,
            "explanation": f"D1/H4 当前{bias_readable}，置信度 {htf_confidence * 100:.0f}%。",
        },
        {
            "timeframe": "H1",
            "label": "交易区",
            "status": zone_status,
            "explanation": f"H1 找到 {zone_count} 个候选交易区。" if zone_count else "H1 暂无可用订单块/FVG 交易区。",
        },
        {
            "timeframe": "M15",
            "label": "入场触发",
            "status": entry_status,
            "explanation": "已形成入场触发 (BOS/CHoCH/FVG)。" if entry_status == "passed" else "价格尚未在交易区内形成 M15 的 BOS、CHoCH 或 FVG 确认。",
        },
    ]

    return {
        "summary": {
            "bias": bias,
            "readiness": readiness,
            "headline": headline,
            "blocking_reason": blocking_reason,
        },
        "radar": radar,
        "timeline": timeline,
        "key_levels": _build_key_levels(
            current_price=current_price,
            smc=smc,
            best_setup=best,
            zone_details=zone_details,
        ),
        "debug": _debug(),
    }
