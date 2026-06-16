"""
AI-SMC Dashboard Web Server (MVP).

轻量 FastAPI server, 读 data/{SYMBOL}/*.json 暴露 REST API + serve dashboard/index.html.
端口 8765 (PRD § 7 契约)。

Stage 4: 支持 `?symbol=XAUUSD|BTCUSD` 切换，单 port 8765 服务双 symbol。
默认 symbol: XAUUSD (兼容旧行为)。

启动:
    python scripts/dashboard_server.py
然后浏览器打开 http://localhost:8765 或 http://localhost:8765?symbol=BTCUSD
"""
from __future__ import annotations

import json
import logging
import importlib.util
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

os.environ.setdefault("POLARS_SKIP_CPU_CHECK", "1")
os.environ.setdefault("PYTHONUTF8", "1")
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
import uvicorn

logger = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
DASHBOARD_HTML = ROOT / "dashboard" / "index.html"

STALE_THRESHOLD_SEC = 5 * 60  # 5 分钟无更新视为 stale

app = FastAPI(title="AI-SMC Dashboard", docs_url=None, redoc_url=None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _symbol_data_root(symbol: str) -> Path:
    """Validate symbol against SYMBOL_REGISTRY; return data/{SYMBOL}/ path.

    Falls back to XAUUSD with a warning if the symbol is unknown so that
    stale/invalid query params never crash the server.
    """
    from smc.instruments import get_instrument_config  # lazy import — avoids circular at module load
    try:
        get_instrument_config(symbol)
    except KeyError:
        logger.warning("Unknown symbol %r — falling back to XAUUSD", symbol)
        symbol = "XAUUSD"
    return DATA / symbol


def _read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def _freshness(state: dict | None) -> dict:
    if not state or not state.get("timestamp"):
        return {"fresh": False, "age_sec": None, "stale": True}
    try:
        ts = datetime.fromisoformat(state["timestamp"].replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return {"fresh": False, "age_sec": None, "stale": True}
    age = (datetime.now(timezone.utc) - ts).total_seconds()
    return {"fresh": age <= STALE_THRESHOLD_SEC, "age_sec": int(age), "stale": age > STALE_THRESHOLD_SEC}


def _load_strategy_server_module():
    """Load scripts/strategy_server.py so dashboard:8765 can serve /signal."""
    module_name = "_aismc_strategy_server_for_dashboard"
    if module_name in sys.modules:
        return sys.modules[module_name]

    path = Path(__file__).resolve().parent / "strategy_server.py"
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load strategy_server.py from {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = mod
    spec.loader.exec_module(mod)
    return mod


def _mt5_symbol_for(symbol: str, cfg: Any) -> str:
    """Resolve canonical dashboard symbol to broker-specific MT5 symbol."""
    from smc.instruments import get_instrument_config

    try:
        default_symbol = get_instrument_config(symbol).mt5_path
    except KeyError:
        default_symbol = symbol
    if hasattr(cfg, "broker_symbol_for"):
        return cfg.broker_symbol_for(symbol, default_symbol)
    return default_symbol


def _account_payload(login: Any, server: Any, balance: Any, *, source: str) -> dict[str, Any]:
    login_value = int(login) if login not in (None, "") else None
    server_value = str(server or "")
    label = (
        f"{server_value}-{login_value}"
        if server_value and login_value is not None
        else "MT5 account unavailable"
    )
    title = (
        f"{server_value} #{login_value} AI-SMC"
        if server_value and login_value is not None
        else "AI-SMC"
    )
    return {
        "login": login_value,
        "server": server_value or None,
        "balance": float(balance) if balance not in (None, "") else None,
        "label": label,
        "title": title,
        "source": source,
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


def _latest_startup_account_from_logs(log_root: Path) -> dict[str, Any] | None:
    """Return latest system_startup account payload from structured logs."""
    paths = sorted(log_root.glob("structured.jsonl*"), key=lambda p: p.stat().st_mtime)
    for path in reversed(paths):
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            continue
        for line in reversed(lines):
            if "system_startup" not in line:
                continue
            try:
                _, json_part = line.split("] ", 1)
                row = json.loads(json_part)
            except (ValueError, json.JSONDecodeError):
                continue
            if row.get("event") != "system_startup":
                continue
            return _account_payload(
                row.get("account"),
                row.get("server"),
                row.get("balance"),
                source="structured_log",
            )
    return None


def _live_mt5_account_payload() -> dict[str, Any] | None:
    """Read account_info from the current MT5 terminal when available."""
    try:
        import MetaTrader5 as mt5_mod  # type: ignore
    except ImportError:
        return None
    if mt5_mod is None:
        return None

    from smc.config import SMCConfig

    cfg = SMCConfig()
    kwargs: dict[str, Any] = {"timeout": 10_000}
    if cfg.mt5_login and cfg.mt5_login > 0:
        kwargs["login"] = cfg.mt5_login
        kwargs["password"] = cfg.mt5_password.get_secret_value()
        kwargs["server"] = cfg.mt5_server
    if cfg.mt5_path:
        kwargs["path"] = cfg.mt5_path

    if not mt5_mod.initialize(**kwargs):
        return None
    try:
        info = mt5_mod.account_info()
        if info is None:
            return None
        return _account_payload(
            getattr(info, "login", None),
            getattr(info, "server", None),
            getattr(info, "balance", None),
            source="mt5_live",
        )
    finally:
        mt5_mod.shutdown()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/signal")
def get_signal_compat(symbol: str = Query(..., min_length=3, max_length=32)) -> JSONResponse:
    """Compatibility path for EAs pointed at dashboard port 8765 by mistake."""
    strategy_server = _load_strategy_server_module()
    original_data_root = strategy_server.DATA_ROOT
    strategy_server.DATA_ROOT = DATA
    try:
        return strategy_server.get_signal(symbol)
    finally:
        strategy_server.DATA_ROOT = original_data_root


@app.get("/api/symbols")
def list_symbols() -> JSONResponse:
    """Return all registered trading symbols."""
    from smc.instruments import SYMBOL_REGISTRY  # lazy import
    return JSONResponse({"symbols": sorted(SYMBOL_REGISTRY.keys())})


@app.get("/api/account")
def get_account() -> JSONResponse:
    account = _live_mt5_account_payload()
    if account is None:
        account = _latest_startup_account_from_logs(ROOT / "logs")
    if account is None:
        account = _account_payload(None, None, None, source="unavailable")
    return JSONResponse(account)


@app.get("/api/state")
def get_state(symbol: str = Query(default="XAUUSD")) -> JSONResponse:
    root = _symbol_data_root(symbol)
    state = _read_json(root / "live_state.json")
    ai = _read_json(root / "ai_analysis.json")
    pause_flag = root / "trading_paused.flag"
    return JSONResponse({
        "state": state,
        "ai": ai,
        "freshness": _freshness(state),
        "trading_paused": pause_flag.exists(),
        "server_time": datetime.now(timezone.utc).isoformat(),
    })


@app.get("/api/positions")
def get_positions(symbol: str = Query(default="XAUUSD")) -> JSONResponse:
    """Real-time broker positions + halt state for the Hero card.

    ``live_demo`` writes ``data/{SYMBOL}/mt5_positions.json`` at the end of
    each M15 cycle via the MT5 positions adapter. Empty list (not 404) on a
    missing file keeps the dashboard usable during cold starts / market-closed.

    Round 6 B4: each position row is enriched with ``trail_activate_r`` +
    ``trail_distance_r`` + ``regime_at_open`` — derived from
    :func:`smc.ai.param_router.get_trail_params` by tail-scanning
    ``logs/structured.jsonl`` for the last ``ai_regime_classified`` event
    whose ``ts <= position.open_time``. Unknown / missing regime → fields
    are ``None`` and the UI renders an empty pill. Never raises: attachment
    failure falls back to the raw broker rows.
    """
    from smc.monitor.dashboard_feeds import attach_trail_params_to_positions

    root = _symbol_data_root(symbol)
    data = _read_json(root / "mt5_positions.json") or {}
    halt = _read_json(root / "consec_loss_state.json") or {}
    raw_positions = data.get("positions", []) or []
    try:
        enriched_positions = attach_trail_params_to_positions(
            raw_positions,
            structured_log_path=ROOT / "logs" / "structured.jsonl",
        )
    except Exception as exc:
        logger.warning("trail attach fail, returning raw positions: %s", exc)
        enriched_positions = raw_positions
    return JSONResponse({
        "ts": data.get("ts"),
        "positions": enriched_positions,
        "halt": {
            "tripped": bool(halt.get("tripped", False)),
            "consec_losses": int(halt.get("consec_losses", 0)),
            "tripped_at": halt.get("tripped_at"),
        },
    })


@app.get("/api/journal")
def get_journal(
    symbol: str = Query(default="XAUUSD"),
    limit: int = Query(default=50, ge=1, le=500),
) -> JSONResponse:
    root = _symbol_data_root(symbol)
    journal_path = root / "journal" / "live_trades.jsonl"
    if not journal_path.exists():
        return JSONResponse({"trades": []})
    try:
        lines = journal_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return JSONResponse({"trades": []})
    trades = []
    for line in lines[-limit:]:
        line = line.strip()
        if not line:
            continue
        try:
            trades.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return JSONResponse({"trades": trades})


@app.get("/healthz")
def healthz() -> JSONResponse:
    """Round 3 Sprint 2: liveness probe for watchdog_smart DashboardWeb branch.

    Returns 200 when:
      - FastAPI process is responding
      - JSON parser is working (round-trip check)
      - Data root is accessible

    Never calls MT5 or heavy aggregations so it stays cheap (<5ms).  Parallel
    to strategy_server.py:/healthz (audit-r1 P0-2).
    """
    ok = True
    probes: dict[str, object] = {}
    try:
        json.loads("{}")
        probes["json_parser"] = "ok"
    except Exception as exc:  # pragma: no cover — json.loads("{}") never fails
        ok = False
        probes["json_parser"] = f"fail: {exc}"
    try:
        probes["data_root_exists"] = DATA.exists()
        if not DATA.exists():
            ok = False
    except Exception as exc:
        ok = False
        probes["data_root_exists"] = f"fail: {exc}"
    payload = {
        "ok": ok,
        "service": "AI-SMC Dashboard",
        "ts": datetime.now(timezone.utc).isoformat(),
        "probes": probes,
    }
    return JSONResponse(payload, status_code=200 if ok else 503)


@app.get("/api/guards")
def get_guards(symbol: str = Query(default="XAUUSD")) -> JSONResponse:
    """Round 3 Sprint 2: live guards traffic-light snapshot.

    Returns 4 guard states (consec / phase1a / asian_quota / drawdown) with
    per-guard status ``green`` / ``amber`` / ``red`` so the dashboard can
    render "why can't I trade right now" at a glance.
    """
    from smc.instruments import get_instrument_config
    from smc.monitor.guards_snapshot import build_guards_snapshot

    root = _symbol_data_root(symbol)
    # Per-symbol consec_loss_limit (R4) — fall back to 3 if cfg is missing
    # (_symbol_data_root already normalises unknown symbols to XAUUSD).
    try:
        cfg = get_instrument_config(symbol)
        consec_limit = getattr(cfg, "consec_loss_limit", 3)
    except KeyError:
        consec_limit = 3
    snap = build_guards_snapshot(symbol, data_root=root, consec_loss_limit=consec_limit)
    return JSONResponse(snap)


@app.get("/api/daily_digest")
def get_daily_digest(
    symbol: str = Query(default="XAUUSD"),
    date_str: str | None = Query(default=None, alias="date"),
) -> JSONResponse:
    """Round 3 Sprint 1: one-page "today" summary for老板 5min scan.

    Response schema per `.scratch/audit-r2/ops-daily-digest-spec.md` §2.
    Builder tolerates missing data sources; returns zeros + warnings list.
    """
    from datetime import date as date_cls
    from smc.monitor.daily_digest import build_daily_digest

    try:
        target = date_cls.fromisoformat(date_str) if date_str else datetime.now(timezone.utc).date()
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid date format, expected YYYY-MM-DD, got: {date_str!r}",
        )
    root = _symbol_data_root(symbol)
    digest = build_daily_digest(symbol, target, data_root=root, log_root=ROOT / "logs")
    return JSONResponse(digest)


@app.get("/api/regime")
def get_regime(limit: int = Query(default=5, ge=1, le=20)) -> JSONResponse:
    """Round 5 O1: tail last N ``ai_regime_classified`` events.

    Cross-symbol (regime events are written by whichever leg runs the AI
    classifier — not partitioned per symbol). Filter out ``source=="default"``
    cold-start noise so the dashboard only surfaces real regime calls.
    """
    from smc.monitor.dashboard_feeds import tail_regime_events

    events = tail_regime_events(ROOT / "logs" / "structured.jsonl", limit=limit)
    return JSONResponse({"events": events, "server_time": datetime.now(timezone.utc).isoformat()})


@app.get("/api/pnl")
def get_pnl() -> JSONResponse:
    """Round 5 O2: today's P&L per leg (control_xau / treatment_xau / control_btc).

    Aggregates realized P&L from ``mt5.history_deals_get(today_00Z, now)``
    grouped by composite (symbol, magic) key — BTC has no treatment leg,
    so ``treatment_btc`` never appears.  Floating P&L comes from
    ``mt5.positions_get()`` directly.  Not symbol-scoped — response
    carries all three legs side-by-side.  5s cache inside
    ``build_pnl_snapshot()`` matches the dashboard poll cadence so MT5
    is hit at most once per cycle.
    """
    from smc.monitor.dashboard_feeds import build_pnl_snapshot

    try:
        import MetaTrader5 as mt5_mod  # type: ignore
    except ImportError:
        mt5_mod = None
    snapshot = build_pnl_snapshot(mt5_mod, data_root=DATA)
    return JSONResponse(snapshot)


@app.get("/api/config")
def get_config(symbol: str = Query(default="XAUUSD")) -> JSONResponse:
    root = _symbol_data_root(symbol)
    cfg = _read_json(root / "user_config.json") or {}
    return JSONResponse(cfg)


@app.post("/api/config")
async def set_config(
    request: Request,
    symbol: str = Query(default="XAUUSD"),
) -> JSONResponse:
    try:
        body = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {exc}")
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Body must be a JSON object")
    root = _symbol_data_root(symbol)
    config_path = root / "user_config.json"
    body["updated_at"] = datetime.now(timezone.utc).isoformat()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(body, indent=2, ensure_ascii=False), encoding="utf-8")
    return JSONResponse({"ok": True, "path": str(config_path)})


@app.post("/api/toggle_trading")
async def toggle_trading(
    request: Request,
    symbol: str = Query(default="XAUUSD"),
) -> JSONResponse:
    body = await request.json()
    paused = bool(body.get("paused", False))
    root = _symbol_data_root(symbol)
    flag = root / "trading_paused.flag"
    if paused:
        flag.parent.mkdir(parents=True, exist_ok=True)
        flag.write_text(datetime.now(timezone.utc).isoformat(), encoding="utf-8")
    else:
        flag.unlink(missing_ok=True)
    return JSONResponse({"paused": paused})


# ---------------------------------------------------------------------------
# Chart data — /api/candles and /api/smc
# ---------------------------------------------------------------------------

def _fetch_bars(symbol: str, tf_str: str, limit: int) -> "pl.DataFrame":
    """Fetch recent OHLCV bars from a live MT5 terminal.

    Raises
    ------
    HTTPException(400)  Unknown timeframe string.
    HTTPException(503)  MT5 mock mode, missing credentials, or connection failure.
    """
    import polars as pl
    from smc.config import SMCConfig
    from smc.monitor.chart_feeds import TF_MAP, tf_bar_duration

    cfg = SMCConfig()

    if cfg.mt5_mock:
        raise HTTPException(
            status_code=503,
            detail=(
                "MT5 not connected: SMC_MT5_MOCK=1. "
                "Set SMC_MT5_MOCK=0 on Windows VPS with MT5 running."
            ),
        )
    if not cfg.has_mt5_credentials():
        raise HTTPException(
            status_code=503,
            detail=(
                "MT5 credentials not configured. "
                "Set SMC_MT5_LOGIN, SMC_MT5_PASSWORD, SMC_MT5_SERVER in .env"
            ),
        )
    if tf_str not in TF_MAP:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown timeframe {tf_str!r}. Valid: {sorted(TF_MAP)}",
        )

    from smc.data.adapters.mt5_adapter import MT5Adapter
    from smc.monitor.chart_feeds import MT5_SERVER_TIME_OFFSET

    tf_enum   = TF_MAP[tf_str]
    duration  = tf_bar_duration[tf_str]
    mt5_symbol = _mt5_symbol_for(symbol, cfg)
    # MT5's copy_rates_range treats datetime args as broker server time (UTC+3),
    # not UTC. Shift by the server offset so MT5 fetches the correct range.
    end       = datetime.now(timezone.utc) + MT5_SERVER_TIME_OFFSET
    start     = end - duration * (limit + 60)

    try:
        with MT5Adapter(
            login=cfg.mt5_login,
            password=cfg.mt5_password.get_secret_value(),
            server=cfg.mt5_server,
            path=cfg.mt5_path or None,
            instrument=mt5_symbol,
        ) as adapter:
            df = adapter.fetch(instrument=mt5_symbol, timeframe=tf_enum, start=start, end=end)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"MT5 fetch failed: {exc}") from exc

    if len(df) == 0:
        raise HTTPException(status_code=503, detail="MT5 returned empty data.")

    return df.tail(limit)


@app.get("/api/candles")
def get_candles(
    symbol: str = Query(default="XAUUSD"),
    tf:     str = Query(default="H1"),
    limit:  int = Query(default=200, ge=10, le=1000),
) -> JSONResponse:
    """Return recent OHLCV bars as Lightweight-Charts-compatible JSON."""
    df = _fetch_bars(symbol, tf, limit)
    try:
        candles = []
        for row in df.iter_rows(named=True):
            ts = row["ts"]
            candles.append({
                "time":  int(ts.timestamp()) if isinstance(ts, datetime) else int(ts),
                "open":  round(float(row["open"]),  5),
                "high":  round(float(row["high"]),  5),
                "low":   round(float(row["low"]),   5),
                "close": round(float(row["close"]), 5),
            })
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Candle serialization failed: {exc}") from exc
    return JSONResponse({"symbol": symbol, "timeframe": tf, "candles": candles})


@app.get("/api/smc")
def get_smc(
    symbol: str = Query(default="XAUUSD"),
    tf:     str = Query(default="H1"),
    limit:  int = Query(default=300, ge=50, le=2000),
) -> JSONResponse:
    """Return OHLCV bars + all SMC signals for chart.html."""
    from smc.monitor.chart_feeds import TF_MAP, serialize_smc, swing_length_for
    from smc.smc_core.detector import SMCDetector

    df      = _fetch_bars(symbol, tf, limit)
    tf_enum = TF_MAP[tf]

    try:
        detector = SMCDetector(swing_length=swing_length_for(tf))
        snapshot = detector.detect(df, tf_enum)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"SMC detection failed: {exc}") from exc

    payload = serialize_smc(snapshot, df)
    payload["symbol"]       = symbol
    payload["timeframe"]    = tf
    payload["generated_at"] = datetime.now(timezone.utc).isoformat()
    return JSONResponse(payload)


@app.get("/")
def index() -> FileResponse:
    if not DASHBOARD_HTML.exists():
        raise HTTPException(status_code=404, detail=f"dashboard/index.html not found at {DASHBOARD_HTML}")
    return FileResponse(DASHBOARD_HTML, media_type="text/html")


@app.get("/chart")
def chart_page() -> FileResponse:
    """Serve the standalone SMC chart page."""
    path = ROOT / "dashboard" / "chart.html"
    if not path.exists():
        raise HTTPException(status_code=404, detail="dashboard/chart.html not found")
    return FileResponse(path, media_type="text/html")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8765, log_level="info")
