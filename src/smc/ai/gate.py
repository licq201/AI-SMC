"""Global AI execution gate.

This module is intentionally tiny and dependency-free so low-level AI callers
can check the operator kill switch without constructing the full application
config on every M15 cycle.
"""

from __future__ import annotations

import os

__all__ = ["ai_is_enabled"]


def _parse_bool(value: str | None, *, default: bool) -> bool:
    if value is None:
        return default
    stripped = value.split("#", 1)[0].strip().lower()
    if stripped in {"1", "true", "yes", "on"}:
        return True
    if stripped in {"0", "false", "no", "off", ""}:
        return False
    return default


def ai_is_enabled() -> bool:
    """Return False only when the global AI kill switch is explicitly off."""
    return _parse_bool(os.environ.get("SMC_AI_ENABLED"), default=True)
