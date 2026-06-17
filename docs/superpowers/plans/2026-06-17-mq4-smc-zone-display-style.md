# MQ4 SMC · OB/FVG 区域显示形式(边框+右侧色标)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` 增加 `ZoneDisplayStyle`(填充/边框/上下线)与 `ShowZoneRightTag`(右侧质量色标),减少 OB/FVG 对 K 线的遮挡。

**Architecture:** 仅改 `DrawPOIZone`(按样式分支绘制 + 右侧色标)与 `RemoveOldestPOIZoneByType`(清理新对象);新增 2 个参数。不动检测逻辑/缠论。

**Tech Stack:** MQL4,无自动化测试框架。

> **MQL4 验证(通用)**:无 pytest。每任务 = MetaEditor F7 **0 errors** + 挂图核对。**行号会漂移,编辑前 Grep 锚点。**

---

## 文件结构

| 文件 | 动作 |
|------|------|
| `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4` | +2 参数;改 `DrawPOIZone`;改 `RemoveOldestPOIZoneByType` |
| `docs/SMC指标_v1.71_OB标签与用法说明.md` | 增加区域显示形式说明 |

---

### Task 1: 新增参数 `ZoneDisplayStyle` + `ShowZoneRightTag`

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(参数块)

- [ ] **Step 1: 新增两个参数**

定位(Grep `extern bool   ShowOBQualityGrade`)该行,在其后插入:

```mql4
// --- G4. 区域显示形式 (v1.72) ---
extern int    ZoneDisplayStyle  = 1;     // OB/FVG区域:0=填充 1=边框(默认) 2=上下边线
extern bool   ShowZoneRightTag  = true;  // 右侧空白区画质量色标(仅边框/上下线样式)
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors(参数新增,未使用,行为不变)。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): add ZoneDisplayStyle + ShowZoneRightTag params"
```

---

### Task 2: `DrawPOIZone` 按样式分支 + 右侧色标

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`DrawPOIZone` 的矩形创建块)

验收点:`ZoneDisplayStyle=1` 仅边框(K线可见)+ 右侧色标;`=0` 填充;`=2` 上下线 + 右侧色标。

- [ ] **Step 1: 替换矩形创建块**

定位(Grep `// 创建矩形`)整段(从 `// 创建矩形` 到其闭合 `}`,即下列内容):

```mql4
    // 创建矩形
    if(ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, start_time, zone.bottom_price, end_time, zone.top_price))
    {
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
        ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);  // 增加边框宽度
        ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);

        // 为OB区域添加更强的边框以提高可见性
        if(StringFind(obj_name, "OB") >= 0) {
            // 创建边框对象增强可见性
            string border_name = obj_name + "_Border";
            if(ObjectCreate(0, border_name, OBJ_RECTANGLE, 0, start_time, zone.bottom_price, end_time, zone.top_price)) {
                ObjectSetInteger(0, border_name, OBJPROP_COLOR, zone_color);
                ObjectSetInteger(0, border_name, OBJPROP_BACK, false);
                ObjectSetInteger(0, border_name, OBJPROP_FILL, false);
                ObjectSetInteger(0, border_name, OBJPROP_WIDTH, 3);
                ObjectSetInteger(0, border_name, OBJPROP_STYLE, STYLE_SOLID);
            }
        }
    }
```

替换为:

```mql4
    // [v1.72] 区域显示形式:0填充 / 1边框 / 2上下线
    if(ZoneDisplayStyle == 2) {
        // 上下两条水平射线
        string top_name = obj_name + "_T";
        string bot_name = obj_name + "_B";
        if(ObjectCreate(0, top_name, OBJ_TREND, 0, start_time, zone.top_price, end_time, zone.top_price)) {
            ObjectSetInteger(0, top_name, OBJPROP_COLOR, zone_color);
            ObjectSetInteger(0, top_name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, top_name, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, top_name, OBJPROP_RAY_RIGHT, true);
            ObjectSetInteger(0, top_name, OBJPROP_BACK, true);
        }
        if(ObjectCreate(0, bot_name, OBJ_TREND, 0, start_time, zone.bottom_price, end_time, zone.bottom_price)) {
            ObjectSetInteger(0, bot_name, OBJPROP_COLOR, zone_color);
            ObjectSetInteger(0, bot_name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, bot_name, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, bot_name, OBJPROP_RAY_RIGHT, true);
            ObjectSetInteger(0, bot_name, OBJPROP_BACK, true);
        }
    } else {
        // 矩形:style0=填充 / style1=边框
        bool do_fill = (ZoneDisplayStyle == 0);
        if(ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, start_time, zone.bottom_price, end_time, zone.top_price))
        {
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
            ObjectSetInteger(0, obj_name, OBJPROP_BACK, do_fill);          // 填充置后/边框置前
            ObjectSetInteger(0, obj_name, OBJPROP_FILL, do_fill);
            ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, do_fill ? 2 : 1);
            ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);

            // 仅填充样式下为OB加强边框
            if(do_fill && StringFind(obj_name, "OB") >= 0) {
                string border_name = obj_name + "_Border";
                if(ObjectCreate(0, border_name, OBJ_RECTANGLE, 0, start_time, zone.bottom_price, end_time, zone.top_price)) {
                    ObjectSetInteger(0, border_name, OBJPROP_COLOR, zone_color);
                    ObjectSetInteger(0, border_name, OBJPROP_BACK, false);
                    ObjectSetInteger(0, border_name, OBJPROP_FILL, false);
                    ObjectSetInteger(0, border_name, OBJPROP_WIDTH, 3);
                    ObjectSetInteger(0, border_name, OBJPROP_STYLE, STYLE_SOLID);
                }
            }
        }
    }

    // [v1.72] 右侧质量色标:非填充样式下,在最后K线右侧空白区画小实色块(颜色=质量色)
    if(ShowZoneRightTag && ZoneDisplayStyle != 0) {
        string tag_name = obj_name + "_Tag";
        datetime tag_start = TimeCurrent() + PeriodSeconds() * 1;
        datetime tag_end   = TimeCurrent() + PeriodSeconds() * 4;
        if(ObjectCreate(0, tag_name, OBJ_RECTANGLE, 0, tag_start, zone.bottom_price, tag_end, zone.top_price)) {
            ObjectSetInteger(0, tag_name, OBJPROP_COLOR, zone_color);
            ObjectSetInteger(0, tag_name, OBJPROP_BACK, false);
            ObjectSetInteger(0, tag_name, OBJPROP_FILL, true);
            ObjectSetInteger(0, tag_name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, tag_name, OBJPROP_STYLE, STYLE_SOLID);
        }
    }
```

> 标签块(`SMC_ZoneLabel_*`)保持不变,紧随其后。

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:`ZoneDisplayStyle=1` 仅边框 + 右侧空白小色块;`=0` 填充;`=2` 上下线 + 右侧色标;`ShowZoneRightTag=false` 无色标。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "feat(mq4): DrawPOIZone outline/lines styles + right-edge quality color tag"
```

---

### Task 3: 清理新对象(trim 时删除 _T/_B/_Tag/_Border)

**Files:**
- Modify: `mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`(`RemoveOldestPOIZoneByType`)

验收点:OB/FVG 被滑窗淘汰时,其边框/上下线/色标对象一并删除,不留孤儿。

- [ ] **Step 1: 扩展删除**

定位:

```mql4
    ObjectDelete(obj_name);
    ObjectDelete(label_name);
```
(在 `RemoveOldestPOIZoneByType` 内,`type_prefix`/`obj_name`/`label_name` 之后)

替换为:

```mql4
    ObjectDelete(obj_name);
    ObjectDelete(label_name);
    // [v1.72] 一并删除衍生对象(边框/上下线/右侧色标)
    ObjectDelete(obj_name + "_Border");
    ObjectDelete(obj_name + "_T");
    ObjectDelete(obj_name + "_B");
    ObjectDelete(obj_name + "_Tag");
```

- [ ] **Step 2: 编译验证(用户执行)**

MetaEditor F7。Expected: 0 errors。挂图:长时间运行后无残留的孤儿色标/线。

- [ ] **Step 3: Commit**

```bash
git add mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4
git commit -m "fix(mq4): delete derived zone objects (_Border/_T/_B/_Tag) on POI trim"
```

---

### Task 4: 文档补充区域显示形式

**Files:**
- Modify: `docs/SMC指标_v1.71_OB标签与用法说明.md`

- [ ] **Step 1: 追加"区域显示形式"小节**

在文档"颜色速查"小节(Grep `## 5. 颜色速查`)之前插入:

```markdown
## 4b. 区域显示形式(减少遮挡)[v1.72]

| 参数 | 默认 | 作用 |
|------|------|------|
| `ZoneDisplayStyle` | 1 | 0=填充 / **1=边框(K线可见)** / 2=上下边线 |
| `ShowZoneRightTag` | true | 在图表最右侧空白区画小实色块,用颜色一眼区分质量(仅边框/上下线样式) |

- 默认:OB/FVG 只画边框,不挡 K 线;右侧空白处有小色块表示质量颜色。
- 想要旧的实色块 → `ZoneDisplayStyle=0`;只看上下边界 → `=2`;不要右侧色标 → `ShowZoneRightTag=false`。
- MT4 限制:右侧色块按"时间×价格"锚定,宽度≈3 根 bar(非精确像素),始终落在空白区。
```

- [ ] **Step 2: Commit**

```bash
git add docs/SMC指标_v1.71_OB标签与用法说明.md
git commit -m "docs: document ZoneDisplayStyle + ShowZoneRightTag"
```

---

## Self-Review(规划者自检)

**Spec 覆盖**:
- `ZoneDisplayStyle` 0/1/2 → Task 1(参数)+ Task 2(分支)✓
- 右侧色标 `ShowZoneRightTag` → Task 1 + Task 2 ✓
- 对象清理(force_refresh 已覆盖;trim 补齐)→ Task 3 ✓
- 文档 → Task 4 ✓

**占位符扫描**:无 TBD;每改码步骤含完整代码。

**类型一致性**:
- `ZoneDisplayStyle`(int)、`ShowZoneRightTag`(bool)在 Task1 定义、Task2 使用 ✓
- 对象名 `obj_name`/`obj_name+"_T"/"_B"/"_Tag"/"_Border"` 在 Task2 创建、Task3 删除一致;均 `SMC_` 前缀(随 force_refresh 清理)✓
- `zone_color`/`start_time`/`end_time`/`zone.top_price`/`zone.bottom_price` 均为 `DrawPOIZone` 内既有变量 ✓

**执行注意**:行号漂移,Grep 锚点;style 2 不创建 `obj_name` 主矩形(用 `_T`/`_B`),force_refresh 与 Task3 均按名清理。
