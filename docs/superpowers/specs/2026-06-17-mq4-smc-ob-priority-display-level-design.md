# MQ4 SMC · OB 优先级展示 + 等级选择器 设计

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`
更新日期:2026-06-17

---

## 1. 背景(测试反馈)

1. BOS/CHoCH 线起点改回**被破摆点**(`swing_bar`)更习惯 → 回退。
2. OB 位置已改好;新增需求:设 N 个时按**优先级**展示重要 OB(老的重要 OB 不被新的普通 OB 挤掉)。
3. 新增 OB **等级选择器**:默认干净,需历史分析(失效/多次触及)时一键放开。

## 2. 设计

### A. 优先级 Top-N 展示
- **扩大 OB 存储池**:`poi_zones` 数组容量提到 `MaxFVGZones + MaxOBZones * 3`;OB 创建淘汰阈值(`AddPOIZone` 内)= `MaxOBZones * 3`(仍按最旧淘汰)。→ 较早的重要 OB 不会过早被挤出存储。
- **绘制按优先级取 Top-N**:`DrawGraphicalObjects` 的 OB 绘制段,在通过 `ShouldSkipOB` 过滤后的候选里,按 `quality_score` 从高到低**只画前 `MaxOBZones` 个**;其余跳过并删除其图形对象。
  - 优先级 = `quality_score`(已综合 Fresh/Tested 状态 + `+FVG` + `+S` 结构背书 + 趋势)。
  - 同分时较新者优先(`start_bar` 较小)。

### B. `OBDisplayLevel` 等级选择器(主显隐开关)
新增 `extern int OBDisplayLevel = 1;`,内部换算"可见质量阈值 `min_score` + 是否显示失效 `show_invalid`":

| 值 | 名称 | min_score | show_invalid | 含义 |
|----|------|-----------|--------------|------|
| 0 | 关键 | 0.80 | false | 只 A 级或 `+S` |
| **1** | **标准(默认)** | 0.60 | false | Fresh+Tested 或 `+S` |
| 2 | 扩展 | 0.40 | false | 再加 Weak/Watch |
| 3 | 全部(历史) | 0.00 | true | 含 Invalid 失效 |

**`ShouldSkipOB` 重写为按 `OBDisplayLevel` 判定:**
- 解析 level → `min_score`、`show_invalid`(上表)。
- 失效隐藏:`status==4 && !show_invalid` → skip。
- 质量过滤:`!has_structure_confluence && quality_score < min_score` → skip(即 **`+S` 结构背书的 OB 在 0/1/2 级始终显示**)。
- level 3:全部显示(min_score=0 且 show_invalid=true)。

**折叠旧参数**:移除 `HideLowQualityOB`、`MinVisibleOBQualityScore`、`RemoveInvalidOB` 三个 extern(其逻辑由 `OBDisplayLevel` 统一驱动),界面更简。

### C. 回退:BOS/CHoCH 线起点改回被破摆点
`DrawStructureZone` 射线起点改回以 `zone.swing_bar`(被破摆点)为主、`start_bar` 兜底。

## 3. 验证

- 编译 0 errors。
- **A**:设 `MaxOBZones=15`,图上稳定显示 15 个最高 `quality_score` 的 OB;走出新 OB 时,若旧的更重要(分更高)则旧的保留、新的普通 OB 不显示。
- **B**:`OBDisplayLevel=1` 默认干净(高质量);`=3` 显示全部含失效(历史复盘);`=0` 只剩最强。
- **C**:BOS/CHoCH 线从被破摆点起向右(旧观感)。
- 缠论显示不变。

## 4. 参数变更

| 参数 | 变更 |
|------|------|
| `OBDisplayLevel` | **新增**(int,默认 1) |
| `HideLowQualityOB` | **移除**(由 OBDisplayLevel 驱动) |
| `MinVisibleOBQualityScore` | **移除** |
| `RemoveInvalidOB` | **移除** |

净:-3 +1 = 参数减 2,且更直观。

## 5. 兼容性 / 风险

- 文件 v1.72;缓冲区布局不变;不涉及缠论。
- 移除三个旧 extern → 旧 `.set` 预设里这三项失效(无害,用 `OBDisplayLevel` 替代)。仅 `ShouldSkipOB` 引用它们,移除安全。
- 存储池增大 3 倍 → 内存/绘制开销略增,可接受(OB 数量级小)。
