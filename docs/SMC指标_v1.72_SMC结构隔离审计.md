# SMC 结构重写 · 隔离依赖审计(v1.72)

日期:2026-06-17
目的:确认"新 SMC BOS/CHoCH 检测器"对缠论体系/趋势引擎零影响。

## 审计结果

| 全局 | 写点 | 读点 | 结论 |
|------|------|------|------|
| `swing_points[].is_broken` | 仅旧 `DetectStructureBreaks`(2345/2389/2421/2449);创建/Reclassify 重置 | `FindLatestUnbrokenStructure`(SMC)**以及 `UpdateTrendSequenceTracking` 趋势引擎(2044/2097/2100)** | ⚠ **被趋势引擎读取** |
| `g_market_trend` | 趋势引擎(`UpdateTrendSequenceTracking`/`UpdateTrendStateMachine`/`ReclassifySwingPoints`) | OB 质量加分(3322)、趋势指示器、旧 `DetectStructureBreaks` 只读 | 趋势引擎拥有,新检测器不写 |
| `g_last_break_up/down_bar` | 仅旧 `DetectStructureBreaks` | 仅已废弃 `OB_OnlyDrive`(2636/2658) | SMC 专用,安全 |
| `g_choch_*_occurred` | 仅旧 `DetectStructureBreaks` + 趋势引擎重置 | 仅旧 `DetectStructureBreaks` | SMC 专用,安全 |
| `structure_zones[]` | `AddStructureZone` | DrawStructureZone、UpdateBuffers、OB `+S` 共识(3367)| SMC 显示输出,可重建 |

## 关键结论(修正原计划)

**`is_broken` 不是纯 SMC 显示标记 —— 趋势引擎 `UpdateTrendSequenceTracking` 会读它来推断 `g_market_trend`。**
因此原计划"移除旧 `DetectStructureBreaks` 调用、新检测器不写 is_broken"会**改变 g_market_trend**(影响 OB 趋势加分、趋势指示器)。
注:笔/摆点的**形成**不受影响(is_broken 在分类之后才设,不参与笔定义),但趋势推断会变。

## 修正后的安全方案

**保留旧 `DetectStructureBreaks` 的运行(继续设 is_broken、喂趋势引擎),只把"SMC 结构显示"换成新检测器:**
- 上游流程(摆点、缠论、is_broken、趋势引擎、g_market_trend)**完全不动** → 缠论/趋势/OB 零变化。
- 在所有现有结构流程之后,追加调用 `DetectStructureBreaksSMC()`:它 `structure_count=0` 重建 `structure_zones[]`(标准 BOS/CHoCH),**覆盖**旧检测器写入的 structure_zones。
- 新检测器只读 `swing_points` 的 price/type/is_high(**不读也不写 is_broken**),自带 `g_smc_bias`。
- 仅 `structure_zones`(SMC 显示)+ 其下游(BOS/CHoCH 缓冲、OB `+S` 共识)随新结构变化——这些都是 SMC 侧,符合预期。

→ 实现上:**Task 3 改为"追加"而非"替换"**。
