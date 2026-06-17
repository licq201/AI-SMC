# MQ4 SMC · OB 位置 + BOS/CHoCH 显示修正 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` 修正 OB 锚点搜索方向、BOS/CHoCH 线起点、BOS 虚线显示。

**Architecture:** 三处独立小修:OB 搜索改向更旧侧;结构线起点改用突破 bar;BOS 线宽改 1 使虚线生效。不涉及缠论。

**Tech Stack:** MQL4,无自动化测试框架。

> **MQL4 验证(通用)**:无 pytest。每任务 = MetaEditor F7 **0 errors** + 挂图核对。**行号会漂移,编辑前 Grep 锚点。**

---

## 文件结构

| 文件 | 动作 |
|------|------|
| `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` | 改 `IdentifyOrderBlocks`(2处循环)+ `DrawStructureZone`(起点+线宽/线型) |

---

### Task 1: OB 锚点搜索方向修正(冲击前的反向 K 线)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`IdentifyOrderBlocks` 两处搜索循环)

验收点:牛 OB 锚在强势上涨**前**最后一根阴线(更旧侧);熊 OB 锚在强势下跌**前**最后一根阳线。

- [ ] **Step 1: 修正牛 OB 搜索循环**

定位(Grep `寻找前面最近的看跌K线作为Order Block`)整段:

```mql4
        // 寻找前面最近的看跌K线作为Order Block
        for(int i = current_bar - 1; i >= MathMax(current_bar - 5, 0); i--) {
            if(close[i] < open[i]) { // 找到看跌K线
                AddPOIZone(i, high[i], low[i], true, 1);
```

替换为(向更旧方向 `current_bar+1` 搜索):

```mql4
        // [v1.72] 冲击之前(更旧侧)最后一根阴线作为看涨OB
        for(int i = current_bar + 1; i <= MathMin(current_bar + 5, ArraySize(close) - 1); i++) {
            if(close[i] < open[i]) { // 找到看跌K线(阴线)
                AddPOIZone(i, high[i], low[i], true, 1);
```

- [ ] **Step 2: 修正熊 OB 搜索循环**

定位(Grep `寻找前面最近的看涨K线作为Order Block`)整段:

```mql4
        // 寻找前面最近的看涨K线作为Order Block
        for(int i = current_bar - 1; i >= MathMax(current_bar - 5, 0); i--) {
            if(close[i] > open[i]) { // 找到看涨K线
                AddPOIZone(i, high[i], low[i], false, 1);
```

替换为:

```mql4
        // [v1.72] 冲击之前(更旧侧)最后一根阳线作为看跌OB
        for(int i = current_bar + 1; i <= MathMin(current_bar + 5, ArraySize(close) - 1); i++) {
            if(close[i] > open[i]) { // 找到看涨K线(阳线)
                AddPOIZone(i, high[i], low[i], false, 1);
```

> 注:两处循环体内的 `break;` 与 `EnableOBDebug` 打印保持不变,只改 `for` 头与注释。

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:牛 OB 出现在上涨起点下方(支撑/阴线),熊 OB 在下跌起点上方(阻力/阳线),与定义一致。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "fix(mq4): OB anchors the last opposite candle BEFORE the impulse (older side)"
```

---

### Task 2: BOS/CHoCH 线起点改用突破点

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`DrawStructureZone` 的 `ray_start_time` 计算)

验收点:BOS/CHoCH 线从**突破确认 bar** 起向右延伸(对齐 chart.html),不再从被破摆点起。

- [ ] **Step 1: 改射线起点为 start_bar**

定位(Grep `ray_start_time` 在 `DrawStructureZone` 内)整段:

```mql4
    datetime ray_start_time;
    if(zone.swing_bar >= 0 && zone.swing_bar < Bars) {
        ray_start_time = Time[zone.swing_bar];  // 从被突破的摆点开始
    } else {
        ray_start_time = Time[zone.start_bar];  // 备用：从突破发生点开始
        Print("SMC 警告: ", type_name, " 无效的swing_bar索引 (", zone.swing_bar, ")，射线起点改为突破点");
    }
```

替换为:

```mql4
    // [v1.72] 起点改为突破确认bar(对齐chart.html),被破摆点价位不变
    datetime ray_start_time;
    if(zone.start_bar >= 0 && zone.start_bar < Bars) {
        ray_start_time = Time[zone.start_bar];   // 从突破点开始
    } else if(zone.swing_bar >= 0 && zone.swing_bar < Bars) {
        ray_start_time = Time[zone.swing_bar];   // 兜底:摆点
    } else {
        ray_start_time = TimeCurrent();          // 最终兜底
    }
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:BOS/CHoCH 线起点位于突破 K 线处。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "fix(mq4): BOS/CHoCH line starts at break bar (align chart.html)"
```

---

### Task 3: BOS 虚线生效(线宽≤1)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`DrawStructureZone` 的 WIDTH/STYLE)

验收点:BOS = 虚线、CHoCH = 实线(MT4 仅在线宽≤1 时渲染虚线)。

- [ ] **Step 1: BOS 线宽改 1**

定位(Grep `对齐chart.html:BOS虚线`)当前两行:

```mql4
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
    // 对齐chart.html:BOS虚线、CHoCH实线
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, (type_name == "BOS") ? STYLE_DASH : STYLE_SOLID);
```

替换为:

```mql4
    // [v1.72] MT4仅在线宽<=1时渲染虚线:BOS宽1虚线 / CHoCH宽2实线
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, (type_name == "BOS") ? 1 : 2);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, (type_name == "BOS") ? STYLE_DASH : STYLE_SOLID);
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:BOS 明确为**虚线**,CHoCH 为实线。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "fix(mq4): BOS dashed by setting width=1 (MT4 renders dash only for width<=1)"
```

---

## Self-Review(规划者自检)

**Spec 覆盖**:
- §3.1 OB 位置(两处搜索方向)→ Task 1 ✓
- §3.2 BOS/CHoCH 起点 → Task 2 ✓
- §3.3 BOS 虚线(width=1)→ Task 3 ✓
- §4 验证 → 各任务 Step + 缠论隔离(本次只改 OB 搜索与结构线绘制,不触摆点/缠论)✓

**占位符扫描**:无 TBD;每改码步骤含完整代码。

**类型一致性**:
- `IdentifyOrderBlocks` 内 `current_bar`/`open/high/low/close`/`AddPOIZone(bar,top,bottom,is_bullish,type)` 用法与既有一致 ✓
- `DrawStructureZone` 内 `zone.start_bar`/`zone.swing_bar`/`type_name`("BOS"/"CHOCH")/`obj_name` 均既有 ✓
- Task 3 依赖 Task 2 之后的 `DrawStructureZone` 现状(WIDTH/STYLE 两行紧邻)— 编辑前 Grep 锚点确认 ✓

**执行注意**:行号漂移,Grep 锚点;三处互相独立,可分别编译验证。
