# MQ4 SMC OB/FVG 质量体系中等改造设计

日期：2026-06-15

## 背景

目标文件是 `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`。当前指标已经具备摆点过滤、BOS/CHOCH、FVG、OB、OB 生命周期雏形和图形绘制能力，但 OB 区域的质量表达不足：

- `EnableOBLifecycle` 默认关闭，OB 多数情况下仍按传统 `is_mitigated` 布尔状态显示。
- OB 的“首次触及”“多次触及”“反向破坏”“确认失效”没有成为主路径。
- OB 与同向 FVG 重叠没有被评分和高亮，无法体现更高质量的机构足迹区。
- SMC 参数数量较多，部分参数用于调试或兼容旧逻辑，默认暴露会增加使用成本。

本设计采用“中等改造”：不重写全部 SMC/ICT 检测算法，不改变现有 BOS/CHOCH 和摆点主流程，只增强 OB 生命周期、OB/FVG 重叠评分和参数分层。

## 目标

1. 将 OB 生命周期升级为默认主逻辑，允许 `EnableOBLifecycle` 默认改为 `true`。
2. 让 OB 的状态从简单触及升级为可解释的质量状态：Fresh、Tested、Weakened、Broken_Once、Invalid。
3. 增加 OB/FVG 同向价格重叠识别，并将其纳入 OB 质量评分。
4. 在图表标签中显示 OB 等级和是否与 FVG 重叠，例如 `Bullish OB+FVG [A]`。
5. 精简用户常用参数，保留高级参数但降低默认可见/默认干扰。
6. 保持 EA 兼容性：不改变现有 indicator buffer 索引 0–8 的语义。
7. 新增一个 `OB_Quality` 数据 buffer（索引 9），作为未来 EA 读取 OB 质量分的预留机器可读通道；本阶段一次接到位，避免后续遗忘。

## 非目标

- 不把 Python 版 `smartmoneyconcepts` 直接移植到 MQ4。
- 不改写 ZigZag/缠论摆点过滤主算法。
- 不重构全部绘图系统。
- 不新增外部 Python 服务或 MT4-Python 通信。
- 不在本阶段实现 EQH/EQL、liquidity sweep 或多周期级联。
- 不在本阶段编写消费 `OB_Quality` buffer 的 EA；只把通道接好并验证可被 `iCustom` 读取。

## 当前代码边界

主要涉及函数：

- `POI_Zone` 结构体：增加 OB 质量和重叠字段。
- `AddPOIZone`：初始化新增字段。
- `IdentifyOrderBlocks`：继续负责发现 OB，不扩大检测范围。
- `UpdatePOIStatus`：继续分发 FVG、OB 状态更新。
- `ProcessOBLifecycle`：升级为 OB 主状态机。
- `ShouldSkipOB`：根据 OB 状态决定隐藏或显示。
- `GetOBDisplayColor`、`GetOBDisplayLabel`、`GetOBLevelName`：输出状态、等级和重叠信息。
- `DrawGraphicalObjects`：统计和绘制 OB 质量信息。
- 新增 `RefreshOBFVGConfluence`、`CalculateOBQualityScore`、`GetOBGradeLabel`、`GetOBFVGOverlapRatio`。
- `OnInit`：`indicator_buffers` 9→10，新增 `SetIndexBuffer(9, OB_Quality)` 与 `SetIndexStyle(9, DRAW_NONE)`。
- 绘图/buffer 更新阶段：新增 `WriteOBQualityBuffer`（或在现有 buffer 更新处内联），把锚点 `quality_score` 写入 `OB_Quality`。

## OB 状态机设计

### 状态定义

- `0 Fresh`：新形成 OB，未被有效触及。最高质量。
- `1 Tested`：首次有效触及，但没有被反向破坏。仍可交易，质量略降。
- `2 Weakened`：多次有效触及。保留显示，但不作为强区。
- `3 Broken_Once`：首次反向收盘破坏 OB 边界。进入观察状态，不能再按强区看待。
- `4 Invalid`：进入 `Broken_Once` 后再次反向破坏，且在需要时满足动能确认。默认灰显；当 `RemoveInvalidOB=true` 时隐藏。

### 有效触及

触及条件沿用当前区域重叠判断：

```text
price_in_zone = low[current_bar] <= ob.top_price && high[current_bar] >= ob.bottom_price
```

触及计数必须经过 `OBCooldownBars` 冷却，避免同一次横盘震荡重复累计。

### 反向破坏

多头 OB 的反向破坏：

```text
close[current_bar] < ob.bottom_price
```

空头 OB 的反向破坏：

```text
close[current_bar] > ob.top_price
```

如果 `RequireMomentumOnBreak=true`，反向破坏需要满足：

```text
abs(close - open) / ATR >= BreakMomentumATR
```

### 状态转移

```text
Fresh -> Tested
  条件：首次有效触及

Fresh -> Broken_Once
  条件：未经任何有效触及即被反向收盘击穿
  说明：同一根 K 线先判断 price_in_zone 触及；若不构成触及，再判断反向破坏

Tested -> Weakened
  条件：冷却后再次有效触及

Tested/Weakened -> Broken_Once
  条件：首次反向收盘破坏

Broken_Once -> Weakened
  条件：价格重新收回 OB 区间，视为假突破复活

Broken_Once -> Invalid
  条件：再次反向收盘破坏；若 RequireMomentumOnBreak=true，则该次破坏还必须满足 BreakMomentumATR
```

新增分支说明（修订 2）：原状态机的 `Fresh` 只处理触及，不处理直接被击穿，导致一根大 K 线收盘贯穿 OB 却仍标记为 Fresh（最高质量）的鬼区。新增 `Fresh -> Broken_Once` 填补此空隙，转移时记录 `first_break_bar`、`break_momentum`。

关键修正（修订 1，对应现有代码 bug）：现有 `ProcessOBLifecycle` 的 case 3（`Broken_Once -> Invalid`）方向写反——对多头 OB 它要求 `close > top_price`（向上突破）才确认失效。必须改为：`Broken_Once -> Invalid` 使用“反向破坏方向”确认。多头 OB 失效看向下破底（`close < bottom_price`），空头 OB 失效看向上破顶（`close > top_price`）；不能用顺向突破确认失效。调试日志输出本次破坏的实际方向。

## OB/FVG 重叠评分设计

### 重叠条件

只统计同向重叠：

- Bullish OB 只与 Bullish FVG 重叠。
- Bearish OB 只与 Bearish FVG 重叠。
- 已完全触及的 FVG 本阶段不参与加分，即使 `ShowMitigatedPOI=true` 也只作为历史显示，不提高 OB 质量分。

价格区间重叠：

```text
overlap_low  = max(ob.bottom_price, fvg.bottom_price)
overlap_high = min(ob.top_price, fvg.top_price)
has_overlap  = overlap_high > overlap_low
```

重叠比例以 OB 宽度为分母：

```text
overlap_ratio = (overlap_high - overlap_low) / (ob.top_price - ob.bottom_price)
```

### 评分公式

基础分按 OB 状态：

- Fresh：0.80
- Tested：0.65
- Weakened：0.45
- Broken_Once：0.20
- Invalid：0.00

加分项：

- 同向 FVG 重叠：+0.15
- `overlap_ratio >= MinOBFVGOverlapRatio`：额外 +0.05
- 与当前趋势方向一致：+0.05

最终分数：

```text
quality_score = min(1.0, max(0.0, base + bonuses))
```

等级：

- `A`：score >= 0.80
- `B`：score >= 0.60
- `C`：score >= 0.40
- `D`：score > 0.00
- `X`：score == 0.00

## 数据结构变更

`POI_Zone` 增加字段：

```mql4
bool   has_fvg_overlap;
int    overlap_fvg_bar;
double overlap_ratio;
double quality_score;
string quality_grade;
```

初始化规则：

- FVG：字段保留默认值，不用于评分。
- OB：创建时默认 `has_fvg_overlap=false`、`overlap_fvg_bar=-1`、`overlap_ratio=0.0`、`quality_score=0.0`、`quality_grade="D"`，随后由刷新函数计算。

## OB_Quality buffer（EA 预留通道）

为未来 EA 通过 `iCustom` 读取 OB 质量分预留一个机器可读通道。本阶段一次接到位。

- `#property indicator_buffers` 由 9 改为 10。
- 在 `OnInit` 中 `SetIndexBuffer(9, OB_Quality)`，并 `SetIndexStyle(9, DRAW_NONE)`（纯数据，不画线，不占图层）。
- 现有索引 0–8（`BOS_Top`/`BOS_Bottom`/`CHOCH_Top`/`CHOCH_Bottom`/`FVG_Top`/`FVG_Bottom`/`OB_Top`/`OB_Bottom`/`MA21_Buffer`）的索引号和语义全部不变。
- 写入时机：在 OB 评分刷新（`RefreshOBFVGConfluence` / `CalculateOBQualityScore`）之后、绘图阶段，将每个 OB 的 `quality_score`（0.0–1.0）写入该 OB 锚点 K 线索引位置；其余 bar 写 `EMPTY_VALUE`。
- 每轮计算前先把可计算区间的 `OB_Quality` 重置为 `EMPTY_VALUE`，避免旧锚点残留。
- 若同一锚点 K 线索引存在多个 OB（极少见），写入其中 `quality_score` 最高者。
- EA 读取约定：`iCustom(Symbol(), Period(), "SMC_OrderFlow_Indicator_v1.70_zig", <参数...>, 9, shift)`，得到该 bar 的 OB 质量分；A/B/C/D 等级由 EA 端按本设计的阈值自行换算，不再单独开 buffer。
- 等级（grade）与 `+FVG` 标记不单独占 buffer：等级可由分数阈值还原，`+FVG` 的贡献已折进分数。

## 参数精简设计

### 常用参数保留

这些参数保留为主要用户配置：

- `StructureLookback`
- `MaxBarsToCalculate`
- `MaxFVGZones`
- `MaxOBZones`
- `ShowBOS`
- `ShowCHOCH`
- `ShowFVG`
- `ShowOrderBlocks`
- `ShowMitigatedPOI`
- `EnableOBLifecycle`
- `OBCooldownBars`
- `RequireMomentumOnBreak`
- `BreakMomentumATR`
- `RemoveInvalidOB`
- `EnableZigZagFilter`
- `EnableChanOptimization`

### 默认值调整

- `EnableOBLifecycle = true`
- `ShowOBStatusInfo = true`
- `ShowOBLifecycleInfo = false`
- `EnableOBDebug = false`
- `ForceOBRedraw = false`
- `RemoveInvalidOB = false`

### 新增参数

```mql4
extern bool   EnableOBFVGConfluence    = true;
extern double MinOBFVGOverlapRatio     = 0.20;
extern bool   ShowOBQualityGrade       = true;
extern bool   HideLowQualityOB         = false;
extern double MinVisibleOBQualityScore = 0.20;
```

### 高级参数降噪

以下参数继续保留，但建议在代码注释中标记为“高级/调试”，默认不鼓励普通用户调整：

- `EnableOBDebug`
- `ForceOBRedraw`
- `ShowOBLifecycleInfo`
- `DebugBOSCHOCH`
- `DebugTrendChange`
- `ShowChanFractals`
- `EnableVirtualSwingExtension`
- `ShowTemporaryExtreme`

MQ4 不能真正折叠 extern 参数，因此“精简”的落地方式是重排参数区块、优化注释、把默认值调成稳定组合，并减少普通用户必须理解的开关。

## 显示设计

OB 标签：

- Fresh 且重叠：`Bullish OB+FVG [A]`
- Fresh 无重叠：`Bullish OB [B]`
- Tested：`Bullish OB Tested [B]`
- Weakened：`Bullish OB Weak [C]`
- Broken_Once：`Bullish OB Watch [D]`
- Invalid：`Bullish OB Invalid [X]`

颜色：

- Fresh：沿用原有多空 OB 色。
- Tested：原色略暗。
- Weakened：更暗。
- Broken_Once：警戒色。
- Invalid：灰色。
- OB+FVG：保持同方向颜色，但标签体现 `+FVG`；不额外新增对象类型，避免对象命名和 EA 读取复杂化。

## 数据刷新顺序

每轮计算中保持现有流程：

1. 识别 Swing。
2. 识别 BOS/CHOCH。
3. 识别 FVG。
4. 识别 OB。
5. 更新 FVG/OB 状态。
6. 刷新 OB/FVG 重叠和 OB 评分。
7. 更新 buffer（含把每个 OB 的 `quality_score` 写入 `OB_Quality` 锚点位置，其余 bar 重置为 `EMPTY_VALUE`）。
8. 绘图。

如果同一轮中先发现 OB 后发现 FVG，评分刷新函数仍会扫描全量 `poi_zones`，确保最终状态一致。

## 兼容性

- 不改变 `BOS_Top`、`BOS_Bottom`、`CHOCH_Top`、`CHOCH_Bottom`、`FVG_Top`、`FVG_Bottom`、`OB_Top`、`OB_Bottom`、`MA21_Buffer`（索引 0–8）的 buffer 编号与语义。
- 仅在末尾追加 `OB_Quality`（索引 9），`indicator_buffers` 9 → 10；不影响任何现有索引。该 buffer 为 `DRAW_NONE` 纯数据通道。
- 不修改现有 `poi_type`：`0=FVG`、`1=OrderBlock`。
- 不将 OB+FVG 作为第三种 `poi_type`，避免破坏旧逻辑。
- `is_mitigated` 对 FVG 继续有效；对 OB 仅作为旧模式兼容字段。

## 测试与验收

手工回放验收：

1. 新 OB 创建后显示为 Fresh，并给出 A/B/C/D 等级。
2. 第一次回踩 OB 后从 Fresh 转为 Tested。
3. 多次回踩后转为 Weakened。
4. 多头 OB 被收盘向下破底后转为 Broken_Once；空头 OB 被收盘向上破顶后转为 Broken_Once。
4b. Fresh OB 未经任何触及即被反向收盘击穿时，直接转为 Broken_Once（验证修订 2，不再永久停留 Fresh）。
4c. 多头 OB 在 Broken_Once 后再次向下破底才转 Invalid；向上顺向突破不触发 Invalid（验证修订 1 方向修复）。
5. Broken_Once 后再次反向破坏转为 Invalid；若 `RequireMomentumOnBreak=true`，第二次破坏必须满足 `BreakMomentumATR`。
6. OB 与同向 FVG 有价格重叠时标签显示 `OB+FVG`，评分提升。
7. 异向 FVG 不给 OB 加分。
8. `RemoveInvalidOB=false` 时失效 OB 灰显；`true` 时隐藏。
9. `HideLowQualityOB=true` 时低于 `MinVisibleOBQualityScore` 的 OB 不绘制。
10. 现有 BOS/CHOCH/FVG/OB buffers（索引 0–8）仍能被 EA 按原编号读取。
11. `OB_Quality`（索引 9）能被 `iCustom(...,9,shift)` 读到 OB 锚点处的 `quality_score`，非锚点 bar 返回 `EMPTY_VALUE`。

日志验收：

- `EnableOBDebug=true` 时输出状态转移、评分和重叠信息。
- 默认参数下不刷屏。

性能验收：

- 在 `MaxBarsToCalculate=1000`、`MaxFVGZones=5`、`MaxOBZones=5` 默认配置下，OB/FVG 重叠扫描最多是小数组 O(n*m)，不会成为性能瓶颈。

## 风险与缓解

风险：默认开启 OB 生命周期可能改变用户看到的 OB 数量和颜色。  
缓解：保留 `EnableOBLifecycle=false` 可回退旧行为。

风险：OB/FVG 重叠评分可能让标签变化更频繁。  
缓解：只在 `g_data_version` 变化或强制刷新时重绘，沿用现有绘图节流。

风险：新增参数继续增加 extern 数量。  
缓解：新增参数控制在 5 个以内，并通过重排参数区块减少常用配置负担。

风险：Invalid 判断方向错误会误删有效 OB。  
缓解：明确多头 OB 看向下破底、空头 OB 看向上破顶，并在调试日志中输出破坏方向。

## 实施顺序

1. 调整参数默认值和参数区块注释。
2. 扩展 `POI_Zone` 字段并初始化。
3. 修正 `ProcessOBLifecycle` 的 Invalid 方向 bug（修订 1），并新增 `Fresh -> Broken_Once` 分支（修订 2）。
4. 新增 OB/FVG 重叠扫描和评分函数。
5. 接入绘图标签、颜色、跳过逻辑。
6. 新增 `OB_Quality` buffer（`indicator_buffers` 9→10、`SetIndexBuffer(9,...)`、`DRAW_NONE`），在评分后写入锚点分数。
7. 手工编译 MQ4，修复语法和类型问题。
8. 用历史图表回放验证状态转移和显示结果，并用一个最小测试脚本 `iCustom(...,9,shift)` 验证 `OB_Quality` 可被读取。

## 成功标准

本设计完成后，MQ4 指标应能在不破坏现有 BOS/CHOCH/FVG/OB 输出的前提下，更清楚地区分：

- 哪些 OB 是新鲜强区。
- 哪些 OB 已经被多次测试、质量下降。
- 哪些 OB 已经失效。
- 哪些 OB 因为与同向 FVG 重叠而质量更高。

普通用户使用默认参数即可获得更稳定的结构质量；高级用户仍可通过参数回退旧逻辑或打开调试。
