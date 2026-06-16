# MQ4 SMC 指标对齐标准 · Phase 1(FVG + OB)设计

适用文件:新建 `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(从 v1.70 演进)
基线参照:Python `src/smc/smc_core/`(基于 `smartmoneyconcepts` 库)+ `dashboard/chart.html`
更新日期:2026-06-16
相关:v1.70 OB/FVG 质量升级 `docs/SMC指标_OB质量升级_使用说明.md`

---

## 1. 背景与目标

项目内存在两套 SMC 引擎:

| 引擎 | OB 是否结构化 | FVG 是否部分填充 | 角色 |
|------|----------|----------|------|
| **Python `smc_core`**(→ chart.html) | ✅ 是(基于 smartmoneyconcepts,绑定摆点结构) | ✅ 是(`filled_pct`) | 生产 + 事实标准 |
| **MQL4 指标 v1.70** | ❌ 否(纯 K 线机械判断) | ❌ 只判全填、且过滤过严 | 手动看盘 — 偏离标准的那个 |

**目标**:在不改动已通过 walk-forward 验证的 Python 生产逻辑前提下,把 MQL4 指标的 **FVG 与 OB** 的检测、失效口径、展示对齐到 Python/标准,新文件为 `v1.71`。BOS/CHoCH 留待 Phase 2。

**方案选型**:采用"务实混合"(Approach C)——保留 MT4 现有的缠论/ZigZag 摆点 + BOS/CHoCH 结构引擎(比标准库更丰富),只让 FVG/OB 的**语义**对齐标准,不去逐字节复刻另一套库的摆点算法(那种"精确一致"是假象)。

---

## 2. 标准参照(Python/smartmoneyconcepts 口径)

来自 `src/smc/smc_core/fvg.py` 与 `order_block.py`:

- **FVG 几何**:多头 `low[i+1] > high[i-1]`,zone = `[high[i-1], low[i+1]]`;只要求**中间 K 线**方向(`close>open`),**不**要求第三根延续;**无** ATR / 折溢价过滤;`join_consecutive` 合并相邻同向缺口。
- **FVG 填充**:按渗透深度累计 `filled_pct`(单调不减),达 100% 为 `fully_filled`。
  - 多头:`pct = (high - max(bar_low, low)) / (high - low)`
  - 空头:`pct = (min(bar_high, high) - low) / (high - low)`
- **OB**:结构化(由 `swing_highs_lows` 推导),失效 = 影线击穿远端边界:
  - 多头 OB:`bar_low < ob.low` → mitigated
  - 空头 OB:`bar_high > ob.high` → mitigated

---

## 3. 关键现状代码事实(实现前必须知道)

- 主循环顺序(`SMC_OrderFlow_Indicator_v1.70_zig.mq4` ~1685–1733):默认 `EnableChanOptimization`/`EnableZigZagFilter` 开启时,**BOS/CHoCH 检测在主循环之后**(1721–1733)才执行;而 `IdentifyOrderBlocks` 在主循环**内**(1705)就跑了。
- 后果:`g_last_break_up_bar`/`g_last_break_down_bar` 在识别 OB 时尚未设置,且只记录"最近一个"突破 bar。因此现有 `OB_OnlyDrive=true` 在默认路径下**不可靠**。
- 结论:OB 结构化**不能**靠翻 `OB_OnlyDrive` 开关,必须改时序——在结构最终确定后,遍历 `structure_zones[]`(已含每个突破的 `start_bar`、`is_bullish`、`structure_type`)生成 OB。
- 缓冲区布局:index 0–9 已定(`0/1`BOS、`2/3`CHoCH、`4/5`FVG、`6/7`OB、`8`MA21、`9`OB_Quality)。Phase 1 **不改布局**。
- `AddPOIZone(start_bar, price1, price2, is_bullish, poi_type)`,`poi_type` 0=FVG/1=OB;`POI_Zone` 已含质量评分字段(`quality_score`/`quality_grade`/`has_fvg_overlap` 等)。实现时需确认 top/bottom 归一化(`top_price ≥ bottom_price`)。

---

## 4. 设计

### 4.1 文件与版本策略
- 从 v1.70 复制出 `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`,所有改动只在 v1.71;v1.70 保持不动作为回退基线。
- 更新 `#property version` 与指标短名(影响 `iCustom` 名称);保持缓冲区 0–9 布局不变。
- 所有新行为有参数开关,**默认值 = 标准对齐后的行为**。

### 4.2 FVG 对齐
1. **放宽检测**:`IdentifyFVG` 去掉第三根延续条件(多头 `close[cb] > close[cb+1]`、空头对称),仅保留中间 K 线方向。
2. **过滤默认关闭**:v1.71 默认 `FVGQualityThreshold = 0.0`、`UsePremiumDiscount = false`。
3. **部分填充(新)**:`POI_Zone` 增加 `fill_pct` 字段;重写 `ProcessFVGStatus` 按 §2 口径累计渗透深度(单调不减);`fill_pct ≥ FVGMitigationThreshold`(新参数,默认 1.0)即视为已填充并隐藏。设 0.5 = 半填充口径。
4. **合并连续缺口(可选)**:`FVG_JoinConsecutive`(默认 true)——新增 FVG 与已存在同向、价格重叠的 FVG 合并为更宽区域。

### 4.3 OB 对齐(含时序重构)
1. **新通道**:新增 `IdentifyOrderBlocksFromStructure()`,在结构检测最终完成后(主循环后、`TrimStructureZonesToNewest` 前后合适位置)执行;**不再**在主循环内调用旧 `IdentifyOrderBlocks`。
2. **逻辑**:遍历最终 `structure_zones[]`,对每个突破事件,向其 `start_bar` 前回溯(沿用现有 5 根窗口,与旧 `IdentifyOrderBlocks` 一致)找紧邻反向 K 线作为 OB(多头突破→突破前最后一根阴线;空头对称),`AddPOIZone(..., poi_type=1)`。
3. **结果**:OB 天然只在真实结构突破处产生,从根本上消除截图中"一堆 OB 挤在一起"。
4. **失效口径对齐标准**:OB 失效/隐藏判定改用**影线击穿远端边界**(多头 `low < ob.low`、空头 `high > ob.high`),硬编码,不新增开关。现有 5 状态生命周期保留作为增强展示,但"失效"以此标准口径为准。
5. **旧路径**:`IdentifyOrderBlocks` 与 `OB_OnlyDrive` 保留代码但默认不走;`OB_OnlyDrive` 标注废弃。

### 4.4 展示降噪(对齐 chart.html 观感)
1. **默认隐藏**已全填 FVG(`fill_pct ≥ FVGMitigationThreshold`)与已失效 OB。
2. FVG 标签显示 `FVG nn%`(填充百分比)。
3. **标签防重叠**:锚点价位接近时垂直错位;同价位多区域只保留 `quality_score` 最高者的标签。
4. `HideLowQualityOB`(已有)保留为进一步精简手段。

### 4.5 验证方式(无需 MT4 导出桥)
- 打开 `dashboard/chart.html`(Python 标准),选相同 symbol/TF,与 MT4 v1.71 **肉眼对照**:FVG/OB 的位置、方向、数量级、填充/失效状态是否一致。
- 固定**核对清单样本**:干净多头 FVG、第三根暂停的 FVG、有 BOS 的 OB、无 BOS 的大阳线 —— 逐条确认 v1.71 标对/标错。
- 验收标准:MetaEditor 编译 0 错误 + 对照清单全部通过。

---

## 5. 参数变更清单

### A. 新增对齐参数(仅 2 个)
| 参数 | 类型 | 默认 | 作用 |
|------|------|------|------|
| `FVGMitigationThreshold` | double | `1.0` | FVG 填充达此比例即隐藏;`0.5`=半填充口径 |
| `FVG_JoinConsecutive` | bool | `true` | 合并相邻同向、价格重叠的 FVG |

### B. 旧参数改默认值
| 参数 | v1.70 | v1.71 | 说明 |
|------|------|------|------|
| `FVGQualityThreshold` | `0.05` | `0.0` | 关闭 ATR 质量过滤(标准库无) |
| `UsePremiumDiscount` | `false` | `false` | 维持关闭(本就 opt-in) |

### C. 废弃 / 计划冻结
| 参数 | 阶段1 处置 | 原因 |
|------|-----------|------|
| `OB_OnlyDrive` | 废弃→内部常量 | 被结构化 OB 通道取代 |
| `RequireMomentumOnBreak` / `BreakMomentumATR` | 标注 deprecated | 失效改影线口径,动能 K 线不再主导 |
| `PreferGolden62` | 标注 deprecated | 标准库无折溢价偏好 |
| `EnableOBDebug` / `ForceOBRedraw` / `ShowOBLifecycleInfo` | 归入调试组 | 非常规使用 |

### D. 保持不变
`ShowFVG`、`ShowOrderBlocks`、`MaxFVGZones`、`MaxOBZones`、各颜色、`EnableOBLifecycle`、`OBCooldownBars`、`EnableOBFVGConfluence`、`MinOBFVGOverlapRatio`、`ShowOBQualityGrade`、`HideLowQualityOB`、`MinVisibleOBQualityScore`。

> 净新增参数仅 2 个;OB 失效硬编码标准影线口径,不新增开关。

---

## 6. 兼容性

- 缓冲区 index 0–9 布局与语义不变,旧 EA/`TestReadOBQuality.mq4` 不受影响(注意指标短名变为 v1.71,`iCustom` 调用名需相应更新)。
- v1.70 文件保持不动,可随时作为回退。

---

## 7. 后续工作(非本 spec 范围,登记以免遗忘)

| 阶段 | 范围 | 产出 |
|------|------|------|
| **Phase 1(本 spec)** | FVG + OB 对齐 + 展示降噪 + 参数精简起步 | 本 spec → plan → v1.71 实现 |
| **Phase 2** | BOS + CHoCH 对齐(对照 `smartmoneyconcepts.bos_choch`;评估 `RequireDisplacement`/`RequireFVG_CHOCH`/MA21 等额外门控是否放宽;结构展示降噪) | 独立 brainstorm → spec → plan |
| 阶段 3(可选) | C 组 deprecated 参数从 `extern` 改 `const` 精简界面;评估 OB 五状态生命周期简化为"mitigated 布尔 + 质量分" | 小型 spec |

Phase 2 依赖说明:Phase 1 的结构化 OB 依赖现有结构引擎输出,故 BOS/CHoCH 优化必须在 Phase 1 稳定后进行,避免两层同时变动难以定位差异。
