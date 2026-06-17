# MQ4 SMC 结构分支重定义 · BOS/CHoCH(标准化重写)设计

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`
更新日期:2026-06-17
取代:`docs/superpowers/specs/2026-06-17-mq4-smc-bos-choch-alignment-design.md`(浅层版,作废)
定义参照:`smartmoneyconcepts.bos_choch` / `dashboard/chart.html`(仅作 SMC 定义参照,非输出目标)

---

## 1. 背景与架构出发点(用户确立)

指标采用**一套摆点 + 两个分支**架构:

```
        统一摆点层(缠论笔端点已规范且完美,既是SMC摆点)  ← 固定,不动
       /                                              \
  缠论体系(笔→中枢→买卖点)              SMC体系(FVG/iFVG, OB, BOS/CHoCH)
```

两分支仅共享摆点,互不影响。当前 `DetectStructureBreaks` 把 SMC 的 BOS/CHoCH 与**趋势门控、位移、FVG 要求、MA21、受保护摆点 gate** 耦在一起,偏离了 SMC 的标准定义。本次**重写 SMC 结构分支**,在固定摆点上忠实实现 SMC 标准 BOS/CHoCH。

**成功标准 = 符合 SMC BOS/CHoCH 规范**(§3 规则),**可**与 chart.html 输出不同(因摆点不同),chart.html 仅作定义参照。

## 2. 硬约束:缠论体系零影响(隔离原则)

新 SMC 结构检测器:
- **只读** `swing_points[]`,**不修改**任何摆点字段(尤其 `is_broken`;如需"已破"标记,用 SMC 私有数组/字段)。
- **不写** `g_market_trend` 及趋势引擎(`UpdateTrendSequenceTracking`/`UpdateTrendStateMachine`)、缠论分型/笔/中枢相关全局、`g_last_break_up_bar/down_bar`、`g_choch_*_occurred_*`。
- **只写** `structure_zones[]`(SMC BOS/CHoCH 显示输出)及检测器自身内部状态。
- 实现前需核对:列出缠论分支实际读取的全局,确保新检测器都不写它们(plan 第一步做依赖核对)。

## 3. 标准 SMC BOS/CHoCH 定义(将实现的规则)

在固定 `swing_points[]`(已分类 HH=0/HL=1/LH=2/LL=3)上,维护 SMC 私有 **bias 状态机**:

**状态**:`smc_bias ∈ {0=中性, 1=上升, -1=下降}`;参照位 `ref_high`(最近被保护摆高)、`ref_low`(最近被保护摆低)。

**逐 bar 收盘破位判定**(`ConfirmBreakClose=true` 用收盘,否则用 high/low):
- **close > `ref_high`**:
  - `smc_bias ∈ {1, 0}` → **BOS↑**(顺势延续)
  - `smc_bias == -1` → **CHoCH↑**(反转)→ `smc_bias = 1`
- **close < `ref_low`**:
  - `smc_bias ∈ {-1, 0}` → **BOS↓**
  - `smc_bias == 1` → **CHoCH↓** → `smc_bias = -1`

**破位后更新参照位**:
- 上升 bias:`ref_high` = 新形成的摆高(HH),`ref_low` = 最近 HL(被保护低点)。
- 下降 bias:`ref_low` = 新摆低(LL),`ref_high` = 最近 LH(被保护高点)。

**自然性质**:bias 在 CHoCH 翻转 → 每段趋势"首次逆势破位=CHoCH,之后同向破位=BOS"自动成立,无需单独唯一性标志。

**事件记录**:每次破位 `AddStructureZone(break_bar, ref_price, is_bullish, type, swing_bar)`,`type` 0=BOS/1=CHoCH;`break_bar`=收盘破位确认的 bar(≈标准 BrokenIndex);`ref_price`/`swing_bar`=被破摆点。

## 4. 去掉 / 保留

| 项 | 处置 | 理由 |
|----|------|------|
| `RequireDisplacement`(位移) | SMC 结构**不再使用** | 标准 BOS/CHoCH 无位移要求 |
| `RequireFVG_BOS` / `RequireFVG_CHOCH` | SMC 结构**不再使用** | 标准无 FVG 要求 |
| 结构层 MA21 过滤 | SMC 结构**不使用**(MA21 仍属缠论摆点层,不动) | 标准无均线门控 |
| 受保护摆点 **gate** | 改为**参照位**(CHoCH 的 ref),非阻断 | 标准里它就是 CHoCH 参照 |
| 收盘确认 `ConfirmBreakClose` | **保留** | 标准用收盘确认 |
| 最近 HL/LH 作 CHoCH 参照 | **保留** | 标准定义 |

> 上述 `Require*` 参数若仅 SMC 结构使用,则在 SMC 路径中忽略;参数本身保留(供回退/其它路径),标注"SMC结构已不使用"。

## 5. 显示

- **修虚线 bug**:`DrawStructureZone` 当前把样式设在 `if(ObjectCreate())` 内,已存在对象不会被重设。改为:无论新建/已存在都执行 `ObjectSetInteger(...OBJPROP_STYLE...)`(或重绘前先 `ObjectDelete`)。
- **线型**:BOS = `STYLE_DASH`,CHoCH = `STYLE_SOLID`。
- 标签 `BOS↑/↓`、`CHOCH↑/↓` 方向箭头保留。

## 6. 验证

- **主(SMC 规范符合性)**:固定样本手工核对——
  1. 上升段收盘破前摆高 → BOS↑;
  2. 上升段首次收盘破被保护 HL → CHoCH↓(且 bias 翻转下降);
  3. 反转后顺势破 → BOS;
  4. 不应出现"同段连续多个同向 CHoCH"。
- **辅(参照)**:chart.html 看趋势/方向是否同向(数量/位置可不同)。
- **隔离回归**:对照重写前后,确认缠论摆点/笔/分型显示**完全不变**(截图比对)。
- 编译 0 errors。

## 7. 文件 / 兼容性 / 路线图

- 在 `v1.72` 实现;v1.71 保留回退。缓冲区 0–9 布局不变。
- 取代浅层 Phase 2。属路线图**子项目 A**;后续:**B. SMC iFVG**、**C. 缠论中枢→买卖点**(各自独立 spec)。

## 8. 风险

- 新检测器若误写了缠论依赖的全局 → 破坏笔。**缓解**:plan 第一步做全局依赖核对 + §6 隔离回归截图比对。
- bias 初始(数据最左端 `smc_bias=0`):首个破位按"中性→BOS"处理,符合"无前趋势时首破记为 BOS"的直觉。
