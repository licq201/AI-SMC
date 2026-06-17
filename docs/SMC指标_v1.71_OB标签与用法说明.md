# SMC 指标 v1.71 · OB 标签与用法说明

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`
更新日期:2026-06-17

---

## 1. OB 标签结构

完整格式:`方向 OB[+FVG][+S][ 状态] [等级]`

例:`Bullish OB+FVG+S [A]` = 多头 OB,叠加同向 FVG,且紧邻结构突破,A 级(最优)。

| 片段 | 含义 |
|------|------|
| `Bullish` / `Bearish` | OB 方向(多 / 空) |
| `OB` | 订单块 |
| `+FVG` | 与**同向未填充 FVG** 价格重叠(供需共振) |
| `+S` | 紧邻同向 **结构突破(BOS/CHoCH)** ±15 根内(结构背书,更贴近标准 SMC) |
| 状态 | 见下表(Fresh 无后缀) |
| `[A/B/C/D/X]` | 质量等级(见 §3) |

---

## 2. OB 五状态(生命周期)

| 状态后缀 | 含义 | 颜色 | 可交易性 |
|---------|------|------|---------|
| (无,Fresh) | 全新、未被有效触及 | 原色(最醒目) | ★★★ 最优 |
| `Tested` | 首次被有效触及,仍有效 | 略暗(海绿/印度红) | ★★ 良好 |
| `Weak` | 多次触及,走弱 | 更暗(深绿/马鞍棕) | ★ 谨慎 |
| `Watch` | 已被首次破坏,观察中 | 警戒橙 | ☆ 仅观察 |
| `Invalid` | 已确认失效 | 灰色 | 不用(默认隐藏) |

---

## 3. 质量等级与评分

**基础分(按状态)**:Fresh 0.80 / Tested 0.65 / Weak 0.45 / Watch 0.20 / Invalid 0.00。

**加分项**:
- `+FVG` 同向 FVG 重叠:**+0.15**(重叠比例 ≥ `MinOBFVGOverlapRatio` 再 +0.05)
- `+S` 结构背书(邻近同向 BOS/CHoCH):**+0.15**
- 与当前主趋势同向:**+0.05**

**等级**:A ≥ 0.80 / B ≥ 0.60 / C ≥ 0.40 / D > 0 / X = 0。

> 实战优先级:`+FVG+S` 的 Fresh/Tested(A/B 级)> 普通 Fresh > Tested > 其余。

---

## 4. 智能过滤开关(只看高质量 OB)

新增"智能过滤",对齐 chart.html 只保留高质量 OB 的观感:

| 参数 | v1.71 默认 | 作用 |
|------|-----------|------|
| `HideLowQualityOB` | **true** | 开启智能过滤:**只显示 `+S` 结构背书 或 等级≥阈值** 的 OB |
| `MinVisibleOBQualityScore` | **0.60** | 高等级阈值(≥B 级);**`+S` 的 OB 无视此阈值,始终显示** |
| `RemoveInvalidOB` | **true** | 隐藏 Invalid(失效)OB |

**逻辑**:`HideLowQualityOB=true` 时,一个 OB 只要满足 **(`+S` 结构背书) 或 (质量分 ≥ 0.60)** 之一就显示,否则隐藏。
→ 结果:画面只留下"结构背书的"和"高等级的"OB,杂乱的低质量 OB 自动消失。

**微调:**
- 想看**全部** OB(含 Weak/Watch)→ `HideLowQualityOB = false`。
- 只留**最强 A 级 + 结构背书**→ `MinVisibleOBQualityScore = 0.80`。
- 嫌 OB/FVG 数量多 → 调小 `MaxOBZones` / `MaxFVGZones`(截图里设到 20 才会很密)。

---

## 5. 颜色速查

| 元素 | 颜色 |
|------|------|
| Fresh 多/空 OB | 原始多/空 OB 色 |
| Tested | 海绿 / 印度红 |
| Weak | 深绿 / 马鞍棕 |
| Watch | 橙色 |
| Invalid | 灰色(默认隐藏) |
| 未填充 FVG | 绿(多)/ 红(空),标签带 `nn%` 填充度 |

---

## 6. 实战用法(建议)

1. **优先级**:在 `HideLowQualityOB=true` 下,图上留下的就是可用 OB。其中带 `+S`(结构背书)或 `+FVG`(供需共振)的 Fresh/Tested 为首选入场区。
2. **方向**:多头 OB 作为回调支撑(需求区),空头 OB 作为反弹阻力(供给区)。
3. **失效**:价格有效跌破多头 OB 底部(或突破空头 OB 顶部)→ 转 Watch/Invalid,不再作为支撑/阻力。
4. **与结构配合**:`+S` 表示该 OB 紧邻 BOS/CHoCH,属"结构驱动"的高确信区,优先级最高。
5. **与 chart.html 对照**:默认智能过滤后的 OB 集合应与标准(Python smc_core)的活跃 OB 基本一致。

---

## 7. 回退

- 想回到"显示全部 OB(含低质量)"→ `HideLowQualityOB=false`、`RemoveInvalidOB=false`。
- 想完全回到旧逻辑(无生命周期)→ `EnableOBLifecycle=false`。
- 整体回退 → 使用旧文件 `SMC_OrderFlow_Indicator_v1.70_zig.mq4`。
