"""Dashboard-friendly SMC decision trace.

The strategy already records raw diagnostics for debugging. This module turns
those fields into a compact, stable shape that is easier to display and easier
for a new SMC learner to follow cycle-by-cycle.
"""

from __future__ import annotations

from typing import Any

__all__ = ["build_smc_trace"]


def _status_for_block(stage: str, blocked_stage: str | None, passed: bool) -> str:
    if blocked_stage == stage:
        return "blocked"
    if passed:
        return "passed"
    return "pending"


def _stage_from_reject(stage_reject: str | None, setup_count: int) -> str:
    if setup_count > 0:
        return "decision"
    if stage_reject in {"htf_bias_neutral", "legacy_ranging_gate"}:
        return "htf_bias"
    if stage_reject in {"h1_snapshot_missing", "no_h1_zones"}:
        return "h1_zone"
    if stage_reject in {"m15_snapshot_missing"} or (stage_reject or "").startswith("all_entries_failed"):
        return "m15_entry"
    if (stage_reject or "").startswith("direction_filter"):
        return "regime_filter"
    if (stage_reject or "").startswith("ai_candidate_review_blocked"):
        return "ai_review"
    return "decision"


def _explain_h1_zone(stage_reject: str | None, zone_count: int | None) -> str:
    if stage_reject == "no_h1_zones":
        return "没有找到与 HTF 方向一致的 H1 OB/FVG 交易区。"
    if zone_count is None:
        return "尚未进入 H1 zone 阶段。"
    return f"找到 {zone_count} 个 H1 候选交易区。"


def _explain_m15_entry(zone_rejects: dict[str, Any], setup_count: int) -> str:
    if setup_count > 0:
        return f"M15 入场触发已形成，候选 setup 数量 {setup_count}。"
    entry_none = int(zone_rejects.get("entry_none") or 0)
    conf_low = int(zone_rejects.get("confluence_low") or 0)
    trigger_filter = int(zone_rejects.get("trigger_filter") or 0)
    if entry_none or conf_low or trigger_filter:
        return (
            f"M15 尚未通过入场确认：无触发 {entry_none}，"
            f"共振不足 {conf_low}，触发器不匹配 {trigger_filter}。"
        )
    return "等待价格进入 zone 并形成 M15 CHoCH/BOS/FVG 入场触发。"


def build_smc_trace(
    *,
    smc_diagnostic: dict[str, Any] | None,
    range_diagnostic: dict[str, Any] | None,
    setups_count: int,
    action: str,
    reason: str,
    ai_analysis: dict[str, Any] | None,
) -> dict[str, Any]:
    """Build a stable SMC trace dictionary for live_state/dashboard."""
    smc = dict(smc_diagnostic or {})
    range_diag = dict(range_diagnostic or {})
    ai = dict(ai_analysis or {})

    stage_reject = smc.get("stage_reject")
    zone_rejects = dict(smc.get("zone_rejects") or {})
    zone_count = smc.get("h1_zones_count")
    current_stage = _stage_from_reject(str(stage_reject) if stage_reject else None, setups_count)

    htf_passed = smc.get("htf_bias_direction") not in (None, "neutral")
    h1_passed = bool(zone_count)
    m15_passed = setups_count > 0

    stages = [
        {
            "name": "htf_bias",
            "label": "HTF 方向",
            "status": _status_for_block("htf_bias", current_stage, bool(htf_passed)),
            "direction": smc.get("htf_bias_direction"),
            "confidence": smc.get("htf_bias_confidence"),
            "explanation": smc.get("htf_bias_rationale") or "等待 D1/H4 结构方向确认。",
        },
        {
            "name": "h1_zone",
            "label": "H1 交易区",
            "status": _status_for_block("h1_zone", current_stage, bool(h1_passed)),
            "count": zone_count,
            "explanation": _explain_h1_zone(str(stage_reject) if stage_reject else None, zone_count),
        },
        {
            "name": "m15_entry",
            "label": "M15 入场",
            "status": _status_for_block("m15_entry", current_stage, bool(m15_passed)),
            "zone_rejects": zone_rejects,
            "explanation": _explain_m15_entry(zone_rejects, setups_count),
        },
        {
            "name": "regime_filter",
            "label": "环境过滤",
            "status": "blocked" if current_stage == "regime_filter" else "passed",
            "source": smc.get("ai_regime_source") or smc.get("ai_regime_stage"),
            "explanation": (
                f"Regime 阶段：{smc.get('ai_regime_stage', 'deterministic_prefilter')}。"
            ),
        },
        {
            "name": "ai_review",
            "label": "AI 复核",
            "status": "blocked" if current_stage == "ai_review" else (
                "passed" if smc.get("ai_regime_stage") == "candidate_review" else "skipped"
            ),
            "explanation": (
                "有候选交易时才进行 AI regime 复核；无候选时跳过以避免无效算力消耗。"
            ),
        },
    ]

    return {
        "current_stage": current_stage,
        "stages": stages,
        "decision": {
            "action": action,
            "reason": reason,
            "setup_count": setups_count,
        },
        "ai": {
            "source": ai.get("ai_source") or ai.get("source"),
            "direction": ai.get("ai_direction") or ai.get("direction"),
            "confidence": ai.get("ai_confidence") or ai.get("confidence"),
        },
        "range": range_diag,
    }
