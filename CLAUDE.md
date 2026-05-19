# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI-SMC is an end-to-end algorithmic trading system for XAUUSD (Gold) on MetaTrader 5. It combines Smart Money Concepts (SMC) pattern detection with an AI regime classifier backed by a 7-agent Claude debate pipeline. The system has been validated across 10 sprints of walk-forward out-of-sample backtesting and runs as a live paper trading loop on a Windows VPS.

## Commands

### Setup
```bash
# Install (Windows with MT5)
pip install -e ".[mt5,dev]"

# Install (macOS/Linux dev — no MT5)
pip install -e ".[dev]"
```

### Testing
```bash
pytest                                             # all tests
pytest tests/smc/unit/ai/                         # single module
pytest -m unit                                     # fast, no IO
pytest -m integration                              # may touch disk/network
pytest -m "not mt5"                                # skip Windows-only tests
pytest --cov=smc --cov-report=term-missing         # with coverage (80% minimum)
```

### Linting & Type Checking
```bash
ruff check src tests
ruff format src tests
mypy src
```

### Backtesting
```bash
# Single OOS window (window 1 = Jan–Apr 2021 test period)
python scripts/run_v7_single_window.py 1

# With AI regime debate enabled
python scripts/run_v7_single_window.py 1 --ai-regime
```

### Live Trading (Windows VPS with MT5)
```bash
# Automated launch (production)
.\scripts\start_live.bat

# Manual
python scripts/live_demo.py
```

### CLI
```bash
smc ingest --instrument XAUUSD --start 2020-01-01 --end 2025-01-01
smc detect --timeframe H1
smc backtest --config config/smc_config.yaml
smc health
smc live --mode demo
```

## Architecture

### Data Flow (Top-Down)

```
ForexDataLake (Parquet D1/H4/H1/M15)
    ↓
SMCDetector (6 sub-detectors: swing, OB, FVG, BOS/CHoCH, liquidity, synthetic_zones)
    ↓
AI Regime Classifier (7-agent Claude debate → ATR fallback → TRANSITION default)
    ↓
MultiTimeframeAggregator (D1→H4 HTF bias → H1 zones → M15 entry triggers)
    ↓
Confluence Scoring (5 factors, threshold 0.45)
    ↓
RiskManager (1% equity sizing, 3%/10% circuit breakers)
    ↓
MT5Executor / SimBrokerPort → LiveLoop (M15 bar-close polling)
```

### Key Modules (`src/smc/`)

| Module | Purpose |
|--------|---------|
| `config.py` | `SMCConfig` — all settings via `SMC_*` env vars (pydantic-settings) |
| `smc_core/` | 6 SMC pattern detectors: swing, order_block, fvg, structure (BOS/CHoCH), liquidity, synthetic_zones |
| `strategy/aggregator.py` | Multi-TF coordinator; `aggregator_v1_1.py` is current production version |
| `strategy/confluence.py` | Weighted scoring engine — setup passes if score ≥ `min_confluence_score` |
| `strategy/entry_trigger.py` | Entry signals: FVG fill, liquidity sweep, OB retest (OB retest disabled — 18.2% WR) |
| `ai/regime_classifier.py` | Extracts `RegimeContext` features, runs AI debate or ATR fallback |
| `ai/debate/pipeline.py` | 7-agent pipeline: 4 Analysts (Sonnet) → Bull/Bear Researchers → Judge (Opus) |
| `ai/param_router.py` | Maps 5 regimes to ATR multipliers, TP ratios, and max hold times |
| `execution/reconciler.py` | Syncs Python logical positions with MT5 physical positions after disconnects |
| `execution/mt5_send.py` | Dynamic deviation slippage + circuit breaker for consecutive requotes |
| `monitor/live_loop.py` | Async M15-bar-close driven main loop; single concurrent cycle enforced |
| `monitor/state_io.py` | Atomic write for live state persistence (survives VPS power loss) |
| `backtest/walk_forward.py` | 12-month train / 3-month test / 3-month step; no-lookahead guarantee |

### 5 AI Market Regimes
`TREND_UP` | `TREND_DOWN` | `CONSOLIDATION` | `TRANSITION` | `ATH_BREAKOUT`

Each regime routes to a different parameter preset via `ai/param_router.py`.

### Versioned Aggregators
- `aggregator.py` — v1 baseline
- `aggregator_v2.py` — v2 ATR-SL
- `aggregator_v3.py` — v3 hybrid
- `aggregator_v1_1.py` — **current production** (v1.1 with inversion fixes)

## Configuration

### Environment Variables
All settings use `SMC_` prefix. Copy `.env.example` → `.env`:

```ini
SMC_ENV=paper              # dev | paper | live
SMC_MT5_MOCK=1             # 1 on macOS/Linux, 0 on Windows VPS
SMC_AI_ENABLED=1           # global kill switch for all Claude/API calls
SMC_AI_REGIME_ENABLED=0    # enable 7-agent debate (expensive)
SMC_AI_DEBATE_ROUNDS=1     # 1 = halve Opus calls (bull+bear x1)
```

Key feature flags (all default `False` — must opt-in):
- `SMC_AI_MODE_ROUTER_ENABLED` — AI-aware trending/ranging mode routing
- `SMC_RANGE_TREND_FILTER_ENABLED` — D1 SMA50 slope filter for range trades
- `SMC_RANGE_AI_REGIME_GATE_ENABLED` — per-direction gating via AI regime
- `SMC_SL_FITNESS_JUDGE_ENABLED` — shadow-mode SL fitness veto (telemetry only)
- `SMC_SYNTHETIC_ZONES_ENABLED` — augment with synthetic zones during ATH regimes
- `SMC_MACRO_ENABLED` — COT/TIPS/DXY macro overlay
- `SMC_RANGE_REVERSAL_CONFIRM_ENABLED` — require bar confirmation for range reversals

### Risk Constants (never change without backtest validation)
- 1% equity per trade (`risk_per_trade_pct`)
- 3% daily loss halt (`max_daily_loss_pct`)
- 10% drawdown halt (`max_drawdown_pct`)
- `max_lot_size = 0.01` hard cap

### Dual-Magic A/B Testing
Control leg uses instrument magic (XAU=19760418), treatment leg uses `SMC_MACRO_MAGIC` (default 19760428). `SMC_JOURNAL_SUFFIX` separates journal files. `SMC_VIRTUAL_BALANCE_SPLIT` (JSON) splits account equity between legs.

## Testing Structure

```
tests/smc/
├── unit/           # fast, no IO — per-module (ai, backtest, data, execution, monitor, risk, smc_core, strategy)
├── integration/    # may touch disk/network (pipeline, CLI, live demo, dual-magic)
└── conftest.py
```

Pytest markers: `unit`, `integration`, `mt5` (Windows only), `slow` (>10s backtest runs).

Property-based tests use `hypothesis`. Coverage minimum is 80% (`fail_under = 80` in pyproject.toml).

## Key Constraints

- **MT5 is Windows-only** — use `SMC_MT5_MOCK=1` on macOS/Linux; `SimBrokerPort` replaces `MT5BrokerPort`
- **`enable_ob_test_trigger` is permanently `False`** — disabled in Sprint 5 due to 18.2% WR; do not re-enable without OOS validation
- **Live loop is deliberately single-concurrent** — one cycle per M15 bar close; do not parallelize trading logic
- **Feature flags are opt-in** — all new gating flags default `False` to preserve production behavior; validate via backtest before enabling
- **Walk-forward OOS** — backtests must use `run_v{N}_single_window.py` with proper train/test windows; no in-sample validation
- **Atomic state writes** — `monitor/state_io.py` uses atomic rename pattern; never write `live_state.json` directly

## Data Paths

```
data/
├── parquet/                  # XAUUSD D1/H4/H1/M15 Parquet lake
├── XAUUSD/
│   ├── journal/              # live trade journal JSONL (+ journal_macro/ for treatment leg)
│   ├── live_state.json       # persisted loop state (atomic writes)
│   └── regime_cache.parquet  # pre-computed AI regimes for backtest
├── gate1_v{N}_windows.jsonl  # OOS backtest results per sprint version
└── worst_indicator_matrix.json
```
