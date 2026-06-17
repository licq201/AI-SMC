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

## 4. OB 展示等级 + 优先级 [v1.72]

**`OBDisplayLevel`(默认 1)** —— 一个参数控制 OB 显隐:

| 值 | 名称 | 显示内容 | 用途 |
|----|------|----------|------|
| 0 | 关键 | 只 A 级(分≥0.80)或 `+S` | 极简,只看最强 |
| **1** | **标准(默认)** | Fresh+Tested(分≥0.60)或 `+S` | 日常交易 |
| 2 | 扩展 | 再加 Weak/Watch(分≥0.40) | 看走弱区 |
| 3 | 全部(历史) | 含 Invalid 失效区 | 历史复盘 |

> `+S` 结构背书的 OB 在 0/1/2 级**无视阈值始终显示**。

**优先级 Top-N**:当通过等级过滤的 OB 多于 `MaxOBZones` 时,按 `quality_score` 只显示**最重要的 `MaxOBZones` 个**——老的高质量 OB 不会被新的普通 OB 挤掉。

**微调:**
- 历史复盘看全部(含失效/多次触及)→ `OBDisplayLevel = 3`。
- 只看最强 → `OBDisplayLevel = 0`。
- 控制数量 → `MaxOBZones`(优先级保留最重要的那批)。

> 旧参数 `HideLowQualityOB` / `MinVisibleOBQualityScore` / `RemoveInvalidOB` 已由 `OBDisplayLevel` 取代。

---

## 4b. 区域显示形式(减少遮挡)[v1.72]

| 参数 | 默认 | 作用 |
|------|------|------|
| `ZoneDisplayStyle` | 1 | 0=填充 / **1=边框(K线可见)** / 2=上下边线 |
| `ShowZoneRightTag` | true | 在图表最右侧空白区画小实色块,用颜色一眼区分质量(仅边框/上下线样式) |

- 默认:OB/FVG 只画边框,不挡 K 线;右侧空白处有小色块表示质量颜色。
- 想要旧的实色块 → `ZoneDisplayStyle=0`;只看上下边界 → `=2`;不要右侧色标 → `ShowZoneRightTag=false`。
- MT4 限制:右侧色块按"时间×价格"锚定,宽度≈3 根 bar(非精确像素),始终落在空白区。

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

1. **优先级**:默认 `OBDisplayLevel=1` 下图上留下的就是可用 OB(并按质量取 Top-`MaxOBZones`)。其中带 `+S`(结构背书)或 `+FVG`(供需共振)的 Fresh/Tested 为首选入场区。
2. **方向**:多头 OB 作为回调支撑(需求区),空头 OB 作为反弹阻力(供给区)。
3. **失效**:价格有效跌破多头 OB 底部(或突破空头 OB 顶部)→ 转 Watch/Invalid,不再作为支撑/阻力。
4. **与结构配合**:`+S` 表示该 OB 紧邻 BOS/CHoCH,属"结构驱动"的高确信区,优先级最高。
5. **与 chart.html 对照**:默认智能过滤后的 OB 集合应与标准(Python smc_core)的活跃 OB 基本一致。

---

## 7. 回退

- 想显示**全部 OB**(含失效/多次触及,历史复盘)→ `OBDisplayLevel=3`。
- 想完全回到旧逻辑(无生命周期)→ `EnableOBLifecycle=false`。
- 整体回退 → 使用旧文件 `SMC_OrderFlow_Indicator_v1.70_zig.mq4`。
