"""Structured JSON logging with severity tags for grep-ability.

Emits to stderr (always) and optionally to a rotating file.

File logging is enabled when the ``SMC_LOG_DIR`` environment variable is set
(or automatically in the default ``logs/`` directory if writable).  The file
handler uses daily midnight rotation with 14-day retention so the VPS disk
stays bounded.

Environment:
    SMC_LOG_DIR  — directory for structured.jsonl (default: "logs").
                   Set to "" or "none" to disable file logging entirely.
"""
from __future__ import annotations

import json
import logging
import logging.handlers
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal, TextIO

Severity = Literal["CRIT", "WARN", "INFO", "DEBUG"]

# ── File handler (lazy init, created once at module load) ─────────────────────

_DISABLE_FILE_LOG_SENTINELS = {"", "none", "0", "false", "off"}

def _build_file_handler() -> logging.Handler | None:
    """Return a TimedRotatingFileHandler or None if file logging is disabled."""
    log_dir_env = os.environ.get("SMC_LOG_DIR", "logs")
    if log_dir_env.lower() in _DISABLE_FILE_LOG_SENTINELS:
        return None
    log_dir = Path(log_dir_env)
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        handler = logging.handlers.TimedRotatingFileHandler(
            log_dir / "structured.jsonl",
            when="midnight",
            backupCount=14,
            encoding="utf-8",
        )
        handler.setFormatter(logging.Formatter("%(message)s"))
        return handler
    except Exception:
        return None  # disk error, readonly fs, etc. — degrade gracefully


_file_logger = logging.getLogger("smc.structured")
_file_logger.setLevel(logging.INFO)
_file_logger.propagate = False  # don't double-emit to root logger

if not _file_logger.handlers:
    _handler = _build_file_handler()
    if _handler is not None:
        _file_logger.addHandler(_handler)


# ── Public API ────────────────────────────────────────────────────────────────


CHINESE_EVENT_DESCRIPTIONS = {
    "peak_balance_daily_reset": "每日最高净值重置",
    "trading_paused": "交易已暂停（Dashboard 开关已启用）",
    "consec_loss_halt_active": "已触发连续亏损熔断保护",
    "drawdown_guard_block": "已触发每日最大回撤熔断保护",
    "tick_unavailable": "获取行情 Tick 失败",
    "mt5_handle_reset_giveup": "重试连接 MT5 失败多次，程序退出准备重启",
    "macro_bias_computed": "宏观大周期指标偏差计算完成",
    "macro_bias_fetch_failed": "宏观大周期指标数据获取失败",
    "pre_write_gate_blocked": "开仓前置风控闸门拦截",
    "paper_mode_signal": "纸面推演（模拟开仓）信号发出",
    "margin_cap_gate": "保证金占比上限风控拦截",
    "mt5_order_sent": "MT5 交易指令已发送",
    "mt5_order_opened": "MT5 开仓交易成功",
    "mt5_order_fail": "MT5 开仓交易失败",
    "asian_quota_exhausted": "亚洲盘每日交易配额已耗尽",
    "ai_regime_classified": "AI 市场环境分类完成",
    "health_probe": "系统健康指标发射",
    "virtual_balance_applied": "虚拟分仓余额比例计算已应用",
    "anti_stack_cooldown_block": "防密集堆叠冷却限制拦截",
    "stale_pid_removed": "检测到过期残留进程锁，自动清理",
}


def log_event(
    severity: Severity,
    event: str,
    stream: TextIO | None = None,
    **fields: Any,
) -> None:
    """Emit a structured log line to stderr (or given stream) and to the
    rotating log file (if file logging is enabled).

    Format: ``[<SEV>] {"ts": "...", "event": "...", ...}``

    - Tag on its own is grep-friendly (``tail -f | grep CRIT``)
    - JSON body makes parsing downstream easy
    - ``default=str`` handles datetime, Path, Decimal etc.
    """
    out = stream if stream is not None else sys.stderr
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "event": event,
        "event_zh": CHINESE_EVENT_DESCRIPTIONS.get(event, "系统事件"),
        **fields,
    }
    line = f"[{severity}] {json.dumps(payload, default=str, ensure_ascii=False)}\n"

    # Always write to stderr (or explicit stream)
    try:
        out.write(line)
        out.flush()
    except Exception:
        pass  # never raise from logging

    # Also write to rotating file (only when using default stderr stream,
    # not when a test passes an explicit StringIO)
    if stream is None and _file_logger.handlers:
        try:
            _file_logger.info(line.rstrip("\n"))
        except Exception:
            pass  # never raise from logging


def crit(event: str, **fields: Any) -> None:
    """Emit a CRIT-severity structured log line."""
    log_event("CRIT", event, **fields)


def warn(event: str, **fields: Any) -> None:
    """Emit a WARN-severity structured log line."""
    log_event("WARN", event, **fields)


def info(event: str, **fields: Any) -> None:
    """Emit an INFO-severity structured log line."""
    log_event("INFO", event, **fields)


__all__ = ["Severity", "log_event", "crit", "warn", "info"]
