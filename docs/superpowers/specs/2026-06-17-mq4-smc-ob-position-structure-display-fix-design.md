# MQ4 SMC · OB 位置 + BOS/CHoCH 显示修正设计

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`
更新日期:2026-06-17
定义参照:用户提供的 SMC OB 定义 + `dashboard/chart.html`

---

## 1. 背景

Phase 1–2 测试发现三处与 SMC 标准定义不符的定位/显示问题(均不涉及缠论体系):

1. **BOS 不显示虚线**。
2. **OB 锚点位置错误**(锚到了冲击之后,而非冲击之前)。
3. **BOS/CHoCH 线起点**用被破摆点,而 chart.html 用突破点。

OB 方向判断本身正确(牛 OB=阴线、熊 OB=阳线),仅搜索位置反了。

## 2. 根因(已核对代码)

1. **虚线**:MT4 趋势线对象当 `OBJPROP_WIDTH ≥ 2` 时**忽略线型,强制实线**。当前结构线 `WIDTH=2` → `STYLE_DASH` 不渲染。
2. **OB 位置**:`IdentifyOrderBlocks` 搜索 `for(i=current_bar-1; i>=current_bar-5; i--)`。本指标 index 越大越旧,`current_bar-1` 是**更新**侧(冲击之后)。而 OB(冲击前最后一根反向 K 线)在**更旧**侧(`current_bar+1` 向上)。→ 搜索方向反。
3. **BOS/CHoCH 起点**:`DrawStructureZone` 用 `Time[zone.swing_bar]`(被破摆点)作射线起点;chart.html 从突破确认 bar 起。

## 3. 设计

### 3.1 OB 位置修正(只改方向)
`IdentifyOrderBlocks` 两处搜索循环改为向更旧方向找冲击前的反向 K 线:
- 牛 OB(`strong_bullish` 分支):`for(int i = current_bar+1; i <= MathMin(current_bar+5, ArraySize(close)-1); i++) if(close[i] < open[i]) { AddPOIZone(i, high[i], low[i], true, 1); break; }`
- 熊 OB(`strong_bearish` 分支):同结构,条件 `close[i] > open[i]`,`AddPOIZone(..., false, 1)`。
- 方向、区域(K 线全幅 high/low)、窗口大小(5)、强势判定条件均不变。

### 3.2 BOS/CHoCH 线起点 → 突破点
`DrawStructureZone` 中射线起点由被破摆点改为突破 bar:
- `ray_start_time = Time[zone.start_bar]`(突破确认 bar),价位仍 `zone.top_price`(被破摆点价),向右延伸。
- 保留 `swing_bar` 无效时的兜底逻辑(改为基于 `start_bar`)。

### 3.3 BOS 虚线生效
- BOS:`OBJPROP_WIDTH = 1` + `OBJPROP_STYLE = STYLE_DASH`。
- CHoCH:`OBJPROP_WIDTH = 2` + `OBJPROP_STYLE = STYLE_SOLID`。
- 按传入 `type_name`("BOS"/"CHOCH")分别设 width 与 style(承接已修复的"样式对已存在对象生效")。

## 4. 验证

- 编译 0 errors。
- **OB**:牛 OB 锚在强势上涨前最后一根阴线(底部/支撑);熊 OB 锚在强势下跌前最后一根阳线(顶部/阻力)。对照定义与 chart.html。
- **BOS 虚线、CHoCH 实线**;两者均从突破点起向右延伸。
- **缠论隔离**:摆点/笔/分型/趋势指示器显示不变(本次只动 OB 搜索方向与结构线绘制)。

## 5. 范围 / 兼容性 / 后续

- 文件 v1.72;缓冲区布局不变;不涉及缠论。
- 后续可选:OB"清扫流动性"高阶过滤(牛 OB 那根阴线先下破前低再反转)。

## 6. 风险

- OB 改搜索方向后仍是主循环生成(数量不变),只是锚点移到正确(更旧)侧;显示过滤(`HideLowQualityOB`/`+S`)照常 → 不会像结构驱动那样变空。
