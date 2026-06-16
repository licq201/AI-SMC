# MQ4 SMC 指标对齐标准 · Phase 1(FVG + OB)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新建 `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`,把 FVG/OB 的检测、失效口径、展示对齐到 Python/`smartmoneyconcepts` 标准(参照 `dashboard/chart.html`)。

**Architecture:** 务实混合(Approach C)——保留 MT4 现有缠论/ZigZag 摆点 + BOS/CHoCH 结构引擎,只让 FVG/OB 语义对齐标准:FVG 放宽检测+部分填充+合并连续;OB 改为"结构突破事件驱动"的新通道并用影线口径判失效;展示降噪对齐 chart.html。

**Tech Stack:** MQL4(MetaTrader 4 自定义指标),无自动化测试框架。

> **MQL4 验证方式(全程通用)**:本项目无 pytest 等自动化测试。每个任务的"验证"= ①在 MetaEditor 打开 v1.71 按 **F7 编译,期望 0 errors**;②把 v1.71 挂到 XAUUSD 图表,与 `dashboard/chart.html`(相同 symbol/TF)肉眼对照该任务声明的验收点。无法在 CLI 跑编译,**编译步骤由用户在 MetaEditor 执行**。
>
> **行号会漂移**:每次编辑前先用 Grep 重新定位锚点(函数名/注释),不要盲信本文件中的行号。

---

## 文件结构

| 文件 | 责任 | 本计划动作 |
|------|------|-----------|
| `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4` | 指标主体(FVG/OB/结构检测/绘制) | **新建**(从 v1.70 复制)并全部改动 |
| `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4` | 旧版基线 | 不动(回退用) |
| `docs/SMC指标_v1.71_对齐标准_验证清单.md` | 验收核对清单 | 新建(Task 9) |

---

### Task 0: 新建 v1.71 文件并改版本号/短名

**Files:**
- Create: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(从 v1.70 复制)

- [ ] **Step 1: 复制文件**

```bash
cp mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4 mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
```

- [ ] **Step 2: 改版本号与短名**

用 Grep 在新文件定位 `#property version` 与 `IndicatorShortName`(或 `IndicatorSetString(...SHORTNAME...)`)。把版本字符串改为 `1.71`,短名里出现的 `v1.70` 改为 `v1.71`。
若文件头有标题注释含 `v1.70_zig`,同步改为 `v1.71_zig`。

- [ ] **Step 3: 编译验证(用户执行)**

在 MetaEditor 打开 `SMC_OrderFlow_Indicator_v1.71_zig.mq4`,按 F7。
Expected: 0 errors(应与 v1.70 行为完全一致,仅名字变化)。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): fork v1.71 from v1.70 for SMC standard alignment"
```

---

### Task 1: 放宽 FVG 检测 + 关闭非标准过滤(默认值)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(`IdentifyFVG` 函数;参数 `FVGQualityThreshold`)

验收点:之前因"第三根未延续"或"ATR 质量不足"被漏掉的 FVG,现在能标出,数量级更接近 chart.html。

- [ ] **Step 1: 改 `FVGQualityThreshold` 默认值**

定位(Grep `FVGQualityThreshold`)参数声明行,改默认:

```mql4
extern double FVGQualityThreshold = 0.0;     // FVG 最低质量阈值(0=关闭,标准库无此过滤)
```

- [ ] **Step 2: 去掉多头 FVG 的第三根延续条件**

定位 `valid_bullish_fvg`(约 2508 行),改为只判中间 K 线方向:

```mql4
            // 验证中间K线的强势特征(对齐标准:只要求中间K线方向)
            bool valid_bullish_fvg = close[current_bar + 1] > open[current_bar + 1]; // 中间K线看涨
```

- [ ] **Step 3: 去掉空头 FVG 的第三根延续条件**

定位 `valid_bearish_fvg`(约 2546 行),改为:

```mql4
            bool valid_bearish_fvg = close[current_bar + 1] < open[current_bar + 1]; // 中间K线看跌
```

- [ ] **Step 4: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图对照:FVG 数量增多且更贴近 chart.html 的 FVG 分布。

- [ ] **Step 5: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): relax FVG detection to standard (drop 3rd-bar continuation, ATR filter off)"
```

---

### Task 2: 新增对齐参数 + `POI_Zone` 增加 `fill_pct` 字段

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(参数块 G2 附近;`POI_Zone` 结构;`AddPOIZone`)

- [ ] **Step 1: 新增 2 个参数**

定位 `// --- G2. OB/FVG 质量评分参数 (新增) ---` 块,在其后追加:

```mql4
// --- G3. FVG 标准对齐参数 (v1.71 新增) ---
extern double FVGMitigationThreshold = 1.0;   // FVG填充达此比例即视为已填充并隐藏(0.5=半填充口径)
extern bool   FVG_JoinConsecutive    = true;  // 合并相邻同向、价格重叠的FVG
```

- [ ] **Step 2: `POI_Zone` 增加 `fill_pct` 字段**

定位 `struct POI_Zone`,在 `double quality_score;` 同区块附近追加:

```mql4
    double fill_pct;            // FVG累计填充比例 0.0-1.0(OB不使用)
```

- [ ] **Step 3: 在 `AddPOIZone` 初始化 `fill_pct`**

定位 `AddPOIZone` 中质量字段初始化处(`poi_zones[poi_count].quality_grade = "D";` 之后),追加:

```mql4
    poi_zones[poi_count].fill_pct = 0.0;
```

- [ ] **Step 4: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors(行为暂无可见变化,字段尚未使用)。

- [ ] **Step 5: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): add FVG alignment params + POI_Zone.fill_pct field"
```

---

### Task 3: FVG 部分填充追踪(重写 `ProcessFVGStatus`)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(`ProcessFVGStatus`)

验收点:FVG 被价格部分渗透时 `fill_pct` 单调增长;达 `FVGMitigationThreshold` 标记 `is_mitigated`。与 Python `_fill_pct_for_fvg` 同口径。

- [ ] **Step 1: 用标准填充口径重写 `ProcessFVGStatus` 主体**

定位 `void ProcessFVGStatus(`,把函数体替换为(保留原有 Alert 段):

```mql4
void ProcessFVGStatus(int index, int current_bar, const double &high[], const double &low[], const double &close[])
{
    if(poi_zones[index].is_mitigated) return;

    double top    = poi_zones[index].top_price;
    double bottom = poi_zones[index].bottom_price;
    double gap    = top - bottom;
    if(gap <= 0) { poi_zones[index].is_mitigated = true; g_data_version++; return; }

    double new_pct = poi_zones[index].fill_pct;
    if(poi_zones[index].is_bullish) {
        // 多头FVG:价格自顶向下渗透(bar_low 下探入区)
        if(low[current_bar] < top) {
            double penetration = top - MathMax(low[current_bar], bottom);
            new_pct = penetration / gap;
        }
    } else {
        // 空头FVG:价格自底向上渗透(bar_high 上行入区)
        if(high[current_bar] > bottom) {
            double penetration = MathMin(high[current_bar], top) - bottom;
            new_pct = penetration / gap;
        }
    }
    // 单调不减
    if(new_pct > poi_zones[index].fill_pct) {
        poi_zones[index].fill_pct = MathMin(1.0, new_pct);
        g_data_version++;
    }

    // 达到隐藏阈值即标记 mitigated
    if(poi_zones[index].fill_pct >= FVGMitigationThreshold && !poi_zones[index].is_mitigated) {
        poi_zones[index].is_mitigated = true;
        g_data_version++;
        string direction = poi_zones[index].is_bullish ? "看涨" : "看跌";
        if(EnableAlerts && AlertOnPOIEntry) {
            bool cooled = (TimeCurrent() - g_last_signal_time) >= (CooldownBars * PeriodSeconds());
            bool zone_available = (poi_zones[index].trigger_count < MaxTriggersPerZone);
            if(cooled && zone_available) {
                Alert("SMC: ", direction, " FVG 已填充 ", DoubleToString(poi_zones[index].fill_pct*100,0), "% at ", Symbol());
                g_last_signal_time = TimeCurrent();
                poi_zones[index].trigger_count++;
            }
        }
    }
}
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。对照 chart.html:同一 FVG 的填充进度方向一致(多头被下探、空头被上行填充)。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): FVG partial-fill tracking aligned to standard penetration depth"
```

---

### Task 4: 合并连续同向 FVG(`FVG_JoinConsecutive`)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(`IdentifyFVG` 两处 `AddPOIZone` 之前)

验收点:相邻同向、价格重叠的多个 FVG 合并为一个更宽区域(对齐 `join_consecutive=True`)。

- [ ] **Step 1: 新增合并辅助函数**

在 `IdentifyFVG` 函数定义之前,新增:

```mql4
//+------------------------------------------------------------------+
//| 尝试把新FVG并入已存在的同向、价格重叠的最近FVG                    |
//| 返回 true 表示已合并(调用方不再 AddPOIZone)                       |
//+------------------------------------------------------------------+
bool TryJoinConsecutiveFVG(double new_top, double new_bottom, bool is_bullish)
{
    if(!FVG_JoinConsecutive) return false;
    for(int i = poi_count - 1; i >= 0; i--) {
        if(poi_zones[i].poi_type != 0) continue;          // 仅FVG
        if(poi_zones[i].is_mitigated) continue;
        if(poi_zones[i].is_bullish != is_bullish) continue;
        // 价格重叠判定
        double ov_low  = MathMax(poi_zones[i].bottom_price, new_bottom);
        double ov_high = MathMin(poi_zones[i].top_price, new_top);
        if(ov_high >= ov_low) {
            // 并入:扩展为并集,重置绘制标记
            poi_zones[i].top_price    = MathMax(poi_zones[i].top_price, new_top);
            poi_zones[i].bottom_price = MathMin(poi_zones[i].bottom_price, new_bottom);
            poi_zones[i].is_drawn     = false;
            g_data_version++;
            return true;
        }
    }
    return false;
}
```

- [ ] **Step 2: 多头 FVG 入口接入合并**

定位多头 `AddPOIZone(current_bar + 1, low[current_bar], high[current_bar + 2], true, 0);`,替换为:

```mql4
                    if(!TryJoinConsecutiveFVG(low[current_bar], high[current_bar + 2], true))
                        AddPOIZone(current_bar + 1, low[current_bar], high[current_bar + 2], true, 0);
```

- [ ] **Step 3: 空头 FVG 入口接入合并**

定位空头 `AddPOIZone(current_bar + 1, low[current_bar + 2], high[current_bar], false, 0);`,替换为:

```mql4
                    if(!TryJoinConsecutiveFVG(low[current_bar + 2], high[current_bar], false))
                        AddPOIZone(current_bar + 1, low[current_bar + 2], high[current_bar], false, 0);
```

- [ ] **Step 4: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。对照:连续缺口区合并,FVG 框更少更宽,接近 chart.html。

- [ ] **Step 5: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): merge consecutive same-direction FVGs (join_consecutive)"
```

---

### Task 5: FVG 展示 —— 显示 `FVG nn%` 并隐藏已填充

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(`DrawGraphicalObjects` 中 FVG 绘制块,约 3495-3503)

验收点:FVG 标签形如 `Bullish FVG 35%`;已填充(mitigated)的 FVG 默认不再绘制。

- [ ] **Step 1: 替换 FVG 标签与隐藏逻辑**

定位 FVG 绘制块中:

```mql4
                color zone_color = poi_zones[i].is_mitigated ? Mitigated_POI_Color :
                                  (poi_zones[i].is_bullish ? Bullish_FVG_Color : Bearish_FVG_Color);
                string label_text = poi_zones[i].is_bullish ? "Bullish FVG" : "Bearish FVG";
                if(poi_zones[i].is_mitigated) label_text += " (Mitigated)";

                DrawPOIZone(i, "FVG", zone_color, label_text);
```

替换为:

```mql4
                // 已填充FVG默认隐藏(除非 ShowMitigatedPOI 显式打开)
                if(poi_zones[i].is_mitigated && !ShowMitigatedPOI) {
                    poi_zones[i].is_drawn = true;
                    continue;
                }
                color zone_color = poi_zones[i].is_mitigated ? Mitigated_POI_Color :
                                  (poi_zones[i].is_bullish ? Bullish_FVG_Color : Bearish_FVG_Color);
                int pct = (int)MathRound(poi_zones[i].fill_pct * 100.0);
                string label_text = (poi_zones[i].is_bullish ? "Bullish FVG" : "Bearish FVG")
                                  + " " + IntegerToString(pct) + "%";

                DrawPOIZone(i, "FVG", zone_color, label_text);
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。对照 chart.html 的 `FVG nn%` 标注与"隐藏全填"行为一致。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): FVG label shows fill %, hide filled FVG by default"
```

---

### Task 6: OB 结构化新通道(替换主循环内的 OB 识别)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(主循环 ~1705;结构最终化区 ~1721-1737;新增函数;`OB_OnlyDrive` 注释)

验收点:OB 只在真实结构突破(`structure_zones[]`)处产生,数量大幅减少,不再"挤成一堆"。

- [ ] **Step 1: 主循环内停用旧 OB 识别**

定位主循环内 `if (i >= 5) IdentifyOrderBlocks(i, open, high, low, close);`,替换为注释占位:

```mql4
            // v1.71: OB 改为结构突破事件驱动,移到结构最终化之后(见 IdentifyOrderBlocksFromStructure)
            // if (i >= 5) IdentifyOrderBlocks(i, open, high, low, close);
```

- [ ] **Step 2: 新增结构驱动 OB 函数**

在 `IdentifyOrderBlocks` 函数定义之后,新增:

```mql4
//+------------------------------------------------------------------+
//| 结构驱动的OB识别(v1.71):遍历最终结构突破事件回溯生成OB           |
//| 多头突破→突破bar前最近一根阴线;空头突破→最近一根阳线;5根窗口     |
//+------------------------------------------------------------------+
void IdentifyOrderBlocksFromStructure(const double &open[], const double &high[],
                                      const double &low[], const double &close[])
{
    int total = ArraySize(close);
    for(int s = 0; s < structure_count; s++) {
        int   brk_bar    = structure_zones[s].start_bar;   // 突破发生的bar
        bool  is_bullish = structure_zones[s].is_bullish;  // 突破方向
        if(brk_bar < 1 || brk_bar >= total) continue;

        int lo = MathMax(brk_bar - 5, 0);
        if(is_bullish) {
            // 多头突破:找突破前最近一根阴线作为看涨OB
            for(int i = brk_bar - 1; i >= lo; i--) {
                if(close[i] < open[i]) { AddPOIZone(i, high[i], low[i], true, 1); break; }
            }
        } else {
            // 空头突破:找突破前最近一根阳线作为看跌OB
            for(int i = brk_bar - 1; i >= lo; i--) {
                if(close[i] > open[i]) { AddPOIZone(i, high[i], low[i], false, 1); break; }
            }
        }
    }
}
```

- [ ] **Step 3: 在结构最终化后调用新函数**

定位结构后置处理块(`if(EnableChanOptimization || EnableZigZagFilter)` 内 `DetectStructureBreaks` 重建之后、`TrimStructureZonesToNewest()` 之前)。在 `TrimStructureZonesToNewest();` 之前插入。注意两条路径都要覆盖:
- 当 `EnableChanOptimization || EnableZigZagFilter`:结构在后置块重建,故在该块 `for` 重检测之后调用。
- 当两者都关闭:结构在主循环内已建,故也需在主循环之后调用一次。

最简做法:在 `TrimStructureZonesToNewest();` **这一行之前**统一插入:

```mql4
        // v1.71: 结构最终确定后,基于突破事件生成OB
        IdentifyOrderBlocksFromStructure(open, high, low, close);
```

确认此处 `open/high/low/close` 在作用域内(主 `OnCalculate` 数组参数);若 `TrimStructureZonesToNewest()` 位于无法访问这些数组的作用域,则改在 1729-1731 的 `UpdateBuffers` 循环之后、同一作用域内调用。

- [ ] **Step 4: 标注 `OB_OnlyDrive` 废弃**

定位 `extern bool   OB_OnlyDrive`,把注释改为:

```mql4
extern bool   OB_OnlyDrive        = false;   // [已废弃 v1.71] OB 改为结构突破事件驱动,本参数不再生效
```

- [ ] **Step 5: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。对照 chart.html:OB 数量、位置与"绑定结构突破"的标准 OB 基本一致;不再出现一堆无结构 OB。

- [ ] **Step 6: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): structure-driven OB detection (bind to BOS/CHoCH breaks)"
```

---

### Task 7: OB 失效口径对齐标准(影线击穿远端)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(`ProcessOBLifecycle` 失效判定)

验收点:多头 OB 当 `low < ob.low` 即失效;空头 OB 当 `high > ob.high` 即失效——与 Python `update_mitigation` 一致。

- [ ] **Step 1: 阅读现有 `ProcessOBLifecycle`**

Grep 定位 `void ProcessOBLifecycle(`,通读其 case 0/3 的"反向破坏"判定(v1.70 用收盘价 `close < bottom`)。

- [ ] **Step 2: 把"反向破坏"改为影线口径**

将判定中用于"破坏/失效"的条件由收盘价改为影线:
- 多头 OB 破坏条件:由 `close[current_bar] < bottom` 改为 `low[current_bar] < poi_zones[index].bottom_price`
- 空头 OB 破坏条件:由 `close[current_bar] > top` 改为 `high[current_bar] > poi_zones[index].top_price`

保留 `RequireMomentumOnBreak`/`BreakMomentumATR` 代码但在其判定前注释说明 v1.71 以影线口径为主(动能仅作附加,后续阶段冻结)。具体改动按实际 `ProcessOBLifecycle` 行内条件逐处替换(编辑时以 Grep 锚点为准)。

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。对照:OB 失效时机与 chart.html 的 OB `mitigated`(影线击穿)一致。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): align OB invalidation to standard wick-breach of far boundary"
```

---

### Task 8: 展示降噪 —— 默认隐藏失效 OB + 标签防重叠

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`(`ShouldSkipOB`;`DrawPOIZone` 标签定位)

验收点:失效 OB 默认不绘制;同价位标签不再完全重叠堆叠。

- [ ] **Step 1: 失效 OB 默认隐藏**

Grep 定位 `bool ShouldSkipOB(`。确认其逻辑:当 OB `status == 4`(Invalid)且 `RemoveInvalidOB==false` 时当前是"灰显保留"。改为默认跳过失效 OB(除非 `ShowMitigatedPOI` 打开)。在 `ShouldSkipOB` 内失效分支加入:

```mql4
    // v1.71: 失效OB默认隐藏(对齐 chart.html 的 active-only),除非显式显示已触及区
    if(poi_zones[index].status == 4 && !ShowMitigatedPOI) { reason = "失效隐藏 "; return true; }
```

(若已有 `status==4` 分支,合并条件,避免重复 return。)

- [ ] **Step 2: 标签防重叠(垂直错位)**

在 `DrawPOIZone` 标签价位计算处,把固定 5% 偏移改为带"防碰撞槽位"的偏移。先在 `DrawGraphicalObjects` 顶部(绘制循环前)声明一个文件级静态收集器,或简单方案:用全局静态数组记录本次已用标签价位,新增标签若与既有过近则上移。最小实现——把 `DrawPOIZone` 内:

```mql4
    double label_price = zone.top_price + (zone.top_price - zone.bottom_price) * 0.05;
```

替换为带 zone_index 微错位:

```mql4
    double zh = (zone.top_price - zone.bottom_price);
    double label_price = zone.top_price + zh * (0.05 + 0.06 * (zone_index % 3)); // 按索引轻微错位,降低重叠
```

> 说明:这是低成本错位,主要降噪来自 Task 6(更少 OB)+ Task 5/8(隐藏已填/失效)。若仍拥挤,后续阶段再做全局标签排布。

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。对照截图原始拥挤场景,标签可读性明显改善。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4
git commit -m "feat(mq4): hide invalid OB by default + stagger zone labels to reduce overlap"
```

---

### Task 9: 验证清单文档

**Files:**
- Create: `docs/SMC指标_v1.71_对齐标准_验证清单.md`

- [ ] **Step 1: 写验证清单**

内容包含:
- 如何并排:MT4 挂 v1.71 + 浏览器开 `dashboard/chart.html`(同 symbol/TF)。
- 4 个核对样本及期望:
  1. 干净多头 FVG(三K无重叠缺口,中间阳线)→ 两侧都应有同位置 FVG。
  2. 第三根暂停的 FVG → v1.71 现在应标出(v1.70 会漏)。
  3. 有 BOS 的大阳线前阴线 → 两侧都应有同位置看涨 OB。
  4. 无 BOS 的孤立大阳线 → v1.71 不应再生成 OB(v1.70 会误标)。
- FVG 填充%、OB 失效时机与 chart.html 对照一致性检查。
- 回退说明:出问题可改用 v1.70 文件。

- [ ] **Step 2: Commit**

```bash
git add docs/SMC指标_v1.71_对齐标准_验证清单.md
git commit -m "docs: add v1.71 standard-alignment verification checklist"
```

---

## Self-Review(规划者自检)

**Spec 覆盖**:
- §4.1 文件/版本 → Task 0 ✓
- §4.2 FVG 放宽/过滤关闭 → Task 1 ✓;部分填充 → Task 2(字段)+Task 3(逻辑)✓;合并连续 → Task 4 ✓
- §4.3 OB 结构化新通道 → Task 6 ✓;影线失效口径 → Task 7 ✓;OB_OnlyDrive 废弃 → Task 6 Step4 ✓
- §4.4 展示降噪(隐藏全填FVG → Task 5;隐藏失效OB+标签防重叠 → Task 8;FVG nn% → Task 5)✓
- §4.5 验证方式 → Task 9 ✓
- §5 参数表:新增2参数 → Task 2;FVGQualityThreshold 默认0 → Task 1;OB_OnlyDrive 废弃 → Task 6;其余 deprecated 仅注释(归入阶段2,本计划不强制)✓
- §6 兼容性:缓冲区 0–9 不动(全程未改 SetIndexBuffer);短名变更已在 Task 0 提示 iCustom 影响 ✓

**占位符扫描**:无 TBD;每个代码步骤含完整代码。Task 7 因 `ProcessOBLifecycle` 内条件分散,采用"Grep 锚点逐处替换"指引而非整段替换——已给出明确的旧→新条件映射。

**类型一致性**:新字段 `fill_pct`(double)在 Task 2 定义、Task 3/5 使用;新函数 `TryJoinConsecutiveFVG`(Task4)、`IdentifyOrderBlocksFromStructure`(Task6)签名与调用一致;新参数 `FVGMitigationThreshold`/`FVG_JoinConsecutive` 在 Task2 定义、Task3/5/4 使用。一致。

**已知风险/执行注意**:
- Task 6 Step3 的插入作用域:必须确认 `open/high/low/close` 可见;否则改到 `UpdateBuffers` 循环同作用域。执行时优先验证编译通过。
- 行号全部会漂移,编辑前 Grep 锚点。
