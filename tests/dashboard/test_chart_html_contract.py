"""Static contract checks for dashboard/chart.html."""
from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent.parent
CHART_HTML = ROOT / "dashboard" / "chart.html"


def test_chart_declares_mt5_server_time_formatting() -> None:
    html = CHART_HTML.read_text(encoding="utf-8")

    assert "MT5_SERVER_TIME_OFFSET_SEC" in html
    assert "ts + MT5_SERVER_TIME_OFFSET_SEC" in html
    assert "tickMarkFormatter" in html
    assert "timeFormatter" in html
    assert "formatChartTime" in html
