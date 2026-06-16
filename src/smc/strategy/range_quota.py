"""Asian ranging daily quota tracker.

Rationale: Asian session (incl. ASIAN_LONDON_TRANSITION) ranging setups are
rare and high-risk. Cap opens per UTC day to prevent regime-flip cascades.

LONDON/NY sessions are NOT subject to this quota — high liquidity allows
multiple setups per day.

Round 4.6-H2: adds JSON persistence so process restarts do not reset the
daily cap and allow a second open on the same UTC day.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path

__all__ = ["AsianRangeQuota", "DEFAULT_QUOTA_STATE_PATH"]

DEFAULT_QUOTA_STATE_PATH = Path("data/asian_range_quota_state.json")


@dataclass(frozen=True)
class AsianRangeQuota:
    """Immutable tracker of Asian ranging opens for the current UTC date.

    Usage:
        quota = AsianRangeQuota.load()  # Round 4.6-H2: restore across restarts
        if quota.is_exhausted_today(datetime.now(tz=timezone.utc)):
            return None  # skip setup
        # ... open trade ...
        quota = quota.record_open(datetime.now(tz=timezone.utc))
    """
    last_open_date: date | None = None
    opens_count: int = 0
    daily_limit: int = 1

    def is_exhausted_today(
        self,
        now_utc: datetime,
        *,
        daily_limit: int | None = None,
    ) -> bool:
        """True iff today's Asian range opens have reached the configured cap."""
        limit = _normalise_limit(daily_limit if daily_limit is not None else self.daily_limit)
        if self.last_open_date is None:
            return False
        if self.last_open_date != now_utc.astimezone(timezone.utc).date():
            return False
        return max(1, max(0, int(self.opens_count or 0))) >= limit

    def record_open(
        self,
        now_utc: datetime,
        state_path: Path | None = None,
        *,
        daily_limit: int | None = None,
    ) -> "AsianRangeQuota":
        """Return new quota with today's UTC open count incremented.

        Round 4.6-H2: also persists the new state to JSON so process
        restarts don't silently reset the cap. Callers that want to opt
        out of persistence can pass state_path explicitly via load(None).
        """
        today = now_utc.astimezone(timezone.utc).date()
        limit = _normalise_limit(daily_limit if daily_limit is not None else self.daily_limit)
        opens_count = self.opens_count if self.last_open_date == today else 0
        opens_count = max(0, int(opens_count or 0)) + 1
        new_quota = AsianRangeQuota(
            last_open_date=today,
            opens_count=opens_count,
            daily_limit=limit,
        )
        if state_path is None:
            state_path = DEFAULT_QUOTA_STATE_PATH
        try:
            state_path.parent.mkdir(parents=True, exist_ok=True)
            state_path.write_text(
                json.dumps(
                    {
                        "last_open_date": today.isoformat(),
                        "opens_count": opens_count,
                        "daily_limit": limit,
                    }
                )
            )
        except Exception:
            # persistence is best-effort; in-memory state still correct
            pass
        return new_quota

    @classmethod
    def load(
        cls,
        state_path: Path | None = None,
        *,
        daily_limit: int | None = None,
    ) -> "AsianRangeQuota":
        """Round 4.6-H2: restore quota from JSON, or fresh if no file.

        Corrupt/missing files yield a fresh quota (fail-open). This keeps
        paper trading tolerant of dev-env noise while giving live runs a
        durable daily cap.
        """
        limit = _normalise_limit(daily_limit)
        if state_path is None:
            state_path = DEFAULT_QUOTA_STATE_PATH
        if not state_path.exists():
            return cls(daily_limit=limit)
        try:
            raw = json.loads(state_path.read_text())
            iso = raw.get("last_open_date")
            if not iso:
                return cls(daily_limit=limit)
            opens_count = raw.get("opens_count")
            if opens_count is None:
                # Backward compatibility: legacy files only recorded the date,
                # which represented exactly one consumed Asian range slot.
                opens_count = 1
            persisted_limit = raw.get("daily_limit")
            effective_limit = _normalise_limit(
                daily_limit if daily_limit is not None else persisted_limit
            )
            return cls(
                last_open_date=date.fromisoformat(iso),
                opens_count=max(0, int(opens_count or 0)),
                daily_limit=effective_limit,
            )
        except Exception:
            return cls(daily_limit=limit)


def _normalise_limit(value: int | None) -> int:
    try:
        limit = int(value if value is not None else 1)
    except (TypeError, ValueError):
        limit = 1
    return max(1, limit)
