# SMC 指标 OB/FVG 质量升级 · 使用说明

适用文件：`mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`
更新日期：2026-06-15
相关文档：设计 `docs/superpowers/specs/2026-06-15-mq4-ob-fvg-quality-design.md`、计划 `docs/superpowers/plans/2026-06-15-mq4-ob-fvg-quality.md`

---

## 1. 本次更新做了什么

把订单块（OB）从简单的「已触及 / 未触及」升级为**可解释的质量体系**：

1. **OB 生命周期状态机**默认开启，OB 会随价格演化在 5 个状态间流转。
2. **OB/FVG 同向重叠评分**：OB 与同方向的 FVG 价格重叠时质量更高，给出 A/B/C/D/X 等级。
3. **图表标签**显示状态、等级和是否 `+FVG`，例如 `Bullish OB+FVG [A]`。
4. **新增 `OB_Quality` 数据缓冲区（索引 9）**：把每个 OB 的质量分（0.0–1.0）暴露出来，供 EA 通过 `iCustom` 读取（本期只预留通道，未写消费 EA）。
5. 修复了一个旧 bug：OB 失效（Invalid）的判定方向之前写反了。
6. 现有 BOS / CHOCH / FVG / OB 的缓冲区（索引 0–8）编号与语义**完全不变**，旧 EA 不受影响。

---

## 2. OB 生命周期五状态

| 状态 | 含义 | 何时进入 |
|------|------|----------|
| **Fresh** | 全新、未被有效触及，质量最高 | OB 刚形成 |
| **Tested** | 首次被有效触及，仍可交易，质量略降 | Fresh 状态下价格首次触及区域 |
| **Weakened** | 多次被触及，质量下降，不再当强区 | 冷却后再次有效触及 |
| **Broken_Once** | 首次被反向收盘破坏，进入观察 | 被反向收盘击穿（含 Fresh 未触及即被一根大 K 线贯穿） |
| **Invalid** | 确认失效 | Broken_Once 后再次反向破坏（可选动能确认） |

**有效触及**：价格进入 OB 区间，且距上次触及已超过 `OBCooldownBars` 根 K 线（避免横盘震荡重复计数）。

**反向破坏方向**（关键，已修复）：
- 多头 OB：收盘价跌破 **底部**（`close < bottom`）。
- 空头 OB：收盘价突破 **顶部**（`close > top`）。

**假突破复活**：Broken_Once 后价格重新收回区间内，会回到 Weakened。

**Fresh 直接被击穿**：一根大 K 线收盘直接贯穿、还没登记过任何触及，OB 直接进入 Broken_Once（不会再误标为最高质量的 Fresh）。

---

## 3. 质量评分与等级

**基础分（按状态）**：Fresh 0.80 / Tested 0.65 / Weakened 0.45 / Broken_Once 0.20 / Invalid 0.00。

**加分项**：
- 与同向、未触及的 FVG 价格重叠：**+0.15**
- 重叠比例 ≥ `MinOBFVGOverlapRatio`（默认 0.20）：再 **+0.05**
- 与当前主趋势方向一致：**+0.05**

最终分 = `min(1.0, max(0.0, 基础分 + 加分))`。

**等级换算**：

| 等级 | 分数 |
|------|------|
| A | ≥ 0.80 |
| B | ≥ 0.60 |
| C | ≥ 0.40 |
| D | > 0.00 |
| X | = 0.00 |

> 只统计**同向**重叠：多头 OB 只和多头 FVG、空头 OB 只和空头 FVG。已被完全触及的 FVG 不参与加分。

---

## 4. 怎么看图表标签

标签格式：`方向 OB[+FVG][ 状态][ 等级]`

| 显示 | 解读 |
|------|------|
| `Bullish OB+FVG [A]` | 多头 Fresh OB，与同向 FVG 重叠，A 级，最优 |
| `Bullish OB [B]` | 多头 Fresh OB，无重叠，B 级 |
| `Bullish OB Tested [B]` | 已首次触及 |
| `Bullish OB Weak [C]` | 多次触及，质量下降 |
| `Bullish OB Watch [D]` | 已被首次破坏，观察中 |
| `Bullish OB Invalid [X]` | 已失效 |

**颜色**：
- Fresh：原始多/空 OB 色（最醒目）
- Tested：略暗（`clrSeaGreen` / `clrIndianRed`）
- Weakened：更暗（`clrDarkGreen` / `clrSaddleBrown`）
- Broken_Once：警戒橙（`clrOrange`）
- Invalid：灰色（`Mitigated_POI_Color`）

---

## 5. 参数说明

### 5.1 常用参数（OB 质量相关）

| 参数 | 默认 | 说明 |
|------|------|------|
| `EnableOBLifecycle` | **true** | OB 生命周期主逻辑总开关。设 `false` 可回退旧的「已触及/未触及」行为 |
| `OBCooldownBars` | 5 | 有效触及的冷却 K 线数 |
| `RequireMomentumOnBreak` | true | 失效确认是否要求动能 K 线 |
| `BreakMomentumATR` | 1.5 | 动能阈值：实体 / ATR ≥ 此值才算有动能 |
| `RemoveInvalidOB` | false | true=隐藏失效 OB；false=灰显保留 |

### 5.2 新增参数（OB/FVG 质量评分）

| 参数 | 默认 | 说明 |
|------|------|------|
| `EnableOBFVGConfluence` | true | 启用 OB/FVG 同向重叠评分 |
| `MinOBFVGOverlapRatio` | 0.20 | 重叠比例达此值额外加分 |
| `ShowOBQualityGrade` | true | 标签是否显示 `[A/B/C/D/X]` |
| `HideLowQualityOB` | false | 是否隐藏低质量 OB |
| `MinVisibleOBQualityScore` | 0.20 | `HideLowQualityOB=true` 时的可见性阈值 |

### 5.3 高级 / 调试参数（一般无需改）

`ShowOBLifecycleInfo`（默认 false，打开后打印状态转移日志）、`EnableOBDebug`、`ForceOBRedraw`。

---

## 6. 给 EA 用：读取 OB 质量分

新增缓冲区 **索引 9 = `OB_Quality`**（`DRAW_NONE`，不画线，纯数据）：
- 在每个 OB 的**锚点 K 线**上写入其 `quality_score`（0.0–1.0）。
- 其余 K 线为 `EMPTY_VALUE`。
- 同一锚点有多个 OB 时取最高分。
- 仅在 `EnableOBLifecycle=true` 时写入。

### EA / 脚本读取示例

```mql4
// 不传 input 参数时，iCustom 使用指标默认参数；9 = OB_Quality 缓冲区索引
double q = iCustom(Symbol(), Period(), "SMC_OrderFlow_Indicator_v1.70_zig", 9, shift);
if(q != EMPTY_VALUE) {
    // q 为该 K 线上 OB 的质量分；按需自行换算等级
    // A>=0.80, B>=0.60, C>=0.40, D>0, X==0
}
```

### 自带烟雾测试脚本

`mql5/TestReadOBQuality.mq4`：编译后放到 MT4 的 `MQL4\Scripts\`，拖到已挂指标的图表上运行，会在日志里打印扫描到的 OB 质量锚点并给出「通道可读 ✓」。

> 提示：现有 0–8 缓冲区语义未变 —— `0/1` BOS 上/下、`2/3` CHOCH、`4/5` FVG、`6/7` OB、`8` MA21、`9` OB_Quality（新增）。

---

## 7. 升级 / 回退

- **正常使用**：默认参数即可，OB 自动按质量分级显示。
- **看到的 OB 数量/颜色变了**：因为生命周期默认开启，这是预期行为。
- **想回到旧行为**：把 `EnableOBLifecycle` 设为 `false`，OB 退回「已触及=灰、未触及=原色」的旧逻辑，`OB_Quality` 缓冲区不写值。

---

## 8. 部署提醒

仓库里的 `.mq4` 只是源码。要在 MT4 上使用，需把
`mql5/SMC_OrderFlow_Indicator_v1.70_zig.mq4`
复制到 MT4 数据目录的 `MQL4\Indicators\`，在 MetaEditor 中编译（F7，0 错误）后再挂到 XAUUSD 图表。测试脚本放 `MQL4\Scripts\`。
