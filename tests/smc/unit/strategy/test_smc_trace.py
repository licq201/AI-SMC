"""Unit tests for dashboard-friendly SMC trace construction."""

from __future__ import annotations

from smc.strategy.smc_trace import build_smc_trace


def test_build_smc_trace_explains_no_setup_stage() -> None:
    trace = build_smc_trace(
        smc_diagnostic={
            "htf_bias_direction": "bullish",
            "htf_bias_confidence": 0.42,
            "htf_bias_rationale": "Tier 4: D1+H4 structure indeterminate; SMA50 slope +0.0600%/bar.",
            "stage_reject": "no_h1_zones",
            "final_count": 0,
            "current_price": 2350.12,
        },
        range_diagnostic={
            "detect": {"final_source": None, "method_a_hit": False, "method_b_hit": False},
            "setups": {"reason_if_zero": "middle"},
        },
        setups_count=0,
        action="HOLD",
        reason="No trade setup",
        ai_analysis={"ai_source": "sma_fallback", "ai_direction": "bullish"},
    )

    assert trace["current_stage"] == "h1_zone"
    assert trace["decision"]["action"] == "HOLD"
    assert trace["ai"]["source"] == "sma_fallback"
    assert trace["stages"][0]["name"] == "htf_bias"
    assert trace["stages"][0]["status"] == "passed"
    assert trace["stages"][1]["name"] == "h1_zone"
    assert trace["stages"][1]["status"] == "blocked"
    assert "没有找到" in trace["stages"][1]["explanation"]


def test_build_smc_trace_marks_entry_when_candidates_exist() -> None:
    trace = build_smc_trace(
        smc_diagnostic={
            "htf_bias_direction": "bearish",
            "htf_bias_confidence": 0.72,
            "htf_bias_rationale": "Tier 1: D1 and H4 both bearish.",
            "h1_zones_count": 2,
            "zone_rejects": {"entry_none": 1, "confluence_low": 0},
            "final_count": 1,
        },
        range_diagnostic={},
        setups_count=1,
        action="SELL",
        reason="V1 setup accepted",
        ai_analysis={"ai_source": "technical_fallback", "ai_direction": "bearish"},
    )

    assert trace["current_stage"] == "decision"
    assert trace["stages"][2]["name"] == "m15_entry"
    assert trace["stages"][2]["status"] == "passed"
    assert trace["decision"]["setup_count"] == 1
