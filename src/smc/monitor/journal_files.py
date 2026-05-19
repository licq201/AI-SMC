"""Helpers for runtime journal files."""

from __future__ import annotations

from pathlib import Path

__all__ = ["ensure_journal_file"]


def ensure_journal_file(path: Path) -> None:
    """Ensure an empty JSONL journal exists before the first trade."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(exist_ok=True)
