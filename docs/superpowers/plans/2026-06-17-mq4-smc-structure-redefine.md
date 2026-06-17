# MQ4 SMC 结构分支重定义(BOS/CHoCH 标准化重写)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` 上,用一个干净的 bias 状态机在**固定摆点**上重写标准 SMC 的 BOS/CHoCH,并修复结构线显示;对缠论体系零影响。

**Architecture:** 新增单次扫描检测器 `DetectStructureBreaksSMC`(只读 `swing_points[]`,只写 `structure_zones[]`,自带私有 `g_smc_bias`,不碰 `g_market_trend`/缠论/`is_broken`)。替换原 `DetectStructureBreaks` 的调用。去掉位移/FVG/MA21/受保护gate 等非标准门控。

**Tech Stack:** MQL4,无自动化测试框架。

> **MQL4 验证方式(通用)**:无 pytest。每任务 = ① MetaEditor F7 **0 errors**;② 挂图核对该任务验收点。编译由用户执行。**行号会漂移,编辑前 Grep 锚点。**

---

## 文件结构

| 文件 | 责任 | 动作 |
|------|------|------|
| `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` | 指标主体 | 新增 SMC 结构检测器 + 改调用 + 改显示 |
| `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4` | 回退基线 | 不动 |
| `docs/SMC指标_v1.72_SMC结构隔离审计.md` | 隔离审计证据 | 新建(Task 1) |
| `docs/SMC指标_v1.71_对齐标准_验证清单.md` | 验证清单 | 追加(Task 5) |

---

### Task 1: 隔离依赖审计(确认不影响缠论)

**Files:**
- Create: `docs/SMC指标_v1.72_SMC结构隔离审计.md`

验收点:确认新检测器要写的全局只被 SMC 读取,缠论不依赖。

- [ ] **Step 1: 跑依赖审计 grep**

```bash
cd /e/bossquant/MQ5/AI-SMC
echo "=== is_broken 读写点 ==="; grep -nE "\.is_broken" mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
echo "=== g_market_trend 读写点 ==="; grep -nE "g_market_trend" mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
echo "=== g_last_break_up/down_bar 读写点 ==="; grep -nE "g_last_break_(up|down)_bar" mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
echo "=== g_choch_*_occurred 读写点 ==="; grep -nE "g_choch_(down|up)_occurred" mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
echo "=== structure_zones 读取点 ==="; grep -nE "structure_zones\[" mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
```

- [ ] **Step 2: 记录结论(已知预期)**

把结果写入 `docs/SMC指标_v1.72_SMC结构隔离审计.md`,确认:
- `is_broken`:仅 `DetectStructureBreaks` 写、仅 `FindLatestUnbrokenStructure` 读 → **SMC 专用**。新检测器**不写** swing 的 `is_broken`(用私有 bias,不需要)。
- `g_market_trend`:由趋势引擎(`UpdateTrendSequenceTracking`/`UpdateTrendStateMachine`/`ReclassifySwingPoints`)写,`DetectStructureBreaks` 只读,OB 质量加分只读 → 新检测器**不写**,保持引擎不变。
- `g_last_break_up/down_bar`、`g_choch_*_occurred`:仅旧 `DetectStructureBreaks` 写;消费者为已废弃的 `OB_OnlyDrive` → 新检测器**不写**,安全。
- `structure_zones[]`:SMC 显示输出,缠论不读 → 可重建。

判定门槛:若 grep 显示上述任一全局被**缠论/笔/分型/中枢**相关函数读取,则停止并上报(需保留该副作用)。否则继续。

- [ ] **Step 3: Commit**

```bash
git add docs/SMC指标_v1.72_SMC结构隔离审计.md
git commit -m "docs: SMC structure isolation audit (no Chan dependency on SMC-owned state)"
```

---

### Task 2: 新增 SMC 私有 bias + `DetectStructureBreaksSMC` + `FindBreakBarSMC`

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(新增全局 + 两个函数;暂不接线)

验收点:编译通过;函数已定义但未调用(行为暂不变)。

- [ ] **Step 1: 新增 SMC 私有 bias 全局**

定位(Grep `int g_market_trend = 0;`),在其后新增一行:

```mql4
int g_smc_bias = 0;                     // [SMC重写] SMC结构私有bias:0中性/1上升/-1下降(不影响g_market_trend)
```

- [ ] **Step 2: 在 `FindLatestUnbrokenStructure` 函数之后新增两个函数**

定位(Grep `int FindLatestUnbrokenStructure`)该函数结尾 `}`,在其后插入:

```mql4
//+------------------------------------------------------------------+
//| [SMC重写] 在(更旧older_bar, 更新newer_bar]间从旧到新找收盘破位bar  |
//| is_up=true 找突破level上方,否则找跌破下方;ConfirmBreakClose 决定   |
//| 用收盘还是 high/low。返回 -1 表示无确认破位。                       |
//| 注:本指标 index 越大越旧;older_bar>newer_bar。                    |
//+------------------------------------------------------------------+
int FindBreakBarSMC(double level, bool is_up, int older_bar, int newer_bar,
                    const double &high[], const double &low[], const double &close[])
{
    int lo = MathMax(newer_bar, 0);
    int hi = older_bar - 1;
    if(hi < lo) return newer_bar;   // 两摆点紧邻,直接用新摆点bar
    for(int b = hi; b >= lo; b--) { // 从旧到新扫描
        if(is_up) {
            double v = ConfirmBreakClose ? close[b] : high[b];
            if(v > level) return b;
        } else {
            double v = ConfirmBreakClose ? close[b] : low[b];
            if(v < level) return b;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| [SMC重写] 固定摆点上的标准BOS/CHoCH检测(单次扫描,bias状态机)      |
//| 只读swing_points[];只写structure_zones[];不动缠论/g_market_trend。 |
//+------------------------------------------------------------------+
void DetectStructureBreaksSMC(const double &high[], const double &low[], const double &close[])
{
    structure_count = 0;   // SMC结构输出,重建
    g_smc_bias = 0;

    bool   have_high = false, have_low = false;
    double prev_high = 0.0,  prev_low = 0.0;
    int    prev_high_bar = -1, prev_low_bar = -1;
    int    total = ArraySize(close);

    // 摆点按时间顺序:index 0=最旧, swing_count-1=最新
    for(int i = 0; i < swing_count; i++) {
        if(swing_points[i].structure_type < 0) continue;   // 跳过未分类/废弃摆点
        int    sbar   = swing_points[i].bar_index;
        double sprice = swing_points[i].price;
        if(sbar < 0 || sbar >= total) continue;

        if(swing_points[i].is_high) {
            if(have_high && sprice > prev_high) {
                int bbar = FindBreakBarSMC(prev_high, true, prev_high_bar, sbar, high, low, close);
                if(bbar >= 0) {
                    int stype = (g_smc_bias == -1) ? 1 : 0; // 下降中破前高=CHoCH(1),否则BOS(0)
                    AddStructureZone(bbar, prev_high, true, stype, prev_high_bar);
                    g_smc_bias = 1;
                }
            }
            prev_high = sprice; prev_high_bar = sbar; have_high = true;
        } else {
            if(have_low && sprice < prev_low) {
                int bbar = FindBreakBarSMC(prev_low, false, prev_low_bar, sbar, high, low, close);
                if(bbar >= 0) {
                    int stype = (g_smc_bias == 1) ? 1 : 0; // 上升中破前低=CHoCH(1),否则BOS(0)
                    AddStructureZone(bbar, prev_low, false, stype, prev_low_bar);
                    g_smc_bias = -1;
                }
            }
            prev_low = sprice; prev_low_bar = sbar; have_low = true;
        }
    }
}
```

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors(函数定义但未调用,图表行为不变)。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): add DetectStructureBreaksSMC (standard BOS/CHoCH bias state machine, not wired)"
```

---

### Task 3: 接线 —— 用新检测器替换旧的逐bar调用

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(主循环 ~1704-1707;后置块 ~1729-1742)

验收点:BOS/CHoCH **正常出现**,且不再被位移/FVG 漏标;缠论摆点/笔显示不变。

- [ ] **Step 1: 停用主循环内(chan/zigzag 关)的旧逐bar检测**

定位:

```mql4
            if(!EnableChanOptimization && !EnableZigZagFilter) {
                // 两种过滤均未启用时，在循环中检测BOS/CHOCH
                if (i >= StructureLookback) DetectStructureBreaks(i, high, low, close);
            }
```

替换为:

```mql4
            // [SMC重写] BOS/CHoCH 改为摆点最终化后单次检测(见 DetectStructureBreaksSMC)
            // 旧逐bar检测已停用:
            // if(!EnableChanOptimization && !EnableZigZagFilter) {
            //     if (i >= StructureLookback) DetectStructureBreaks(i, high, low, close);
            // }
```

- [ ] **Step 2: 用单次 SMC 检测替换后置块**

定位整段:

```mql4
        if(EnableChanOptimization || EnableZigZagFilter) {
            // 清空旧结构，确保BOS/CHOCH仅基于过滤后的摆点
            structure_count = 0;
            // 基于过滤后的摆点重新检测BOS/CHOCH（swing_points已为过滤结果）
            for(int i = limit; i >= StructureLookback; i--) {
                DetectStructureBreaks(i, high, low, close);
            }
            // 刷新BOS/CHOCH缓冲区（主循环时structure_count=0未写入，此处补全）
            for(int i = limit; i >= 0; i--) {
                UpdateBuffers(i);
            }
            // 注意：分型标记绘制移到DrawGraphicalObjects之后，避免被清除
        }
        // --- 摆点后置过滤结束 ---
```

替换为:

```mql4
        // [SMC重写] 标准BOS/CHoCH:在最终摆点上单次检测(覆盖两种路径)
        // 只读摆点;只写structure_zones;不动缠论与g_market_trend
        DetectStructureBreaksSMC(high, low, close);
        // 刷新BOS/CHoCH等缓冲区
        for(int sb = limit; sb >= 0; sb--) {
            UpdateBuffers(sb);
        }
        // --- 摆点后置处理结束 ---
```

> 说明:`DetectStructureBreaksSMC` 内部已 `structure_count=0` 重建,且无论 chan/zigzag 开关都执行,统一两路径。此调用点在 `FilterSwingPointsByZigZag()`/`FilterSwingPointsByChan()` 之后,摆点已分类最终化。

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:BOS/CHoCH 出现;相比之前无 FVG/弱位移的破位也能标出。**缠论摆点连线/分型显示应完全不变**(对比改前截图)。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): wire DetectStructureBreaksSMC (replace gated per-bar detection)"
```

---

### Task 4: 修复结构线显示(虚线对已存在对象生效)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`DrawStructureZone` 创建结构射线处)

验收点:BOS = 虚线、CHoCH = 实线,且**已存在的旧线也会更新为正确样式**(不再因 ObjectCreate 失败而保持旧样式)。

- [ ] **Step 1: 把样式设置移出 `if(ObjectCreate())`,对已存在对象也生效**

定位:

```mql4
    // 创建趋势线并设为向右射线
    if(ObjectCreate(0, obj_name, OBJ_TREND, 0, ray_start_time, zone.top_price, ray_dir_time, zone.top_price))
    {
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
        // [v1.72] 对齐chart.html:BOS虚线、CHoCH实线
        ObjectSetInteger(0, obj_name, OBJPROP_STYLE, (type_name == "BOS") ? STYLE_DASH : STYLE_SOLID);
        // 尽量兼容：开启右侧射线
        ObjectSetInteger(0, obj_name, OBJPROP_RAY, true);
        ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);
    }
```

替换为:

```mql4
    // 创建趋势线并设为向右射线([v1.72]修复:样式对新建/已存在对象都生效)
    ObjectCreate(0, obj_name, OBJ_TREND, 0, ray_start_time, zone.top_price, ray_dir_time, zone.top_price);
    ObjectMove(0, obj_name, 0, ray_start_time, zone.top_price);
    ObjectMove(0, obj_name, 1, ray_dir_time,  zone.top_price);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
    // 对齐chart.html:BOS虚线、CHoCH实线
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, (type_name == "BOS") ? STYLE_DASH : STYLE_SOLID);
    ObjectSetInteger(0, obj_name, OBJPROP_RAY, true);
    ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:BOS 明确为**虚线**,CHoCH 为实线(含历史已画的线)。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "fix(mq4): apply structure line style to existing objects (BOS dash now visible)"
```

---

### Task 5: 验证清单追加 + 隔离回归

**Files:**
- Modify: `docs/SMC指标_v1.71_对齐标准_验证清单.md`

- [ ] **Step 1: 追加 SMC 结构重写验证章节**

在文件末尾追加:

```markdown

---

## SMC 结构重写验证(v1.72,标准 BOS/CHoCH)

适用:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`

**SMC 规范符合性(主):**
| # | 样本 | 期望 |
|---|------|------|
| 1 | 上升段收盘破前摆高 | 标 **BOS↑**(虚线) |
| 2 | 上升段首次收盘破被保护摆低 | 标 **CHoCH↓**(实线),bias 翻转下降 |
| 3 | 反转(下降)后顺势破前摆低 | 标 **BOS↓** |
| 4 | 同一段内不应出现连续多个同向 CHoCH | bias 翻转天然保证 |
| 5 | 仅影线触及、收盘未破(ConfirmBreakClose=true) | **不**标破位 |

**缠论隔离回归(必须):** 对比重写前后截图,**摆点连线、分型、笔显示完全不变**。

**参照(辅):** chart.html 看趋势/方向同向即可(数量/位置因摆点不同可不等)。

**回退:** 改用 v1.71 文件;或恢复调用旧 `DetectStructureBreaks`(仍保留在文件中,未删除)。
```

- [ ] **Step 2: Commit**

```bash
git add docs/SMC指标_v1.71_对齐标准_验证清单.md
git commit -m "docs: add v1.72 SMC structure rewrite verification + Chan isolation regression"
```

---

## Self-Review(规划者自检)

**Spec 覆盖**:
- §2 隔离原则 → Task 1 审计 + Task 2 函数设计(只读摆点/不写 g_market_trend/不写 is_broken)✓
- §3 bias 状态机 BOS/CHoCH 定义 → Task 2 `DetectStructureBreaksSMC` ✓
- §4 去掉位移/FVG/MA21/受保护gate → Task 3 用新检测器替换旧(新检测器不含这些门控)✓;保留收盘确认 → `FindBreakBarSMC` 用 `ConfirmBreakClose` ✓
- §5 显示(虚线 bug + BOS虚线/CHoCH实线)→ Task 4 ✓
- §6 验证(SMC 规范样本 + 缠论隔离回归 + chart.html 参照)→ Task 5 ✓
- §7 文件 v1.72 ✓

**占位符扫描**:无 TBD;每个改码步骤含完整代码。

**类型一致性**:
- `g_smc_bias`(int,Task2 定义)在 `DetectStructureBreaksSMC` 使用 ✓
- `FindBreakBarSMC(double,bool,int,int,&high,&low,&close)` 定义(Task2)与调用(Task2 内)签名一致 ✓
- `DetectStructureBreaksSMC(&high,&low,&close)` 定义(Task2)与调用(Task3)签名一致 ✓
- `AddStructureZone(bar, price, is_bullish, structure_type, swing_bar)` 用法与既有定义一致(structure_type 0=BOS/1=CHoCH)✓
- `swing_points[].is_high / .structure_type / .bar_index / .price` 均为既有字段 ✓

**执行注意**:
- 行号会漂移,编辑前 Grep 锚点。
- Task 3 接线后若 BOS/CHoCH 不出现:优先确认 `DetectStructureBreaksSMC` 调用点在摆点分类(`ReclassifySwingPoints`/Filter)之后;并确认 `swing_points` 在该点已填充。
- 旧 `DetectStructureBreaks`/`FindLatestUnbrokenStructure` 保留在文件中(未删),作回退;不再被调用。
