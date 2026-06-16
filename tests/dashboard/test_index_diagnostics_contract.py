from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent.parent
INDEX_HTML = ROOT / "dashboard" / "index.html"


def test_waiting_state_does_not_translate_to_missing_range() -> None:
    html = INDEX_HTML.read_text(encoding="utf-8")

    assert "runtime_status !== \"waiting_next_m15\"" in html
    assert "找不到可交易区间，市场可能在单边趋势中" in html


def test_raw_diagnostic_includes_smc_diagnostic_fallback() -> None:
    html = INDEX_HTML.read_text(encoding="utf-8")

    assert "this.state?.smc_diagnostic" in html
    assert "range_diagnostic" in html


def test_today_trades_surface_strategy_and_reason_columns() -> None:
    html = INDEX_HTML.read_text(encoding="utf-8")

    assert "策略" in html
    assert "依据 / 状态" in html
    assert "strategyLabel(t)" in html
    assert "tradeReasonLabel(t)" in html


def test_account_header_is_loaded_from_server() -> None:
    html = INDEX_HTML.read_text(encoding="utf-8")

    assert 'fetch("/api/account")' in html
    assert "accountTitle" in html
    assert "东方6# AI-SMC" not in html
    assert "DooTechnology-563549" not in html
