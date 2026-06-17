# MQ4 SMC · OB/FVG 区域显示形式设计(减少遮挡)

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`
更新日期:2026-06-17

---

## 1. 背景

逻辑已满意。剩 UI 问题:OB/FVG 用**实色填充矩形**(`OBJPROP_FILL=true`)绘制,大面积遮挡 K 线与其它图形。MT4 对象**无 alpha 透明**,填充必为实色,故需改变区域的**显示形式**而非透明度。

## 2. 设计

新增参数:
- `extern int  ZoneDisplayStyle = 1;` —— 区域主形式。
- `extern bool ShowZoneRightTag = true;` —— 右侧质量色标(非填充样式下)。

`ZoneDisplayStyle`:
- **0 = 填充**:旧实色块(`FILL=true`)。
- **1 = 边框(默认)**:矩形只画边框,区域内 K 线完全可见。
- **2 = 上下边线**:仅画区域上/下两条水平射线。

### 右侧质量色标(`ShowZoneRightTag`,默认 true)
在 `ZoneDisplayStyle = 1 或 2` 时,额外在图表**最右侧空白(未来)区域**画一个小实色块:
- 位置:`tag_start = TimeCurrent() + PeriodSeconds()*1`,`tag_end = TimeCurrent() + PeriodSeconds()*4`(≈最后一根 K 线右侧 3 根 bar 宽,始终落在空白区,不挡 K 线)。
- 价位:`bottom..top`(=区域高度,便于对应价位);`FILL=true`;颜色 = `zone_color`(已含 OB 等级色 / FVG 多空色)。
- 对象名:`obj_name + "_Tag"`(`SMC_` 前缀,随 force_refresh 清理)。
- `ZoneDisplayStyle = 0`(填充)时不画此色标(已是实色)。
- MT4 限制:矩形按时间×价格锚定,无法精确 10px;用 ≈3 bar 宽近似(随缩放略变,但恒在空白区)。

> 效果叠加:**边框/上下线(看位置、不挡盘)+ 右侧小实色块(用颜色一眼区分质量)**。

`DrawPOIZone(zone_index, type_prefix, zone_color, label_text)` 按 `ZoneDisplayStyle` 分支:

| style | 矩形/线 | FILL | BACK | 备注 |
|-------|---------|------|------|------|
| 0 | `OBJ_RECTANGLE` | true | true | 现状;OB 仍加 `_Border`;不画右侧色标 |
| 1 | `OBJ_RECTANGLE` | **false** | false | 仅边框,宽度 1–2,用原色;**不**画 `_Border`;+右侧色标 |
| 2 | 两条 `OBJ_TREND` | — | true | top/bottom 价位水平射线,用原色;+右侧色标 |

> style 1/2 且 `ShowZoneRightTag=true` 时,追加 `obj_name+"_Tag"` 小实色块(见上节)。

- 适用于 **FVG 与 OB**(两者都经 `DrawPOIZone`)。
- style 2 的两条线对象名以 `SMC_` 前缀 + `_T`/`_B` 派生(基于现有 `obj_name`),确保被 `force_refresh` 的 `ObjectsDeleteAll("SMC_")` 清理。
- 标签绘制逻辑不变(沿用现有 `SMC_ZoneLabel_*`)。
- 颜色:边框/线条沿用现有 OB/FVG 配色(`zone_color`),不再大面积铺色。

## 3. 验证

- 编译 0 errors。
- `ZoneDisplayStyle=1`(默认):OB/FVG 仅边框,区域内 K 线清晰可见;**右侧空白区有小实色块**(颜色=质量),不挡 K 线;切换样式后无残留旧对象(force_refresh 清理)。
- `=0`:回到实色填充(无右侧色标);`=2`:仅上下两条水平线 + 右侧色标。
- `ShowZoneRightTag=false`:不画右侧色标。
- OB/FVG 的位置、等级标签、颜色语义不变;缠论/结构显示不变。

## 4. 范围 / 兼容性 / 风险

- 仅改 `DrawPOIZone` + 新增 1 个参数;不动检测逻辑、缓冲区、缠论。
- 风险:style 2 多对象命名/清理需确保 `SMC_` 前缀(已在设计中约束)。
- 边框模式下 `BACK=false` 使边框绘制在 K 线之上(更清晰);如发现边框压住 K 线影响读价,可改 `BACK=true`(后续微调,不在本次硬性范围)。
