from __future__ import annotations

from smc.monitor.journal_files import ensure_journal_file


def test_ensure_journal_file_creates_empty_jsonl(tmp_path) -> None:
    journal_path = tmp_path / "journal" / "live_trades.jsonl"

    ensure_journal_file(journal_path)

    assert journal_path.exists()
    assert journal_path.read_text(encoding="utf-8") == ""
