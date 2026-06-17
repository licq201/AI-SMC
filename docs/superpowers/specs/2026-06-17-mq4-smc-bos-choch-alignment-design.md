# MQ4 SMC 指标对齐标准 · Phase 2(BOS + CHoCH)设计

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(从修好的 v1.71 演进;v1.71 保留为回退基线)
基线参照:Python `src/smc/smc_core/structure.py`(基于 `smartmoneyconcepts.bos_choch`)+ `dashboard/chart.html`
更新日期:2026-06-17
前序:Phase 1(FVG+OB)`docs/superpowers/specs/2026-06-16-mq4-smc-fvg-ob-alignment-design.md`

---

## 1. 背景与目标

Phase 1 已把 FVG/OB 对齐标准,并让 OB 改为"结构突破事件驱动"(依赖 `structure_zones[]`)。Phase 2 处理结构本身:把 MQL4 的 **BOS/CHoCH** 检测与展示对齐到 Python/标准。

**对齐方式(用户选定):定义校准 + 选择性放宽。** 保留 MT4 更干净的结构引擎(缠论/ZigZag 摆点 + 趋势驱动检测),只把偏离标准的硬门控改为可选/默认关闭,确保定义/方向与标准一致 —— **不**刻意追求与标准库 `bos_choch` 逐条相等(该库偏吵,MT4 的额外过滤通常是有益降噪)。

**不改动 Python 生产逻辑**(walk-forward 验证过,CLAUDE.md 约束)。

---

## 2. 标准参照(Python/smartmoneyconcepts 口径)

来自 `structure.py`:`SMC.bos_choch(ohlc, swing_highs_lows)`,输出列 `BOS / CHOCH / Level / BrokenIndex`:
- BOS/CHOCH:1=bullish,-1=bearish。
- **Level**:被破结构水平的价格。
- **BrokenIndex**:突破被确认的 bar 索引(事件时间戳取此 bar)。
- 纯由摆点序列推导,**无** 位移过滤、**无** FVG 要求、**无** 受保护摆点验证、**不** 设 CHoCH 唯一性(每个确认 CHoCH 都标)。

`chart.html` 渲染:在 `sb.price`(被破水平)画水平线延伸到右侧,标签 `BOS ↑ / CHOCH ↓`(方向箭头),**CHoCH 实线 / BOS 虚线**区分,颜色 BOS 蓝、CHoCH 靛。

---

## 3. 现状代码事实(实现前必须知道)

`DetectStructureBreaks`(`SMC_OrderFlow_Indicator_v1.71_zig.mq4` ~2298):
- **趋势门控**:仅当 `g_market_trend`(1/-1)已确定时检测;趋势未定义(0)时不标(仅数据极初始,影响小)。
- BOS:顺势破最近未破摆点(上升破 HH / 下降破 LL),`ConfirmBreakClose=true` 用收盘确认。
- CHoCH:逆势首破(上升破 HL→bearish / 下降破 LH→bullish),用 `g_choch_*_occurred_in_*` 标志保证每趋势唯一。
- 额外门控:`IsDisplacementOK`(`RequireDisplacement`,实体比例≥`MinBodyRatio` 且 全幅/ATR≥`MinAtrMomentum`)、`RequireFVG_BOS`(默认 false)、`RequireFVG_CHOCH`(默认 **true**)、受保护摆点验证。

`DrawStructureZone`(~3742):`OBJ_TREND` 射线,从被破摆点(`swing_bar`)起向右,价位=被破水平;BOS/CHoCH **都 STYLE_SOLID**(仅颜色不同);标签 `type+↑/↓` 已带方向箭头。

`/api/smc` → `serialize_smc` 输出 `structure_breaks[{ts, price, break_type, direction}]`;`chart.html` 有 `tog-struct` 开关。→ 可视化验证可行。

定义映射核对(MQL4 ↔ 标准):方向、价位(被破摆点价=Level)、确认 bar(current_bar≈BrokenIndex)**均一致**。

---

## 4. 设计

### 4.1 选择性放宽(核心改动)
- **`RequireFVG_CHOCH`:`true` → `false`**(v1.71 默认)。CHoCH 不再要求伴随 FVG,对齐标准 —— 解决 MQL4 漏标无 FVG 的 CHoCH。
- `RequireFVG_BOS`:保持 `false`。
- **保留**为 MT4 有意的"更干净"行为(文档标注为与标准的有意差异,均为可选 knob):
  - `RequireDisplacement`=true(位移质量门)。若放宽 FVG 后仍漏标,再调低 `MinBodyRatio`/`MinAtrMomentum` 或关闭。
  - 受保护摆点验证。
  - CHoCH 唯一性(每趋势一个,翻转后记为 BOS,比标准库重复标记更正确)。

### 4.2 定义校准(确认,无需改码)
§3 已核对方向/价位/确认 bar 与标准一致。仅在文档记录映射表,无代码改动。

### 4.3 展示对齐 chart.html
- **线型区分**:`DrawStructureZone` 中 BOS 设 **`STYLE_DASH`**、CHoCH 设 **`STYLE_SOLID`**(当前都 SOLID)。按传入 `type_name`("BOS"/"CHOCH")判定。
- 方向箭头标签:已有,保持。
- 标签防重叠:结构标签按 `swing_bar` 定位通常已错开;若与区域标签仍重叠,后续微调(本期不强做)。
- 射线起点差异(MQL4 从被破摆点 / chart.html 从突破 bar):有意差异,保留。

### 4.4 验证方式
- `chart.html` 勾选 BOS/CHoCH,选相同 symbol/TF,与 MT4 v1.71 肉眼对照:BOS/CHoCH 的位置、方向、价位、数量级。
- 关键样本:**无 FVG 的 CHoCH** —— v1.70 漏标,v1.71 应标出,且 chart.html 也有。
- 验收:MetaEditor 编译 0 errors + 对照清单通过。

---

## 5. 参数变更清单

| 参数 | v1.70/Phase1 | Phase 2 | 说明 |
|------|------|------|------|
| `RequireFVG_CHOCH` | `true` | **`false`** | 对齐标准:CHoCH 不再要求 FVG |
| `RequireFVG_BOS` | `false` | `false` | 不变 |
| `RequireDisplacement` | `true` | `true` | 保留为可选降噪门(标注 deviation) |
| `MinBodyRatio` / `MinAtrMomentum` | 不变 | 不变 | 位移阈值,可按需调低 |

净改动:1 个默认值(`RequireFVG_CHOCH`)+ 1 处线型(BOS 虚线)。无新增参数。

---

## 6. 兼容性
- 缓冲区 0–9 布局不变。
- 仍在 v1.71 文件内演进,v1.70 保持回退基线。

---

## 7. 已知差异 / 后续(登记)
- **趋势门控**:趋势未定义(0)时不标 BOS/CHoCH(仅数据极初始);标准无此限制。属保留的引擎行为,如将来需要再单独处理。
- **CHoCH 唯一性 / 受保护摆点 / 位移过滤**:有意保留,使 MT4 结构比标准库更干净。
- 阶段 3(可选):参数冻结、生命周期简化(承接 Phase 1 §7)。
