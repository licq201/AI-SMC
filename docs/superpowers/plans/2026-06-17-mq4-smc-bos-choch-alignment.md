# MQ4 SMC 指标对齐标准 · Phase 2(BOS + CHoCH)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` 上把 BOS/CHoCH 对齐 Python/标准:CHoCH 不再强制要求 FVG(选择性放宽),并对齐 chart.html 的线型(BOS 虚线 / CHoCH 实线)。

**Architecture:** 定义校准 + 选择性放宽。保留 MT4 现有结构引擎(缠论/ZigZag 摆点 + 趋势驱动 BOS/CHoCH),仅放宽偏离标准的硬门控(`RequireFVG_CHOCH`),其余降噪门控(位移/受保护摆点/CHoCH 唯一性)作为有意差异保留。定义/方向/价位/确认 bar 经核对已与标准一致,无需改码。

**Tech Stack:** MQL4(MetaTrader 4 自定义指标),无自动化测试框架。

> **MQL4 验证方式(全程通用)**:无 pytest。每个任务验证 = ① MetaEditor 打开 v1.72 按 **F7,期望 0 errors**;② 挂图与 `dashboard/chart.html`(相同 symbol/TF,勾选 BOS/CHoCH)肉眼对照该任务的验收点。编译由用户在 MetaEditor 执行。
>
> **行号会漂移**:每次编辑前用 Grep 重新定位锚点,不要盲信行号。

---

## 文件结构

| 文件 | 责任 | 本计划动作 |
|------|------|-----------|
| `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` | 指标主体 | 修改(版本号、`RequireFVG_CHOCH` 默认、`DrawStructureZone` 线型) |
| `mql5/SMC_OrderFlow_Indicator_v1.71_zig.mq4` | 回退基线 | 不动 |
| `docs/SMC指标_v1.71_对齐标准_验证清单.md` | 验证清单 | 追加 Phase 2 章节 |

---

### Task 0: 版本号 bump 到 1.72

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`#property version`、描述行)

- [ ] **Step 1: 改版本号与描述**

定位(Grep `#property version`):把 `#property version   "1.71"` 改为:

```mql4
#property version   "1.72"
```

在该 `#property version` 行下方紧接的描述区,追加一行(放在 v1.71 描述之上):

```mql4
#property description "v1.72: BOS/CHoCH对齐标准—CHoCH不再强制FVG;BOS虚线/CHoCH实线对齐chart.html"
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors(行为与 v1.71 一致,仅版本字符串变化)。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "chore(mq4): bump v1.72, fork point for BOS/CHoCH alignment"
```

---

### Task 1: CHoCH 不再强制要求 FVG(核心改动)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(参数 `RequireFVG_CHOCH`)

验收点:此前因"无伴随 FVG"被漏标的 CHoCH,现在能标出,数量更接近 chart.html 的 CHoCH。

- [ ] **Step 1: 改 `RequireFVG_CHOCH` 默认值**

定位(Grep `RequireFVG_CHOCH     =`)参数声明行,改默认:

```mql4
extern bool   RequireFVG_CHOCH     = false;  // CHoCH是否要求伴随FVG [v1.72对齐标准:默认关]
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图对照 chart.html:CHoCH 数量增多且更贴近标准;BOS 不变(`RequireFVG_BOS` 本就 false)。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): CHoCH no longer requires accompanying FVG (align to standard)"
```

---

### Task 2: 线型对齐 chart.html(BOS 虚线 / CHoCH 实线)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`DrawStructureZone`)

验收点:BOS 射线为虚线、CHoCH 射线为实线 —— 与 chart.html(CHoCH solid / BOS dashed)一致。

- [ ] **Step 1: 把结构射线样式按类型区分**

定位(Grep `void DrawStructureZone`),在创建 `OBJ_TREND` 后设置样式处。当前为:

```mql4
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
```

替换为(BOS 虚线、CHoCH 实线;`type_name` 为 "BOS"/"CHOCH"):

```mql4
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
        // [v1.72] 对齐chart.html:BOS虚线、CHoCH实线
        ObjectSetInteger(0, obj_name, OBJPROP_STYLE, (type_name == "BOS") ? STYLE_DASH : STYLE_SOLID);
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:BOS 线为虚线,CHoCH 线为实线。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): BOS dashed / CHoCH solid structure lines (align chart.html)"
```

---

### Task 3: 验证清单追加 Phase 2 章节

**Files:**
- Modify: `docs/SMC指标_v1.71_对齐标准_验证清单.md`(追加 Phase 2 小节)

- [ ] **Step 1: 追加 Phase 2 验证内容**

在文件末尾追加:

```markdown

---

## Phase 2 · BOS/CHoCH 对齐验证(v1.72)

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`

| # | 场景 | v1.71 行为 | v1.72 期望 | chart.html 对照 |
|---|------|-----------|-----------|----------------|
| 1 | 无伴随 FVG 的 CHoCH | 漏标 | 标出 | chart.html 有 → 应一致 |
| 2 | 有 FVG 的 CHoCH | 标出 | 标出 | 一致 |
| 3 | BOS(顺势破摆点) | 标出 | 标出 + **虚线** | 一致 |
| 4 | CHoCH 线型 | 实线 | **实线** | chart.html CHoCH 实线 |

**定义核对**(应已一致):方向(BOS 破 HH=多/破 LL=空;CHoCH 破 HL=空/破 LH=多)、价位=被破摆点价、确认 bar=收盘突破 bar。

**已知有意差异(非缺陷)**:CHoCH 唯一性(每趋势一个)、受保护摆点验证、位移过滤(`RequireDisplacement`)—— 使 MT4 结构比标准库更干净;趋势未定义(0)时不标。

**回退**:`RequireFVG_CHOCH=true` 恢复严格 CHoCH;或改用 v1.71 文件。
```

- [ ] **Step 2: Commit**

```bash
git add docs/SMC指标_v1.71_对齐标准_验证清单.md
git commit -m "docs: add Phase 2 BOS/CHoCH verification checklist"
```

---

## Self-Review(规划者自检)

**Spec 覆盖**:
- §4.1 选择性放宽(`RequireFVG_CHOCH` 默认 false)→ Task 1 ✓;其余门控保留(无需改码)✓
- §4.2 定义校准(确认,无需改码)→ Task 3 文档核对 ✓
- §4.3 展示对齐(BOS 虚线/CHoCH 实线)→ Task 2 ✓;方向箭头已有(不动)✓;射线起点有意差异(保留)✓
- §4.4 验证方式 → Task 3 ✓
- §5 参数清单(`RequireFVG_CHOCH` 默认改、其余保留)→ Task 1 ✓
- §6 兼容性(缓冲区不变)✓;文件 v1.72(Task 0)✓

**占位符扫描**:无 TBD;每个改码步骤含完整代码。

**类型一致性**:`type_name`(string "BOS"/"CHOCH")在 Task 2 中的判定与 `DrawStructureZone` 调用方传入值一致(调用处:`DrawStructureZone(i, "BOS", ...)` / `DrawStructureZone(i, "CHOCH", ...)`)。`RequireFVG_CHOCH`(bool)默认改动与其使用处 `(!RequireFVG_CHOCH) || HasRecentFVG(...)` 一致。

**执行注意**:行号会漂移,编辑前 Grep 锚点。Task 2 编辑前确认 `DrawStructureZone` 内确实是 `STYLE_SOLID` 那三行(v1.72 应与 v1.71 相同)。
