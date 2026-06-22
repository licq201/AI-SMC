# SMC 指标 v1.74 极端低点漏连修复记录

日期：2026-06-18

## 背景

在 XAUUSD+ M5 的极端下跌行情中，ZigZag/摆点连线没有连接到实际最低点。用户验证发现：

- 关闭 ZigZag 优化后，低点仍停在 B 点，没有到 A 点。
- 关闭缠论优化后，低点仍停在 B 点，只是后续摆点数量增加。
- 日志中缠论分型能看到真实低点记录，例如：

```text
fractal[39]: 底 bar_index=2351 original_bar=115 price=4219.12 time=2026.06.17 22:35
FilterSwingPointsByZigZag: pivot无匹配摆点 低 bar=115 price=4219.12
```

## 现象分层

本次排查把问题拆成三层：

1. 原始 swing 识别层：`IdentifySwingPoints()` 依赖 `IsSwingHigh/IsSwingLow` 和 `StructureLookback` 的左右确认。
2. 后置过滤层：`FilterSwingPointsByZigZag()`、`FilterSwingPointsByChan()` 会重写 `swing_points`。
3. 视觉绘制层：`DrawSwingConnections()` 只根据最终 `swing_points` 生成线段。

最终证据显示，真正导致最低点丢失的是第二层：

`CalculateZigZagPivots()` 已经识别出低点 pivot，但 `FilterSwingPointsByZigZag()` 没有在原始 `swing_points` 中匹配到同类型摆点，于是只打印 `pivot无匹配摆点`，没有把该 pivot 写回最终摆点集合。

## 误判与已撤回改动

排查过程中曾尝试过视觉层修补，包括：

- 虚拟摆点默认开启。
- 强制虚拟线使用实线/前景/Z-order。
- 最左侧视觉边界补锚。
- `[ZIGZAG_LINE]`、`[ZIGZAG_DRAW]` 等全量绘制日志。
- 普通虚拟笔默认关闭。

这些改动最终证明不是根因，已撤回。虚拟相关默认值已恢复：

- `ShowVirtualStroke = true`
- `EnableVirtualSwingExtension = false`
- `VirtualSwingExtension_Style = STYLE_DOT`

## 最终修复

### 1. ZigZag 过滤阶段

- 新增 `MakeSwingPointFromZigZagPivot()`。
- 当 ZigZag pivot 没有匹配到原始 swing 时，不再丢弃。
- 将该 pivot 合成为 `SwingPoint`，加入过滤后的摆点集合。
- 写回 `swing_points` 前按时间顺序重新排序。
- 后续继续调用 `ReclassifySwingPoints()`，让合成摆点获得 HH/HL/LH/LL 分类。

核心逻辑：

```text
ZigZag pivot 已确认
  -> 找得到原始 swing：保留原始 swing 元数据
  -> 找不到原始 swing：合成为 synthetic SwingPoint
  -> 合并排序
  -> ReclassifySwingPoints()
```

### 2. 缠论过滤阶段

用户进一步验证：关闭 ZigZag 优化、保留缠论优化时，最低点仍可能没有进入最终连线；日志中却能看到缠论底分型。这说明缠论也存在同类问题：

```text
缠论分型已确认关键低点
  -> 原始 swing_points 没有对应摆点
  -> FilterSwingPointsByChan() 只过滤已有 swing
  -> 分型没有被转成 SwingPoint
  -> 最终连线仍缺最低点
```

对应修复：

- 新增 `MakeSwingPointFromChanFractal()`。
- `FilterSwingPointsByChan()` 第一遍分型/MA21过滤后，扫描 `g_chan_fractals`。
- 若某个顶/底分型没有被同类型候选 swing 代表，则合成为 `SwingPoint`。
- 合成后重新按时间排序，再交给原有极点识别、成笔过滤、回溯机制处理。

这样不会绕过缠论笔规则，只是保证“已确认分型”不会因为原始 swing 缺失而永远无法参与成笔。

## 为什么关闭 ZigZag 后仍不正常

这不矛盾。

本次修复依赖 ZigZag pivot 作为补充事实源。开启 ZigZag 时，`CalculateZigZagPivots()` 能识别到最低点，所以可以把缺失 pivot 合成回 `swing_points`。

关闭 ZigZag 后，这个补充事实源不存在，最终只依赖原始 swing 识别和缠论过滤。如果原始 `IsSwingLow()` 因 `StructureLookback` 右侧确认、等低比较、窗口边界，或缠论处理后的 `original_bar` 映射没有生成对应 swing，那么最低点仍不会进入最终摆点集合。

因此，关闭 ZigZag 后的问题属于另一个上游缺口。v1.74 已补上缠论分型到 `SwingPoint` 的合成路径，用于覆盖“ZigZag 关闭但缠论开启”的场景。

若 ZigZag 和缠论同时关闭，则只剩原始 swing 识别：

- 原始 swing 识别没有覆盖真实极端低点；或
- `IsSwingLow()` 因右侧确认、等低比较、窗口边界等原因没有生成摆点。

这不应由视觉层修补，后续如需支持“双关闭”也不漏极值，应单独审计原始 swing 模型。

## 后续建议

方向：

1. 在 `IdentifySwingPoints()` 增加诊断，记录目标 bar 是否通过 `IsSwingLow()`，失败原因是左侧、右侧、边界还是等低。
2. 将 ZigZag、缠论、原始 swing 三个来源抽象成统一的“候选 pivot -> SwingPoint”管线，避免各自过滤后丢关键极值。
3. 为“双关闭”场景增加独立回归样例，确认原始 swing 模型是否应承担极端低点识别职责。

## 验证

本次保留的回归检查：

```text
python -m pytest tests/mql/test_smc_indicator_contract.py -q
```

验证结果：

```text
3 passed
```

MetaEditor 编译结果：

```text
SMC_OrderFlow_Indicator_v1.73_zig.mq4: 0 errors, 0 warnings
SMC_OrderFlow_Indicator_v1.74_zig.mq4: 0 errors, 0 warnings
```
