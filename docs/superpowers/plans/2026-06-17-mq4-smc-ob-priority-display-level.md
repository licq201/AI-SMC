# MQ4 SMC · OB 优先级展示 + 等级选择器 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` 实现 OB 优先级 Top-N 展示、`OBDisplayLevel` 等级选择器(折叠旧 3 参数),并回退 BOS/CHoCH 线起点。

**Architecture:** 扩大 OB 存储池;`ShouldSkipOB` 改由 `OBDisplayLevel` 驱动;绘制时按 `quality_score` 取 Top-N。不涉及缠论。

**Tech Stack:** MQL4,无自动化测试框架。

> **MQL4 验证(通用)**:无 pytest。每任务 = MetaEditor F7 **0 errors** + 挂图核对。**行号会漂移,编辑前 Grep 锚点。**

---

## 文件结构

| 文件 | 动作 |
|------|------|
| `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` | 参数增删 + `ShouldSkipOB` 重写 + 存储池 + Top-N + 起点回退 |
| `docs/SMC指标_v1.71_OB标签与用法说明.md` | 更新参数说明 |

---

### Task 1: 回退 BOS/CHoCH 线起点为被破摆点

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`DrawStructureZone` 的 `ray_start_time`)

验收点:BOS/CHoCH 线从被破摆点(`swing_bar`)起向右延伸(旧观感)。

- [ ] **Step 1: 起点改回 swing_bar 为主**

定位(Grep `起点改为突破确认bar`)整段:

```mql4
    // [v1.72] 起点改为突破确认bar(对齐chart.html);被破摆点价位不变
    datetime ray_start_time;
    if(zone.start_bar >= 0 && zone.start_bar < Bars) {
        ray_start_time = Time[zone.start_bar];   // 从突破点开始
    } else if(zone.swing_bar >= 0 && zone.swing_bar < Bars) {
        ray_start_time = Time[zone.swing_bar];   // 兜底:摆点
    } else {
        ray_start_time = TimeCurrent();          // 最终兜底
    }
```

替换为:

```mql4
    // [v1.72] 起点回退为被破摆点(swing_bar),start_bar 兜底
    datetime ray_start_time;
    if(zone.swing_bar >= 0 && zone.swing_bar < Bars) {
        ray_start_time = Time[zone.swing_bar];   // 从被破摆点开始
    } else if(zone.start_bar >= 0 && zone.start_bar < Bars) {
        ray_start_time = Time[zone.start_bar];   // 兜底:突破点
    } else {
        ray_start_time = TimeCurrent();          // 最终兜底
    }
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:BOS/CHoCH 线从被破摆点起。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "fix(mq4): revert BOS/CHoCH line origin to broken swing point"
```

---

### Task 2: 新增 `OBDisplayLevel` 等级选择器 + 重写 ShouldSkipOB + 移除旧 3 参数

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(参数块;`ShouldSkipOB`)

验收点:`OBDisplayLevel` 控制 OB 显隐(0关键/1标准/2扩展/3全部);旧 3 参数移除后编译通过。

- [ ] **Step 1: 移除旧 3 参数,新增 OBDisplayLevel**

定位(Grep `extern bool   RemoveInvalidOB`)这三行:

```mql4
extern bool   RemoveInvalidOB        = true;     // 是否直接移除失效的OB [v1.71默认开:隐藏Invalid]
```
(以及 `HideLowQualityOB`、`MinVisibleOBQualityScore` 两行)

把这三行整体替换为:

```mql4
// OB 显示等级:0=关键(A级/+S) 1=标准(默认) 2=扩展(含走弱) 3=全部(含失效,历史分析)
extern int    OBDisplayLevel         = 1;        // [v1.72] OB显隐主开关
```

> 注:`RemoveInvalidOB`/`HideLowQualityOB`/`MinVisibleOBQualityScore` 仅被 `ShouldSkipOB` 引用,移除后 Step 2 重写该函数即可,无其它引用。

- [ ] **Step 2: 重写 ShouldSkipOB 为按 OBDisplayLevel 判定**

定位(Grep `bool ShouldSkipOB`)整个函数,替换为:

```mql4
bool ShouldSkipOB(int index, string &skip_reason)
{
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // [v1.72] 由 OBDisplayLevel 统一驱动:换算可见阈值与是否显示失效
        double min_score; bool show_invalid;
        switch(OBDisplayLevel) {
            case 0: min_score = 0.80; show_invalid = false; break; // 关键
            case 2: min_score = 0.40; show_invalid = false; break; // 扩展
            case 3: min_score = 0.00; show_invalid = true;  break; // 全部(历史)
            case 1:
            default: min_score = 0.60; show_invalid = false; break; // 标准
        }
        // 失效隐藏(除非等级3)
        if(poi_zones[index].status == 4 && !show_invalid) {
            skip_reason = "失效隐藏(等级<3)";
            return true;
        }
        // 质量过滤:+S结构背书的OB无视阈值始终显示
        if(!poi_zones[index].has_structure_confluence &&
           poi_zones[index].quality_score < min_score) {
            skip_reason = "低于显示等级";
            return true;
        }
    } else {
        // 传统逻辑（向后兼容）
        if(!ShowMitigatedPOI && poi_zones[index].is_mitigated) {
            skip_reason = "传统已触及";
            return true;
        }
    }
    return false;
}
```

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:`OBDisplayLevel=1` 默认干净;改 `=3` 显示全部含失效;`=0` 只剩最强。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): OBDisplayLevel selector drives OB visibility (fold 3 legacy params)"
```

---

### Task 3: 扩大 OB 存储池(×3)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`ArrayResize(poi_zones...)`;`AddPOIZone` 的 max_count)

验收点:存储更多 OB 候选,使 Top-N 有可选池;编译通过。

- [ ] **Step 1: 数组容量 ×3(OB 部分)**

定位:

```mql4
    ArrayResize(poi_zones, MaxFVGZones + MaxOBZones);
```

替换为:

```mql4
    ArrayResize(poi_zones, MaxFVGZones + MaxOBZones * 3); // [v1.72] OB存储池放大,显示由等级+Top-N控制
```

- [ ] **Step 2: AddPOIZone 中 OB 淘汰阈值放大**

定位:

```mql4
    int max_count = (type == 0) ? MaxFVGZones : MaxOBZones; // 0=FVG, 1=OB
```

替换为:

```mql4
    int max_count = (type == 0) ? MaxFVGZones : (MaxOBZones * 3); // [v1.72] OB存储池放大(显示数仍受MaxOBZones控制)
```

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。行为暂与之前接近(Top-N 未加前,会显示更多 OB —— 下个任务收口)。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): enlarge OB storage pool x3 for priority selection"
```

---

### Task 4: 绘制按优先级取 Top-N(MaxOBZones)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(新增 `ComputeOBDisplayCutoff`;OB 绘制循环加 cutoff 过滤)

验收点:设 `MaxOBZones=15` 时,图上只显示 `quality_score` 最高的 ~15 个 OB(老的更重要者保留)。

- [ ] **Step 1: 新增 cutoff 计算函数**

在 `ShouldSkipOB` 函数之后新增:

```mql4
//+------------------------------------------------------------------+
//| [v1.72] 计算OB显示优先级cutoff:返回第MaxOBZones高的quality_score   |
//| 候选数<=MaxOBZones时返回-1(全显示)。绘制时只画 score>=cutoff。      |
//+------------------------------------------------------------------+
double ComputeOBDisplayCutoff()
{
    double scores[];
    int n = 0;
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type != 1) continue;
        string r = "";
        if(ShouldSkipOB(i, r)) continue;   // 仅统计通过等级过滤的OB
        ArrayResize(scores, n + 1);
        scores[n] = poi_zones[i].quality_score;
        n++;
    }
    if(n <= MaxOBZones) return -1.0;        // 全部可显示
    ArraySort(scores);                       // 升序
    return scores[n - MaxOBZones];           // 第MaxOBZones高 = cutoff
}
```

- [ ] **Step 2: 绘制循环加 cutoff 过滤**

定位 OB 绘制循环开头(Grep `Order Block且未绘制或强制重绘`)。在该 `for(int i = 0; i < poi_count; i++)` 循环**之前**,加一行计算 cutoff;并在 `ShouldSkipOB` 通过之后加 cutoff 判定。

定位:

```mql4
        for(int i = 0; i < poi_count; i++) {
            if(poi_zones[i].poi_type == 1 && (!poi_zones[i].is_drawn || ForceOBRedraw)) { // Order Block且未绘制或强制重绘

                // 检查是否应该跳过
                string skip_reason = "";
                if(ShouldSkipOB(i, skip_reason)) {
                    ob_skipped++;
                    poi_zones[i].is_drawn = true;
```

替换为:

```mql4
        double ob_cutoff = ComputeOBDisplayCutoff(); // [v1.72] 优先级Top-N门槛
        for(int i = 0; i < poi_count; i++) {
            if(poi_zones[i].poi_type == 1 && (!poi_zones[i].is_drawn || ForceOBRedraw)) { // Order Block且未绘制或强制重绘

                // 检查是否应该跳过
                string skip_reason = "";
                if(ShouldSkipOB(i, skip_reason)) {
                    ob_skipped++;
                    poi_zones[i].is_drawn = true;
                    continue;
                }
                // [v1.72] 优先级Top-N:低于cutoff的低优先OB不画(保证留重要的)
                if(ob_cutoff > 0.0 && poi_zones[i].quality_score < ob_cutoff) {
                    ob_skipped++;
                    poi_zones[i].is_drawn = true;
                    continue;
                }
                {
```

> 注:原 `if(ShouldSkipOB...)` 块内紧接着是 `if(EnableOBDebug){...} continue; }`。上面替换在 `poi_zones[i].is_drawn = true;` 后用 `continue;` 收口该跳过分支,并新增 cutoff 跳过分支;随后用 `{` 开启原有"绘制信息"块。**编辑时以 Grep 锚点核对花括号配平**:确保原 skip 分支剩余的 `if(EnableOBDebug){...}` 调试打印被并入或删除,避免悬空。最简做法:保留原 skip 分支结构不动,仅在其 `continue;` 之后插入"cutoff 跳过分支",见下方 Step 2b 精确版。

- [ ] **Step 2b: 精确改法(优先采用,避免花括号问题)**

不替换整块,只做两处插入:
1. 在 `for(int i = 0; i < poi_count; i++) {` 这一行**之前**插入:

```mql4
        double ob_cutoff = ComputeOBDisplayCutoff(); // [v1.72] 优先级Top-N门槛
```

2. 在原 skip 分支的结尾 `continue;`(即 `if(ShouldSkipOB(...)){ ... continue; }` 的 `continue;`)**之后、获取显示信息之前**,插入 cutoff 跳过分支。定位:

```mql4
                    continue;
                }

                // 获取显示信息
                color zone_color = GetOBDisplayColor(i);
```

替换为:

```mql4
                    continue;
                }
                // [v1.72] 优先级Top-N:低于cutoff的低优先OB不画(保证留重要的)
                if(ob_cutoff > 0.0 && poi_zones[i].quality_score < ob_cutoff) {
                    ob_skipped++;
                    poi_zones[i].is_drawn = true;
                    continue;
                }

                // 获取显示信息
                color zone_color = GetOBDisplayColor(i);
```

- [ ] **Step 3: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图(`MaxOBZones=15`):稳定显示约 15 个最高质量 OB;新出现的普通 OB 不会挤掉更重要的旧 OB。

- [ ] **Step 4: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): draw top-N OB by quality (priority display, keep important ones)"
```

---

### Task 5: 更新 OB 用法文档

**Files:**
- Modify: `docs/SMC指标_v1.71_OB标签与用法说明.md`

- [ ] **Step 1: 用 OBDisplayLevel 替换旧参数说明**

定位文档中"智能过滤开关"小节(Grep `HideLowQualityOB`),把该表替换为:

```markdown
## 4. OB 展示等级 + 优先级

**`OBDisplayLevel`(默认 1)** —— 一个参数控制显隐:
| 值 | 名称 | 显示 |
|----|------|------|
| 0 | 关键 | 只 A 级或 `+S` |
| 1 | 标准(默认) | Fresh+Tested 或 `+S` |
| 2 | 扩展 | 再加 Weak/Watch |
| 3 | 全部(历史) | 含 Invalid 失效区 |

**优先级 Top-N**:当通过等级过滤的 OB 多于 `MaxOBZones` 时,按 `quality_score` 只显示最重要的 `MaxOBZones` 个(老的高质量 OB 不会被新的普通 OB 挤掉)。

> 旧参数 `HideLowQualityOB`/`MinVisibleOBQualityScore`/`RemoveInvalidOB` 已由 `OBDisplayLevel` 取代。
```

- [ ] **Step 2: Commit**

```bash
git add docs/SMC指标_v1.71_OB标签与用法说明.md
git commit -m "docs: update OB usage for OBDisplayLevel + priority Top-N"
```

---

## Self-Review(规划者自检)

**Spec 覆盖**:
- A 优先级 Top-N → Task 3(存储池)+ Task 4(cutoff)✓
- B `OBDisplayLevel` + 折叠旧参数 → Task 2 ✓
- C 回退 BOS 起点 → Task 1 ✓
- 文档 → Task 5 ✓

**占位符扫描**:无 TBD;每改码步骤含完整代码。Task 4 提供 Step 2b 精确改法避免花括号歧义。

**类型一致性**:
- `OBDisplayLevel`(int,Task2 定义)在 `ShouldSkipOB`(Task2)使用 ✓
- `ComputeOBDisplayCutoff()`(double,Task4 定义)在绘制循环(Task4)调用 ✓
- 移除的 `RemoveInvalidOB/HideLowQualityOB/MinVisibleOBQualityScore` 仅在被重写的 `ShouldSkipOB` 中引用(Task2 一并去除)✓
- `quality_score`/`has_structure_confluence`/`status`/`poi_type` 均既有字段 ✓
- `ArraySort` 默认升序;cutoff 取 `scores[n-MaxOBZones]`(第 MaxOBZones 高)✓

**执行注意**:行号漂移,Grep 锚点;Task 4 用 Step 2b;任务顺序 1→5。
