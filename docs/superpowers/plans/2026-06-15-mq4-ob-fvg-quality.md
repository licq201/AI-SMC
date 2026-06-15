# MQ4 SMC OB/FVG 质量体系改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不破坏现有 BOS/CHOCH/FVG/OB 输出的前提下，把 MQ4 指标 `SMC_OrderFlow_Indicator_v1.70_zig.mq4` 的 OB 升级为可解释的质量状态机（Fresh/Tested/Weakened/Broken_Once/Invalid），叠加 OB/FVG 同向重叠评分，并新增一个 EA 可读的 `OB_Quality` 数据 buffer。

**Architecture:** 纯单文件 MQL4 指标改造。复用现有 `POI_Zone` 结构与 `ProcessOBLifecycle` 状态机；新增 5 个结构体字段、5 个 extern 参数、4 个评分/重叠函数、1 个 buffer 写入函数；修复一个既有方向 bug；在末尾追加 1 个 `DRAW_NONE` 数据 buffer（索引 9），现有索引 0–8 不动。

**Tech Stack:** MQL4（MetaTrader 4 指标）。无自动化测试框架——每个任务的验证 = MetaEditor 编译 0 错误 + 历史图表回放对照验收用例。

---

## 关键背景（执行者必读）

1. **没有 pytest / 单元测试**。MQL4 的"测试"是：① 在 MetaEditor 按 F7（或 CLI）编译，要求 0 errors；② 把指标挂到 XAUUSD 图表上，用历史回放核对状态/标签/颜色；③ Task 7 用一个测试脚本验证 `OB_Quality` 能被 `iCustom` 读到。

2. **编译方式**（二选一）：
   - GUI：MetaEditor 打开 `.mq4`，按 F7，看"Errors"标签为 0。
   - CLI：`"<MT4安装目录>\metaeditor.exe" /compile:"E:\bossquant\MQ5\AI-SMC\mql5\SMC_OrderFlow_Indicator_v1.70_zig.mq4" /log`，然后查看同目录 `.log`。路径按本机 MT4 安装位置调整。
   - 要在图表上看效果，需把 `.mq4` 复制到 MT4 数据目录的 `MQL4\Indicators\` 下再编译（或在该目录建立指向仓库文件的链接）。本仓库只是源码存放处。

3. **行号会随编辑漂移**。每个 step 给出的行号是改动前的参考位置；定位时以引用的代码片段（`old_string`）为准。

4. **设计文档**：`docs/superpowers/specs/2026-06-15-mq4-ob-fvg-quality-design.md`。本计划是其落地步骤。

5. **目标文件**：`mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（下称"指标文件"）。

6. **提交**：每个任务结束提交一次。提交信息末尾保留：
   `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

## File Structure

| 文件 | 职责 | 本计划动作 |
|------|------|-----------|
| `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4` | SMC 指标主体 | 修改：参数、结构体、状态机、评分、buffer、显示 |
| `mql5/TestReadOBQuality.mq4` | iCustom 读取 `OB_Quality` 的烟雾测试脚本 | 新建（Task 7） |
| `docs/superpowers/specs/2026-06-15-mq4-ob-fvg-quality-design.md` | 设计来源 | 只读引用 |

任务顺序有依赖：Task 1（参数）→ Task 2（字段）→ Task 3（buffer）→ Task 4（评分，依赖 1/2/3）→ Task 5（状态机修复）→ Task 6（显示，依赖 4）→ Task 7（验收）。

---

### Task 1: 新增质量参数 + 调整默认值

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（参数区 ~L98-109）

- [ ] **Step 1: 把 `EnableOBLifecycle` 默认改为 true**

定位（~L104）：
```mql4
extern bool   EnableOBLifecycle      = false;     // 启用OB生命周期机制
```
改为：
```mql4
extern bool   EnableOBLifecycle      = true;      // 启用OB生命周期机制(默认主逻辑)
```

- [ ] **Step 2: 把 `ShowOBLifecycleInfo` 默认改为 false（降噪）**

定位（~L109）：
```mql4
extern bool   ShowOBLifecycleInfo   = true;     // 显示OB生命周期详细信息
```
改为：
```mql4
extern bool   ShowOBLifecycleInfo   = false;    // [高级/调试] 显示OB生命周期详细信息
```

- [ ] **Step 3: 在 OB 生命周期参数块后新增质量评分参数块**

在 `ShowOBLifecycleInfo` 那一行之后、`// --- E. 缠论优化参数 ---` 之前插入：
```mql4

// --- G2. OB/FVG 质量评分参数 (新增) ---
extern bool   EnableOBFVGConfluence    = true;   // 启用OB/FVG同向重叠评分
extern double MinOBFVGOverlapRatio     = 0.20;   // 重叠比例达此值时额外加分
extern bool   ShowOBQualityGrade       = true;   // OB标签显示质量等级[A/B/C/D/X]
extern bool   HideLowQualityOB         = false;  // 隐藏低于阈值的低质量OB
extern double MinVisibleOBQualityScore = 0.20;   // HideLowQualityOB=true时的可见性阈值
```

- [ ] **Step 4: 编译验证**

编译指标文件（见"关键背景 2"）。
Expected: 0 errors, 0 warnings（新增 extern 不影响逻辑）。

- [ ] **Step 5: 提交**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4
git commit -m "feat(mq4): add OB/FVG quality params, default lifecycle on

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 扩展 `POI_Zone` 字段并初始化

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（struct ~L179-196，`AddPOIZone` ~L2698-2745）

- [ ] **Step 1: 给 `POI_Zone` 增加 5 个字段**

定位 struct 末尾（~L195）：
```mql4
    int first_break_bar;        // 记录首次突破的K线索引
    double break_momentum;      // 突破时的动能强度（实体/ATR比值）
};
```
改为：
```mql4
    int first_break_bar;        // 记录首次突破的K线索引
    double break_momentum;      // 突破时的动能强度（实体/ATR比值）

    // --- OB/FVG 重叠与质量评分新增字段 ---
    bool   has_fvg_overlap;     // 是否与同向FVG价格重叠
    int    overlap_fvg_bar;     // 重叠FVG的锚点bar(-1=无)
    double overlap_ratio;       // 重叠宽度/OB宽度
    double quality_score;       // OB质量分 0.0-1.0
    string quality_grade;       // 等级 A/B/C/D/X
};
```

- [ ] **Step 2: 在 `AddPOIZone` 中初始化新字段**

定位 `AddPOIZone` 末尾的生命周期 if/else 块之后、`poi_count++;` 之前（~L2738-2744）：
```mql4
    } else {
        // FVG或未启用生命周期时的默认值
        poi_zones[poi_count].touch_count = 0;
        poi_zones[poi_count].status = -1;          // -1表示不使用生命周期
        poi_zones[poi_count].last_touch_bar = -1;
        poi_zones[poi_count].first_break_bar = -1;
        poi_zones[poi_count].break_momentum = 0.0;
    }
```
在该 `}` 之后插入：
```mql4

    // 初始化OB/FVG重叠与质量评分字段（FVG保留默认值，不参与评分）
    poi_zones[poi_count].has_fvg_overlap = false;
    poi_zones[poi_count].overlap_fvg_bar = -1;
    poi_zones[poi_count].overlap_ratio   = 0.0;
    poi_zones[poi_count].quality_score   = 0.0;
    poi_zones[poi_count].quality_grade   = "D";
```

- [ ] **Step 3: 编译验证**

编译指标文件。
Expected: 0 errors。（字段已声明并初始化，但尚未被读取，正常。）

- [ ] **Step 4: 提交**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4
git commit -m "feat(mq4): add OB quality fields to POI_Zone

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 新增 `OB_Quality` buffer（EA 预留通道）

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（`#property` ~L18，buffer 声明 ~L302，`OnInit` ~L1497-1535，`UpdateBuffers` ~L3194）

- [ ] **Step 1: buffer 数量 9 → 10**

定位（~L18）：
```mql4
#property indicator_buffers 9
```
改为：
```mql4
#property indicator_buffers 10
```

- [ ] **Step 2: 声明 buffer 数组**

定位（~L302）：
```mql4
double MA21_Buffer[];         // Buffer 8: MA21均线缓冲区
```
其后插入：
```mql4
double OB_Quality[];          // Buffer 9: OB质量分(0.0-1.0,DRAW_NONE,供EA经iCustom读取)
```

- [ ] **Step 3: 绑定 buffer**

定位（~L1497）：
```mql4
    SetIndexBuffer(8, MA21_Buffer);
```
其后插入：
```mql4
    SetIndexBuffer(9, OB_Quality);
```

- [ ] **Step 4: 设为 DRAW_NONE（纯数据，不画线）**

定位 MA21 的样式块（~L1510-1512）：
```mql4
        SetIndexStyle(8, DRAW_LINE, STYLE_SOLID, MA21_LineWidth, MA21_Color);
    }
    else
        SetIndexStyle(8, DRAW_NONE);
```
在这一段（`else SetIndexStyle(8, DRAW_NONE);` 那行）之后插入：
```mql4
    SetIndexStyle(9, DRAW_NONE);
```

- [ ] **Step 5: 设置标签与空值**

定位（~L1524）：
```mql4
    SetIndexLabel(8, "MA21");
```
其后插入：
```mql4
    SetIndexLabel(9, "OB Quality");
```
定位（~L1535）：
```mql4
    SetIndexEmptyValue(8, EMPTY_VALUE);
```
其后插入：
```mql4
    SetIndexEmptyValue(9, EMPTY_VALUE);
```

- [ ] **Step 6: 在 `UpdateBuffers` 每根 K 线初始化时重置 OB_Quality**

定位（~L3194-3195）：
```mql4
    OB_Top[current_bar] = EMPTY_VALUE;
    OB_Bottom[current_bar] = EMPTY_VALUE;
```
改为：
```mql4
    OB_Top[current_bar] = EMPTY_VALUE;
    OB_Bottom[current_bar] = EMPTY_VALUE;
    OB_Quality[current_bar] = EMPTY_VALUE;
```

- [ ] **Step 7: 编译验证**

编译指标文件。
Expected: 0 errors。此时 `OB_Quality` 全为 `EMPTY_VALUE`（写入逻辑在 Task 4），索引 0–8 行为完全不变。

- [ ] **Step 8: 提交**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4
git commit -m "feat(mq4): add OB_Quality data buffer (index 9, DRAW_NONE)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: OB/FVG 重叠扫描 + 质量评分 + 写入 buffer

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（在 `GetOBLevelName` 之后 ~L3174 新增函数；主循环 ~L1731 接入调用）

- [ ] **Step 1: 新增 4 个评分/重叠函数 + 1 个 buffer 写入函数**

定位 `GetOBLevelName` 函数结束（~L3174，紧接其后是 `//-----... 更新缓冲区` 注释块）。在 `GetOBLevelName` 的 `}` 之后、`//+---...更新缓冲区` 注释之前插入：
```mql4

//+------------------------------------------------------------------+
//| 计算OB与指定FVG的价格重叠比例(以OB宽度为分母)                      |
//+------------------------------------------------------------------+
double GetOBFVGOverlapRatio(int ob_index, int fvg_index)
{
    double ob_top     = poi_zones[ob_index].top_price;
    double ob_bottom  = poi_zones[ob_index].bottom_price;
    double fvg_top    = poi_zones[fvg_index].top_price;
    double fvg_bottom = poi_zones[fvg_index].bottom_price;

    double overlap_low  = MathMax(ob_bottom, fvg_bottom);
    double overlap_high = MathMin(ob_top, fvg_top);
    if(overlap_high <= overlap_low) return 0.0;

    double ob_width = ob_top - ob_bottom;
    if(ob_width <= 0.0) return 0.0;
    return (overlap_high - overlap_low) / ob_width;
}

//+------------------------------------------------------------------+
//| 根据分数返回等级标签                                              |
//+------------------------------------------------------------------+
string GetOBGradeLabel(double score)
{
    if(score >= 0.80) return "A";
    if(score >= 0.60) return "B";
    if(score >= 0.40) return "C";
    if(score >  0.00) return "D";
    return "X";
}

//+------------------------------------------------------------------+
//| 计算单个OB的质量分(基础分按状态 + 重叠/趋势加分)                   |
//+------------------------------------------------------------------+
double CalculateOBQualityScore(int ob_index)
{
    double base = 0.0;
    switch(poi_zones[ob_index].status) {
        case 0: base = 0.80; break; // Fresh
        case 1: base = 0.65; break; // Tested
        case 2: base = 0.45; break; // Weakened
        case 3: base = 0.20; break; // Broken_Once
        case 4: base = 0.00; break; // Invalid
        default: base = 0.00; break;
    }

    double bonus = 0.0;
    // 同向FVG重叠加分
    if(poi_zones[ob_index].has_fvg_overlap) {
        bonus += 0.15;
        if(poi_zones[ob_index].overlap_ratio >= MinOBFVGOverlapRatio) bonus += 0.05;
    }
    // 与当前主趋势方向一致加分 (g_market_trend: 1=上升, -1=下降)
    if((poi_zones[ob_index].is_bullish  && g_market_trend == 1) ||
       (!poi_zones[ob_index].is_bullish && g_market_trend == -1)) {
        bonus += 0.05;
    }

    double score = base + bonus;
    if(score < 0.0) score = 0.0;
    if(score > 1.0) score = 1.0;
    return score;
}

//+------------------------------------------------------------------+
//| 刷新所有OB的OB/FVG重叠与质量评分(全量扫描)                         |
//+------------------------------------------------------------------+
void RefreshOBFVGConfluence()
{
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type != 1) continue; // 仅OB
        if(poi_zones[i].status < 0) continue;     // 未启用生命周期的OB跳过

        // 重置重叠信息
        poi_zones[i].has_fvg_overlap = false;
        poi_zones[i].overlap_fvg_bar = -1;
        poi_zones[i].overlap_ratio   = 0.0;

        // 扫描同向、未完全触及的FVG，取最大重叠比例
        if(EnableOBFVGConfluence) {
            for(int j = 0; j < poi_count; j++) {
                if(poi_zones[j].poi_type != 0) continue;                         // 仅FVG
                if(poi_zones[j].is_bullish != poi_zones[i].is_bullish) continue; // 同向
                if(poi_zones[j].is_mitigated) continue;                          // 已触及FVG不加分
                double ratio = GetOBFVGOverlapRatio(i, j);
                if(ratio > poi_zones[i].overlap_ratio) {
                    poi_zones[i].overlap_ratio   = ratio;
                    poi_zones[i].overlap_fvg_bar = poi_zones[j].start_bar;
                    poi_zones[i].has_fvg_overlap = true;
                }
            }
        }

        // 计算质量分与等级
        poi_zones[i].quality_score = CalculateOBQualityScore(i);
        poi_zones[i].quality_grade = GetOBGradeLabel(poi_zones[i].quality_score);
    }
}

//+------------------------------------------------------------------+
//| 把每个OB的质量分写入OB_Quality缓冲区(锚点K线;同锚点取最高分)       |
//+------------------------------------------------------------------+
void WriteOBQualityBuffer()
{
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type != 1) continue;
        if(poi_zones[i].status < 0) continue;
        int bar = poi_zones[i].start_bar;
        if(bar < 0 || bar >= ArraySize(OB_Quality)) continue;
        double existing = OB_Quality[bar];
        if(existing == EMPTY_VALUE || poi_zones[i].quality_score > existing) {
            OB_Quality[bar] = poi_zones[i].quality_score;
        }
    }
}
```

- [ ] **Step 2: 在绘图前接入刷新与 buffer 写入**

定位主循环末尾、`DrawGraphicalObjects()` 调用之前（~L1730-1732）：
```mql4
    // 绘制图形对象 (每次都调用，函数内部会判断是否需要重绘)
    DrawGraphicalObjects();
```
改为：
```mql4
    // 刷新OB/FVG重叠评分并写入OB_Quality缓冲区(供EA读取)
    if(EnableOBLifecycle) {
        RefreshOBFVGConfluence();
        WriteOBQualityBuffer();
    }

    // 绘制图形对象 (每次都调用，函数内部会判断是否需要重绘)
    DrawGraphicalObjects();
```

- [ ] **Step 3: 编译验证**

编译指标文件。
Expected: 0 errors。（`g_market_trend` 已在 ~L320 声明，可直接引用。）

- [ ] **Step 4: 回放冒烟验证**

挂到 XAUUSD H1 图表，`EnableOBLifecycle=true`（默认）。打开数据窗口（Ctrl+D），把鼠标移到某个 OB 形成的 K 线上，确认 "OB Quality" 一栏出现 0.x 数值（非空），其余 K 线为空。
Expected: OB 锚点 K 线上 OB Quality 有 0.0–1.0 的值。

- [ ] **Step 5: 提交**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4
git commit -m "feat(mq4): OB/FVG confluence scoring + write OB_Quality buffer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 修复状态机（Invalid 方向 bug + Fresh→Broken_Once）

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（`ProcessOBLifecycle` ~L2985-3030）

- [ ] **Step 1: case 0 增加 Fresh→Broken_Once 分支**

定位（~L2986-2994）：
```mql4
        case 0: // Fresh -> Tested
            if(price_in_zone && IsValidTouch(index, current_bar)) {
                poi_zones[index].status = 1;
                poi_zones[index].touch_count = 1;
                poi_zones[index].last_touch_bar = current_bar;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "首次触及", "Fresh -> Tested");
            }
            break;
```
改为：
```mql4
        case 0: // Fresh -> Tested 或 (未触及即被击穿) -> Broken_Once
            if(price_in_zone && IsValidTouch(index, current_bar)) {
                poi_zones[index].status = 1;
                poi_zones[index].touch_count = 1;
                poi_zones[index].last_touch_bar = current_bar;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "首次触及", "Fresh -> Tested");
            } else if((poi_zones[index].is_bullish && bearish_break) ||
                      (!poi_zones[index].is_bullish && bullish_break)) {
                // 未登记任何有效触及即被反向收盘击穿：直接进入观察状态
                poi_zones[index].status = 3;
                poi_zones[index].first_break_bar = current_bar;
                poi_zones[index].break_momentum = momentum;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "未触及即被击穿", "Fresh -> Broken_Once");
            }
            break;
```

- [ ] **Step 2: 修复 case 3 的 Invalid 方向 bug**

定位（~L3013-3014）：
```mql4
        case 3: // Broken_Once -> Invalid 或 -> Weakened (假突破复活)
            if((poi_zones[index].is_bullish && bullish_break) || (!poi_zones[index].is_bullish && bearish_break)) {
```
改为（多头看反向破底=bearish_break，空头看反向破顶=bullish_break）：
```mql4
        case 3: // Broken_Once -> Invalid 或 -> Weakened (假突破复活)
            // 失效必须用"反向破坏方向"确认：多头看向下破底，空头看向上破顶
            if((poi_zones[index].is_bullish && bearish_break) || (!poi_zones[index].is_bullish && bullish_break)) {
```

- [ ] **Step 3: 编译验证**

编译指标文件。
Expected: 0 errors。

- [ ] **Step 4: 回放验证状态转移（设计验收 4b / 4c）**

挂图回放，建议临时设 `ShowOBLifecycleInfo=true` 看日志：
- **4b（Fresh 直接 Broken）**：找到一个新形成的多头 OB，价格未回踩就一根阴线收盘跌破其底部 → 标签从 Fresh 直接变 Watch（Broken_Once），不再停留 Fresh。
- **4c（Invalid 方向）**：一个 Broken_Once 的多头 OB，价格再次向下收盘破底才转 Invalid；价格向上顺向突破时**不应**转 Invalid。
Expected: 两条都符合。验证完把 `ShowOBLifecycleInfo` 改回 false。

- [ ] **Step 5: 提交**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4
git commit -m "fix(mq4): correct OB invalidation direction + allow Fresh->Broken

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 显示接入（等级标签 + +FVG + 颜色分级 + 低质量隐藏）

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`（`ShouldSkipOB` ~L3078-3094，`GetOBDisplayColor` ~L3099-3123，`GetOBDisplayLabel` ~L3128-3155）

- [ ] **Step 1: `ShouldSkipOB` 增加低质量隐藏**

定位（~L3080-3086）：
```mql4
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑
        if(poi_zones[index].status == 4 && RemoveInvalidOB) { // Invalid且设置移除
            skip_reason = "失效已移除";
            return true;
        }
    } else {
```
改为：
```mql4
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑
        if(poi_zones[index].status == 4 && RemoveInvalidOB) { // Invalid且设置移除
            skip_reason = "失效已移除";
            return true;
        }
        if(HideLowQualityOB && poi_zones[index].quality_score < MinVisibleOBQualityScore) {
            skip_reason = "低质量隐藏";
            return true;
        }
    } else {
```

- [ ] **Step 2: `GetOBDisplayColor` 细化分级配色**

定位生命周期分支的 switch（~L3103-3117）：
```mql4
        switch(poi_zones[index].status) {
            case 0: // Fresh (高效)
                return poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color;
                
            case 1: // Tested (中等)
            case 2: // Weakened (中等)  
            case 3: // Broken_Once (中等)
                return poi_zones[index].is_bullish ? clrDarkGreen : clrSaddleBrown;
                
            case 4: // Invalid (失效)
                return Mitigated_POI_Color; // 使用灰色
                
            default:
                return poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color;
        }
```
改为：
```mql4
        switch(poi_zones[index].status) {
            case 0: // Fresh：原色
                return poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color;

            case 1: // Tested：略暗
                return poi_zones[index].is_bullish ? clrSeaGreen : clrIndianRed;

            case 2: // Weakened：更暗
                return poi_zones[index].is_bullish ? clrDarkGreen : clrSaddleBrown;

            case 3: // Broken_Once：警戒色
                return clrOrange;

            case 4: // Invalid：灰色
                return Mitigated_POI_Color;

            default:
                return poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color;
        }
```

- [ ] **Step 3: `GetOBDisplayLabel` 输出 +FVG 与等级**

定位生命周期分支（~L3132-3148）：
```mql4
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑
        switch(poi_zones[index].status) {
            case 0: // Fresh (高效)
                return direction + " OB (High)";
                
            case 1: // Tested (中等)
            case 2: // Weakened (中等)  
            case 3: // Broken_Once (中等)
                return direction + " OB (Mid-" + IntegerToString(poi_zones[index].touch_count) + ")";
                
            case 4: // Invalid (失效)
                return direction + " OB (Invalid)";
                
            default:
                return direction + " OB";
        }
    } else {
```
改为：
```mql4
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑：方向 + OB[+FVG] + 状态 + [等级]
        string fvg_tag   = poi_zones[index].has_fvg_overlap ? "+FVG" : "";
        string grade_tag = ShowOBQualityGrade ? (" [" + poi_zones[index].quality_grade + "]") : "";
        string state_tag = "";
        switch(poi_zones[index].status) {
            case 0: state_tag = "";         break; // Fresh
            case 1: state_tag = " Tested";  break;
            case 2: state_tag = " Weak";    break;
            case 3: state_tag = " Watch";   break;
            case 4: state_tag = " Invalid"; break;
            default: state_tag = "";        break;
        }
        return direction + " OB" + fvg_tag + state_tag + grade_tag;
    } else {
```

- [ ] **Step 4: 编译验证**

编译指标文件。
Expected: 0 errors。

- [ ] **Step 5: 回放验证显示（设计验收 1/6/7/9）**

挂图回放确认：
- 新 OB 显示 `Bullish OB [B]` 之类，带等级。
- OB 与同向 FVG 价格重叠时标签出现 `+FVG`，且数据窗口 OB Quality 更高（验收 6）。
- 异向 FVG 不产生 `+FVG`、不加分（验收 7）。
- 设 `HideLowQualityOB=true`、`MinVisibleOBQualityScore=0.5`，低分 OB 不再绘制（验收 9）；验证后改回 false。
Expected: 均符合。

- [ ] **Step 6: 提交**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4
git commit -m "feat(mq4): OB labels show grade/+FVG, graded colors, hide low-quality

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: iCustom 读取测试脚本 + 全量验收

**Files:**
- Create: `mql5/TestReadOBQuality.mq4`

- [ ] **Step 1: 编写测试脚本**

创建 `mql5/TestReadOBQuality.mq4`：
```mql4
//+------------------------------------------------------------------+
//| TestReadOBQuality.mq4                                            |
//| 验证 SMC 指标的 OB_Quality(索引9) 可被 EA/脚本经 iCustom 读取     |
//| 用法：编译后拖到 XAUUSD 图表(指标须已挂在同图表或可被加载)        |
//+------------------------------------------------------------------+
#property strict
#property show_inputs

input int ScanBars = 500;   // 向左扫描的K线数

void OnStart()
{
    string ind = "SMC_OrderFlow_Indicator_v1.70_zig";
    int found = 0;
    int limit = MathMin(ScanBars, Bars);

    for(int shift = 0; shift < limit; shift++) {
        // 不传 input 参数：iCustom 使用指标默认参数；9=OB_Quality buffer 索引
        double q = iCustom(Symbol(), Period(), ind, 9, shift);
        if(q != EMPTY_VALUE) {
            found++;
            Print("OB_Quality @ shift ", shift, " (", TimeToString(Time[shift]),
                  ") = ", DoubleToString(q, 2));
        }
    }
    Print("TestReadOBQuality: 在 ", limit, " 根K线内发现 ", found,
          " 个OB质量分锚点。", (found > 0 ? "通道可读 ✓" : "未读到，检查指标是否已加载/EnableOBLifecycle"));
}
```

- [ ] **Step 2: 编译测试脚本**

编译 `mql5/TestReadOBQuality.mq4`（脚本同样在 MetaEditor 编译；运行时需放在 `MQL4\Scripts\`）。
Expected: 0 errors。

- [ ] **Step 3: 运行脚本验证（设计验收 11）**

确保 SMC 指标已挂在 XAUUSD 图表上，把脚本拖到同一图表运行，看"Experts/Journal"日志。
Expected: 打印若干 `OB_Quality @ shift ... = 0.xx`，末行 `通道可读 ✓`。

- [ ] **Step 4: 全量验收对照**

按设计文档"测试与验收"逐条核对（1–11）。重点回归：
- 验收 10：现有 BOS/CHOCH/FVG/OB（索引 0–8）数据窗口数值与改造前一致（旧 EA 兼容）。
- 验收 2/3/5：Fresh→Tested→Weakened、Broken_Once→Invalid（动能门控）转移正确。
- 验收 8：`RemoveInvalidOB=false` 时 Invalid 灰显；`true` 时隐藏。
Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add mql5/TestReadOBQuality.mq4
git commit -m "test(mq4): add iCustom smoke test for OB_Quality buffer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 自检对照（spec 覆盖）

- 目标1 默认开启生命周期 → Task 1 Step 1。
- 目标2 五状态质量机 + Fresh→Broken 修订 → Task 5。
- 目标3 OB/FVG 重叠评分 → Task 4。
- 目标4 标签显示等级与 +FVG → Task 6 Step 3。
- 目标5 参数精简/降噪 → Task 1（默认值 + 注释标记）。
- 目标6 兼容（索引 0–8 不变）→ Task 3 仅追加索引 9；验收 10。
- 目标7 OB_Quality EA 通道 → Task 3 + Task 4 写入 + Task 7 读取验证。
- 修订1 Invalid 方向 bug → Task 5 Step 2。
- 修订2 Fresh→Broken_Once → Task 5 Step 1。

## 风险提示

- 默认开启生命周期会改变用户看到的 OB 颜色/数量；可回退 `EnableOBLifecycle=false`。
- 颜色用了固定色（clrSeaGreen 等），若与用户主题冲突可后续参数化；本期不做（YAGNI）。
- `iCustom` 不传 input 时用指标默认参数；若用户在图表上改了参数，脚本读到的是默认参数那一份指标实例的值——验收时用默认参数即可。
