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
                {
                    "high": 2355.0,
                    "low": 2351.0,
                    "direction": "long",
                    "dist_from_price": 4.2,
                    "in_expanded_zone": True,
                },
                {
                    "high": 2348.0,
                    "low": 2344.0,
                    "direction": "long",
                    "dist_from_price": 9.0,
                    "in_expanded_zone": False,
                },
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


def test_orderflow_unknown_when_smc_diagnostic_missing_even_with_price() -> None:
    orderflow = build_smc_orderflow(
        smc_trace=None,
        smc_diagnostic=None,
        range_diagnostic={},
        best_setup=None,
        current_price=2350.8,
    )

    assert orderflow["summary"]["readiness"] == "unknown"
    assert all(item["status"] == "unknown" for item in orderflow["radar"])
