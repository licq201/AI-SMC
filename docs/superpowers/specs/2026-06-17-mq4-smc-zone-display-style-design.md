# MQ4 SMC · OB/FVG 区域显示形式设计(减少遮挡)

适用文件:`mql5/SMC_OrderFlow_Indicator_v1.72_zig.mq4`
更新日期:2026-06-17

---

## 1. 背景

逻辑已满意。剩 UI 问题:OB/FVG 用**实色填充矩形**(`OBJPROP_FILL=true`)绘制,大面积遮挡 K 线与其它图形。MT4 对象**无 alpha 透明**,填充必为实色,故需改变区域的**显示形式**而非透明度。

## 2. 设计

新增参数 `extern int ZoneDisplayStyle = 1;`:
- **0 = 填充**:旧实色块(`FILL=true`)。
- **1 = 边框(默认)**:矩形只画边框,区域内 K 线完全可见。
- **2 = 上下边线**:仅画区域上/下两条水平射线。

`DrawPOIZone(zone_index, type_prefix, zone_color, label_text)` 按 `ZoneDisplayStyle` 分支:

| style | 矩形/线 | FILL | BACK | 备注 |
|-------|---------|------|------|------|
| 0 | `OBJ_RECTANGLE` | true | true | 现状;OB 仍加 `_Border` |
| 1 | `OBJ_RECTANGLE` | **false** | false | 仅边框,宽度 1–2,用原色;**不**画 `_Border` |
| 2 | 两条 `OBJ_TREND` | — | true | top/bottom 价位水平射线,用原色 |

- 适用于 **FVG 与 OB**(两者都经 `DrawPOIZone`)。
- style 2 的两条线对象名以 `SMC_` 前缀 + `_T`/`_B` 派生(基于现有 `obj_name`),确保被 `force_refresh` 的 `ObjectsDeleteAll("SMC_")` 清理。
- 标签绘制逻辑不变(沿用现有 `SMC_ZoneLabel_*`)。
- 颜色:边框/线条沿用现有 OB/FVG 配色(`zone_color`),不再大面积铺色。

## 3. 验证

- 编译 0 errors。
- `ZoneDisplayStyle=1`(默认):OB/FVG 仅边框,区域内 K 线清晰可见;切换样式后无残留旧对象(force_refresh 清理)。
- `=0`:回到实色填充;`=2`:仅上下两条水平线。
- OB/FVG 的位置、等级标签、颜色语义不变;缠论/结构显示不变。

## 4. 范围 / 兼容性 / 风险

- 仅改 `DrawPOIZone` + 新增 1 个参数;不动检测逻辑、缓冲区、缠论。
- 风险:style 2 多对象命名/清理需确保 `SMC_` 前缀(已在设计中约束)。
- 边框模式下 `BACK=false` 使边框绘制在 K 线之上(更清晰);如发现边框压住 K 线影响读价,可改 `BACK=true`(后续微调,不在本次硬性范围)。
