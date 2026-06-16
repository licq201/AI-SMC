# SMC 指标 v1.71 · 对齐标准验证清单

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4`
参照基线:Python `src/smc/smc_core/`(smartmoneyconcepts)→ `dashboard/chart.html`
范围:Phase 1(FVG + OB)。BOS/CHoCH 见 Phase 2。

---

## 1. 如何并排验证

1. **MT4**:把 `SMC_OrderFlow_Indicator_v1.71_zig.mq4` 复制到 MT4 的 `MQL4\Indicators\`,MetaEditor 按 **F7 编译(0 errors)**,挂到 XAUUSD 图表。
2. **浏览器**:启动 dashboard 服务后打开 `dashboard/chart.html`,选 **相同 symbol 与周期(TF)**。
3. 两边对照同一段 K 线的 FVG / OB。

> chart.html 取数自 `/api/smc`(Python 标准检测器),即"事实标准"。

---

## 2. 核对样本(逐条确认 v1.71 标对/标错)

| # | 场景 | v1.70 行为 | v1.71 期望 | chart.html 对照 |
|---|------|-----------|-----------|----------------|
| 1 | 干净多头 FVG(三 K 无重叠缺口,中间阳线) | 标出 | 标出 | 同位置有 bullish FVG |
| 2 | **第三根暂停**的 FVG(缺口成立但第三根未延续) | **漏标** | **标出** | chart.html 有 → v1.71 应一致 |
| 3 | 有 BOS 的大阳线、其前的阴线 | 标出看涨 OB | 标出看涨 OB | 同位置有 bullish OB |
| 4 | **无 BOS** 的孤立大阳线 | **误标 OB** | **不生成 OB** | chart.html 无 → v1.71 应一致 |

---

## 3. 行为一致性检查

- **FVG 填充%**:价格部分进入缺口时,标签 `nn%` 单调增长;多头被**下探**填充、空头被**上行**填充。达 `FVGMitigationThreshold`(默认 1.0)即隐藏。
- **FVG 合并**:相邻同向、价格重叠的缺口合并为单个更宽区域(对齐 `join_consecutive`)。
- **OB 失效口径**:多头 OB 当 **影线** `low < 底部` 即破坏;空头 OB 当 `high > 顶部` 即破坏(对齐 chart.html 的 `low < ob.low` / `high > ob.high`)。
- **OB 可见集合**:v1.71 默认隐藏 Invalid 与低质量(Weakened/Broken),只显示 Fresh + Tested,应与 chart.html 的"active OB"基本一致。

---

## 4. 默认参数(干净显示)

| 参数 | v1.71 默认 | 说明 |
|------|-----------|------|
| `RemoveInvalidOB` | true | 隐藏失效 OB |
| `HideLowQualityOB` | true | 启用按质量分隐藏 |
| `MinVisibleOBQualityScore` | 0.55 | 留 Fresh+Tested,隐藏 Weakened/Broken/Invalid |
| `FVGQualityThreshold` | 0.0 | 关闭非标准 ATR 过滤 |
| `FVGMitigationThreshold` | 1.0 | 填充满即隐藏(设 0.5=半填充口径) |
| `FVG_JoinConsecutive` | true | 合并连续 FVG |

**微调**:只看最强 OB→`MinVisibleOBQualityScore=0.75`;看回全部→`HideLowQualityOB=false`+`RemoveInvalidOB=false`;FVG 更干净→`FVGMitigationThreshold=0.5`。

---

## 5. 回退

出问题可直接改用旧文件 `SMC_OrderFlow_Indicator_v1.70_zig.mq4`(v1.71 全部改动均在新文件,v1.70 未动)。

---

## 6. 已知差异(非缺陷)

- v1.71 仍保留 OB 五状态生命周期(Fresh/Tested/Weakened/Broken_Once/Invalid)作为增强,标准只有"mitigated 布尔"。显示上通过默认隐藏低质量/失效达到与标准等价的可见集合。
- BOS/CHoCH 尚未对齐(Phase 2),其判定仍比标准严(`RequireDisplacement`/`RequireFVG_CHOCH`/MA21 等)。
