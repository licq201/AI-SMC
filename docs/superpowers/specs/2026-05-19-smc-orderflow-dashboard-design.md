# SMC 订单流 Dashboard 展示设计

**日期**：2026-05-19  
**状态**：已确认设计方向，待实施计划  
**目标用户**：中文使用习惯的系统所有者，既想学习 SMC，也想快速判断当前行情是否满足交易条件。  

---

## 1. 背景

当前 `dashboard/index.html` 已有“SMC 阶段追踪”，数据来源是 `live_state.json` 中的 `smc_trace`。这个展示能说明策略卡在哪一层，但仍偏流程摘要，不能充分展示项目已有的 SMC 分析能力。

项目底层已经具备完整 SMC 检测类型：

- `SwingPoint`：摆动高低点
- `OrderBlock`：订单块
- `FairValueGap`：FVG 失衡区
- `StructureBreak`：BOS / CHoCH
- `LiquidityLevel`：等高/等低/趋势线流动性
- `SMCSnapshot`：单周期完整 SMC 快照

用户明确选择的展示方向是：

> 采用 B 为主 + A 的解释语句 + C 的关键价位列表。首页可以快速判断交易条件，展开后又能学习每一层 SMC 逻辑。

---

## 2. 设计目标

1. 每次行情分析时，提取并展示本项目的 SMC 订单流分析能力。
2. Dashboard 首页能快速回答：当前 SMC 条件是否支持交易，卡在哪一层。
3. 展开后能帮助用户学习：D1/H4、H1、流动性、M15 每层是怎么判断的。
4. 展示关键价位：当前价、上方流动性、下方流动性、有效 OB/FVG 区域。
5. 不改变交易逻辑、下单逻辑、风控逻辑或 EA 通讯逻辑。

非目标：

- 不做 K 线图绘制。
- 不保存全量历史 SMC 快照。
- 不重新定义 SMC 检测算法。
- 不让用户在 dashboard 手动选择某个 SMC 区域下单。

---

## 3. 推荐方案

采用“订单流摘要层 + Dashboard 雷达展示”的方案。

后端在每个 M15 分析周期生成 `smc_orderflow` 摘要，写入 `data/{SYMBOL}/live_state.json`。前端读取该字段，并用三个层次展示：

1. **订单流雷达**：首页主展示，快速扫视结构、交易区、流动性、入场、风险。
2. **学习时间线**：折叠展开，解释 D1/H4 → H1 → 流动性 → M15 的判断链路。
3. **关键价位列表**：列出上方/下方流动性、订单块、FVG、当前价等。

---

## 4. 数据结构

新增 `live_state.json` 顶层字段：

```json
{
  "smc_orderflow": {
    "summary": {
      "bias": "bullish",
      "readiness": "waiting",
      "headline": "大周期偏多，H1 有候选交易区，但 M15 入场确认未完成。",
      "blocking_reason": "等待 M15 CHoCH 或 FVG 回补确认"
    },
    "radar": [
      {
        "key": "structure",
        "label": "结构",
        "status": "passed",
        "title": "D1/H4 偏多",
        "detail": "HTF 方向为 bullish，置信度 72%。"
      },
      {
        "key": "zone",
        "label": "交易区",
        "status": "passed",
        "title": "找到 2 个 H1 候选区",
        "detail": "优先关注未缓解订单块和 FVG 重叠区域。"
      },
      {
        "key": "liquidity",
        "label": "流动性",
        "status": "waiting",
        "title": "等待扫流动性",
        "detail": "上方等高未扫，下方低点已扫。"
      },
      {
        "key": "entry",
        "label": "入场",
        "status": "blocked",
        "title": "M15 未确认",
        "detail": "尚未出现同向 CHoCH / BOS / FVG 回补。"
      },
      {
        "key": "risk",
        "label": "风险",
        "status": "waiting",
        "title": "等待候选 setup",
        "detail": "形成候选后再计算 RR、共振和风控。"
      }
    ],
    "timeline": [
      {
        "timeframe": "D1/H4",
        "label": "大周期结构",
        "status": "passed",
        "explanation": "D1/H4 结构偏多，允许寻找多头交易区。"
      },
      {
        "timeframe": "H1",
        "label": "交易区",
        "status": "passed",
        "explanation": "H1 找到 2 个与大周期方向一致的交易区。"
      },
      {
        "timeframe": "M15",
        "label": "入场触发",
        "status": "blocked",
        "explanation": "价格尚未在交易区内形成 M15 反转确认。"
      }
    ],
    "key_levels": [
      {
        "kind": "current_price",
        "label": "当前价",
        "price": 2362.1,
        "side": "current",
        "detail": "本轮分析价格"
      },
      {
        "kind": "liquidity",
        "label": "上方流动性",
        "price": 2384.2,
        "side": "above",
        "detail": "等高流动性，尚未扫"
      },
      {
        "kind": "order_block",
        "label": "H1 多头订单块",
        "low": 2351.2,
        "high": 2354.8,
        "side": "below",
        "detail": "未缓解，方向与 HTF 一致"
      }
    ],
    "debug": {
      "source": "aggregator",
      "generated_at": "2026-05-19T00:00:00+00:00"
    }
  }
}
```

### 字段语义

`summary.readiness` 取值：

- `ready`：SMC 条件已形成，存在可交易候选。
- `waiting`：部分条件通过，仍等待入场或价位确认。
- `blocked`：关键条件失败，不应交易。
- `unknown`：本周期数据不足或未生成。

`radar[].status` 与 `timeline[].status` 取值：

- `passed`：该层已通过。
- `waiting`：该层尚未完成，但不是失败。
- `blocked`：该层明确阻断。
- `skipped`：本轮未执行。
- `unknown`：数据缺失。

---

## 5. 后端设计

新增一个轻量模块，例如 `src/smc/strategy/smc_orderflow.py`。

职责：

1. 接收现有 `smc_diagnostic`、`range_diagnostic`、`smc_trace`、`best_setup`、`current_price`。
2. 尽量使用已有诊断字段，不重复跑重型 SMC 检测。
3. 从现有数据中提炼：
   - 结构方向与置信度。
   - H1 候选交易区数量与最近价位。
   - M15 入场失败原因。
   - RR / 共振 / 风控状态。
4. 在有底层 snapshot 可用时，补充 OB/FVG/BOS/CHoCH/流动性摘要。
5. 数据不足时返回可渲染的 `unknown` 状态，而不是抛异常。

为了避免扩大风险，第一版不把全量 `SMCSnapshot` 写入 `live_state.json`。只写摘要和最多 8 个关键价位。

### 与现有流程的关系

`scripts/live_demo.py` 的 `save_state()` 当前已经写入：

- `range_diagnostic`
- `smc_diagnostic`
- `best_setup`
- `smc_trace`

第一版在 `smc_trace` 生成之后调用 `build_smc_orderflow(...)`，把结果写入 `state["smc_orderflow"]`。

---

## 6. 前端设计

在 `dashboard/index.html` 中，将现有“SMC 阶段追踪”升级为“SMC 订单流雷达”。

### 首页默认展示

卡片标题：`SMC 订单流雷达`

顶部显示：

- 一句话结论：`smc_orderflow.summary.headline`
- 状态徽章：准备好 / 等待确认 / 已阻断 / 暂无数据

中间显示 5 个雷达模块：

1. 结构
2. 交易区
3. 流动性
4. 入场
5. 风险

每个模块显示：

- 状态颜色：绿=通过，黄=等待，红=阻断，灰=暂无
- 中文标题
- 一句细节解释

### 展开区

折叠区一：`学习每一层 SMC 判断`

- 渲染 `timeline`
- 每层显示周期、标签、状态、解释

折叠区二：`关键价位地图`

- 渲染 `key_levels`
- 上方流动性、订单块、FVG、当前价、下方流动性按 side 分组或按价格排序
- 对区间用 `low-high`，对单价位用 `price`

折叠区三：`原始诊断`

- 保留现有 raw diagnostic JSON，仅作为开发者调试入口。

---

## 7. 中文解释规则

第一版使用稳定、保守的人话解释：

- `HTF bias bullish` → “大周期偏多，只优先寻找多头机会。”
- `HTF bias bearish` → “大周期偏空，只优先寻找空头机会。”
- `HTF bias neutral` → “大周期方向不清晰，系统不主动追方向。”
- `no_h1_zones` → “没有找到与大周期方向一致的 H1 订单块或 FVG 交易区。”
- `entry_none` → “价格位置可能接近，但 M15 还没有出现入场触发。”
- `confluence_low` → “有形态，但共振分数不够，质量不足。”
- `trigger_filter` → “触发器出现了，但当前市场环境不允许这种触发。”
- `ai_candidate_review_blocked` → “SMC 候选出现后，被 AI 市场环境复核拦截。”

解释语句必须短，适合 dashboard 扫视；长解释放入用户手册后续补充。

---

## 8. 错误处理

1. `smc_orderflow` 缺失：前端回退到现有 `smcTrace` 展示。
2. `radar` 为空：显示“暂无本周期 SMC 订单流摘要”。
3. `key_levels` 为空：隐藏关键价位地图，不显示空表。
4. 后端摘要生成异常：记录为 `unknown` 状态，不阻断 `live_state.json` 写入。
5. 任意字段类型不符合预期：前端使用默认值，避免页面崩溃。

---

## 9. 测试策略

### 单元测试

新增 `tests/smc/unit/strategy/test_smc_orderflow.py`：

- HTF 偏多 + H1 zones + M15 entry_none → radar 显示结构/交易区通过，入场等待或阻断。
- `stage_reject=no_h1_zones` → 交易区 blocked。
- 有 `best_setup` → readiness 为 `ready`，风险模块显示 RR / confluence。
- 数据缺失 → 返回 `unknown`，不抛异常。

### 集成或现有测试扩展

扩展 dashboard 或 live state 测试：

- `save_state()` 写入 `smc_orderflow`。
- dashboard 在有 `smc_orderflow` 时展示新卡片。
- dashboard 在无 `smc_orderflow` 时仍可展示旧 `smc_trace`。

### 浏览器验证

启动 `scripts/dashboard_server.py`，打开 `http://localhost:8765`：

- 监控页可见 `SMC 订单流雷达`。
- 雷达模块、学习时间线、关键价位地图渲染正常。
- 设置页不受影响。
- 控制台无错误。

---

## 10. 实施顺序

1. 新增后端摘要构造模块和单元测试。
2. 在 `save_state()` 中写入 `smc_orderflow`。
3. 升级 dashboard SMC 卡片，保留旧字段回退。
4. 补充 dashboard 测试。
5. 浏览器验证页面渲染。
6. 更新 `docs/用户操作手册.md` 的 SMC 订单流说明。

---

## 11. 风险与约束

主要风险是把过多底层 SMC 原始数据塞进 dashboard，导致页面噪音过大或 `live_state.json` 变重。第一版只做摘要，不做完整快照历史。

另一个风险是解释过度承诺。页面文案必须表达“结构支持/等待确认/被阻断”，不能暗示任何确定性盈利。

本设计不改变交易决策路径，因此上线风险集中在展示层和状态文件大小，风险可控。

