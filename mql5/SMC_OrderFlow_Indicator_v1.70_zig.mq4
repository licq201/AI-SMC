//+------------------------------------------------------------------+
//|                                        SMC_OrderFlow_Indicator.mq4 |
//|                                    Smart Money Concepts Indicator |
//|                                   专业SMC订单流市场结构分析指标 |
//+------------------------------------------------------------------+
#property copyright "SMC Trading System"
#property link      "https://bbs.sunwy.com"
#property version   "1.70"
#property description "SMC_OrderFlow_Indicator, 专业SMC订单流市场结构分析指标 - BOS/CHOCH优化版"
#property description "author:博思客 V:2030988"
#property description "v1.70: 新增ZigZag摆点前置过滤(缠论之前,严格交集,开关EnableZigZagFilter默认true)"
#property description "v1.69: 缠论V1.64极短笔收窄(方案A)—新低/新高延伸时不丢current，避免真LL被吞后误连4-7"
#property description "v1.67: 回迁缠论不成笔过滤为chan_1逻辑，修复LH/HL/LH/LL/HH误连2-5成笔"
#property description "v1.58: 缠论包含/分型/笔5项优化(processed_index/trend初始/极点降门槛/等高等低/笔长精确)"
#property description "v1.57: 缠论不成笔时修正回溯逻辑(删除last非丢弃current)"
#property strict
#property indicator_chart_window
#property indicator_buffers 10

//+------------------------------------------------------------------+
//| 输入参数定义                                                      |
//+------------------------------------------------------------------+
// --- A. 核心逻辑参数 (EA调用所需) ---
extern int    StructureLookback   = 5;     // 结构点识别强度(左右各N根K线)
extern int    MaxBarsToCalculate  = 1000;  // 最大计算K线数量(性能优化,0=全部)
extern int    MaxFVGZones         = 5;     // 计算并存储的FVG区域的最大数量
extern int    MaxOBZones          = 5;     // 计算并存储的OB区域的最大数量
extern int    MaxBOSZones         = 2;     // 计算并存储的BOS区域的最大数量
extern int    MaxCHOCHZones       = 2;     // 计算并存储的CHoCH区域的最大数量

// --- B. 视觉与警报参数 (EA调用时可忽略) ---
extern bool   ShowBOS             = true;  // 显示BOS
extern bool   ShowCHOCH           = true;  // 显示CHOCH
extern bool   ShowFVG             = true;  // 显示FVG
extern bool   ShowOrderBlocks     = true;  // 显示Order Blocks
extern bool   ShowMitigatedPOI    = false; // 显示已被触及的区域
extern bool   CHOCH_InstantTrendUpdate = false; // 趋势判断模式：false=方案A(序列跟踪), true=方案B(状态机)
extern bool   ShowSwingConnections = true;  // 显示摆点连线

extern color  BOS_Color           = clrPowderBlue; // BOS线条颜色
extern color  CHOCH_Color         = clrDodgerBlue;  // CHOCH线条颜色
extern color  Bullish_FVG_Color   = clrGreen;      // 看涨FVG区域颜色
extern color  Bearish_FVG_Color   = clrRed;        // 看跌FVG区域颜色
extern color  Bullish_OB_Color    = clrLimeGreen;  // 看涨OB区域颜色
extern color  Bearish_OB_Color    = clrOrange;     // 看跌OB区域颜色
extern color  Mitigated_POI_Color = clrGray;       // 已触及区域的颜色
extern color  SwingConnection_Color = clrYellow;   // 摆点连线颜色
extern color  BullishSwing_Color = clrLimeGreen;   // 上升趋势摆点连线颜色
extern color  BearishSwing_Color = clrOrangeRed;   // 下降趋势摆点连线颜色

extern bool   EnableAlerts        = false; // 启用警报功能
extern bool   AlertOnBOS          = false; // BOS形成时警报
extern bool   AlertOnCHOCH        = false; // CHOCH形成时警报
extern bool   AlertOnPOIEntry     = false; // 价格进入未触及的POI区域时警报

// --- C. V1.2 行为与过滤参数 (可配置，默认按建议值) ---
extern int    OuterLookbackFactor = 2;      // 外部结构 = StructureLookback * 因子
extern bool   ConfirmBreakClose   = true;   // 突破是否要求收盘确认
extern double MinBodyRatio        = 0.35;   // 最小实体比例(实体/全幅)
extern double MinAtrMomentum      = 0.8;    // 突破K线全幅/ATR(N) 的最小比值
extern int    AtrPeriod           = 14;     // ATR周期

extern int    LiquidityReclaimWindow = 1;   // Liquidity Grab 回收确认窗口(根数)
extern double LiquidityMinOverrunATR = 0.10;// 最小超越幅度(以ATR比例)

extern double FVGQualityThreshold = 0.05;   // FVG 最低质量阈值(0-1)
extern bool   OB_OnlyDrive        = false;   // 仅绑定驱动段产生的OB

extern bool   UsePremiumDiscount  = false;   // 启用折价/溢价过滤(外部结构50%)
extern bool   PreferGolden62      = false;   // 62%作为优先条件(更优位置)

extern int    CooldownBars        = 10;     // 信号冷却间隔(根)
extern int    MaxTriggersPerZone  = 1;      // 单区域最大触发次数
extern bool   ShowPremiumDiscountLines = true; // 显示50%/62%(38%)折溢价线

// --- D. 稳健结构识别参数（方案2） ---
extern double SwingMinAtr          = 0.4;    // 最小摆幅(倍数ATR) - 过滤微小摆点
extern int    SwingMinPoints       = 3;      // 或者最小摆幅(点数)，0禁用点数过滤
extern int    EqualTolerancePoints = 2;      // 等高/等低容差(点)，视为相等不改变级别
extern int    TrendWindowStructures= 6;      // 趋势确认窗口：最近结构数量(4~6)
extern bool   RequireDisplacement  = true;   // 触发需位移（实体/全幅 & 全幅/ATR）
extern bool   RequireFVG_BOS       = false;  // BOS是否要求伴随FVG
extern bool   RequireFVG_CHOCH     = true;   // CHOCH是否要求伴随FVG（更严格）

// --- E. 缠论MA21均线参数 ---
extern bool   EnableMA21Filter    = true;        // 启用MA21均线过滤（在缠论步骤中执行）
extern int    MA21_Period         = 21;           // MA21均线周期
extern int    MA21_Method         = MODE_EMA;    // MA21计算方法(0=SMA,1=EMA,2=SMMA,3=LWMA)
extern int    MA21_AppliedPrice   = PRICE_CLOSE; // MA21应用价格
extern color  MA21_Color          = clrWhite;    // MA21均线颜色
extern int    MA21_LineWidth      = 1;           // MA21均线宽度
extern bool   ShowMA21Line        = true;        // 显示MA21均线
// MA21过滤强度（与缠论优化配合，在FilterSwingPointsByChan中执行）
// 1=仅H/L突破均线  2=连续N根K线H/L同侧(推荐)
extern int    MA21FilterMode      = 1;           // 均线过滤强度模式(1/2)
extern int    MA21ConfirmBars     = 2;           // Mode=2时连续根数(1~5)

// --- F. OB显示优化参数 ---
extern bool   EnableOBDebug        = false;   // 启用OB区域调试信息
extern bool   ForceOBRedraw        = false;  // 强制重绘OB区域
extern bool   ShowOBStatusInfo     = true;   // 显示OB区域状态信息

// --- G. OB生命周期优化参数 ---
extern bool   EnableOBLifecycle      = true;      // 启用OB生命周期机制(默认主逻辑)
extern int    OBCooldownBars         = 5;        // 定义新触及的冷却K线数
extern bool   RequireMomentumOnBreak = true;     // 失效确认是否需要动能K线
extern double BreakMomentumATR       = 1.5;      // 动能K线实体需大于N倍ATR
extern bool   RemoveInvalidOB        = false;    // 是否直接移除失效的OB
extern bool   ShowOBLifecycleInfo   = false;    // [高级/调试] 显示OB生命周期详细信息

// --- G2. OB/FVG 质量评分参数 (新增) ---
extern bool   EnableOBFVGConfluence    = true;   // 启用OB/FVG同向重叠评分
extern double MinOBFVGOverlapRatio     = 0.20;   // 重叠比例达此值时额外加分
extern bool   ShowOBQualityGrade       = true;   // OB标签显示质量等级[A/B/C/D/X]
extern bool   HideLowQualityOB         = false;  // 隐藏低于阈值的低质量OB
extern double MinVisibleOBQualityScore = 0.20;   // HideLowQualityOB=true时的可见性阈值

// --- E. 缠论优化参数 ---
extern bool   EnableChanOptimization = true;  // 启用缠论优化（K线包含+分型过滤）
extern int    MinStrokeBars          = 5;      // 笔的最小K线数(原始K线)
extern double MinStrokeATR           = 0.5;    // 笔的最小幅度(ATR倍数,0=禁用)
extern bool   ShowChanFractals       = false;  // 显示分型标记(调试用)
extern color  TopFractalColor        = clrRed;       // 顶分型颜色
extern color  BottomFractalColor     = clrLime;      // 底分型颜色
extern bool   ShowVirtualStroke      = true;         // 显示虚拟笔
extern color  VirtualStrokeColor     = clrYellow;    // 虚拟笔颜色

// --- D. V1.36 调试参数 ---
extern bool   EnableDebugMode     = false; // 启用调试日志总开关
extern bool   DebugBOSCHOCH       = false; // 显示BOS/CHOCH识别日志
extern bool   DebugTrendChange    = false; // 显示趋势变化日志

// --- H. V1.52 极点保护参数 ---
extern bool   EnableExtremeProtection = true;  // 启用极点保护机制
extern bool   DebugExtremePoints      = false; // 调试极点识别日志

// --- J. V1.54 临时极点追踪参数 ---
extern bool   ShowTemporaryExtreme    = false;        // 显示临时极点（未确认的最新高/低点）
extern color  TempExtremeHigh_Color   = clrAqua;     // 临时高点颜色
extern color  TempExtremeLow_Color    = clrMagenta;  // 临时低点颜色
extern int    TempExtremeArrowSize    = 2;           // 临时极点箭头大小

// --- I. V1.53 趋势可视化参数 ---
extern bool   ShowTrendIndicator      = true;        // 显示趋势指示器
extern int    TrendIndicator_Corner   = 1;           // 位置：0=左上,1=右上,2=左下,3=右下
extern int    TrendIndicator_XOffset  = 20;          // X轴偏移(像素)
extern int    TrendIndicator_YOffset  = 80;          // Y轴偏移(像素)
extern int    TrendIndicator_FontSize = 16;          // 字体大小
extern color  UpTrend_Color           = clrLime;     // 上升趋势颜色
extern color  DownTrend_Color         = clrRed;      // 下降趋势颜色
extern color  NeutralTrend_Color      = clrYellow;   // 震荡/未定趋势颜色

// --- K. V1.55 虚拟摆点扩展参数 ---
extern bool   EnableVirtualSwingExtension = false;  // 启用虚拟摆点延伸(VHH/VLL)
extern color  VHH_Color                   = clrAqua;  // 虚拟高点连线颜色
extern color  VLL_Color                   = clrMagenta;// 虚拟低点连线颜色
extern int    VirtualSwingExtension_Style = STYLE_DOT; // 虚拟延伸线样式

// --- L. V1.70 ZigZag 摆点前置过滤参数 ---
extern bool   EnableZigZagFilter   = true;  // 启用ZigZag摆点过滤(缠论之前执行)
extern int    ZigZag_Depth         = 12;    // ZigZag深度(最小回溯K线数)
extern int    ZigZag_Deviation     = 5;     // ZigZag偏差(点数)
extern int    ZigZag_Backstep      = 3;     // ZigZag回溯步数
extern int    ZigZag_MatchWindow   = 3;     // 摆点与ZigZag转折点匹配的bar容差窗口

//+------------------------------------------------------------------+
//| 时间限制保护机制                                                  |
//+------------------------------------------------------------------+
#define EXPIRY_DATE D'2025.12.15 23:59:59'  // 到期时间：2025年9月15日
#define WARNING_DAYS 7                       // 到期前7天开始警告

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
struct SwingPoint {
    int bar_index;
    double price;
    bool is_high;
    bool is_broken;
    int structure_type;  // 0=HH, 1=HL, 2=LH, 3=LL, -1=未分类
    bool is_extreme;     // V1.52新增：是否为极点（极高/极低）
    bool is_tentative;   // V1.55新增：暂定摆点(虚拟摆点)
    int processed_index; // V1.58新增：对应的缠论处理后K线索引(-1=未找到)
};

struct POI_Zone {
    int start_bar;
    double top_price;
    double bottom_price;
    bool is_bullish;
    bool is_mitigated;          // 保留用于FVG兼容性
    int poi_type;               // 0=FVG, 1=OrderBlock
    string zone_id;
    bool is_drawn;              // 标记是否已经绘制
    int trigger_count;          // 已触发次数（用于节流）
    
    // --- OB生命周期新增字段 ---
    int touch_count;            // OB有效触及次数
    int status;                 // OB当前状态: 0=Fresh, 1=Tested, 2=Weakened, 3=Broken_Once, 4=Invalid
    int last_touch_bar;         // 记录上次触及的K线索引
    int first_break_bar;        // 记录首次突破的K线索引
    double break_momentum;      // 突破时的动能强度（实体/ATR比值）

    // --- OB/FVG 重叠与质量评分新增字段 ---
    bool   has_fvg_overlap;     // 是否与同向FVG价格重叠
    int    overlap_fvg_bar;     // 重叠FVG的锚点bar(-1=无)
    double overlap_ratio;       // 重叠宽度/OB宽度
    double quality_score;       // OB质量分 0.0-1.0
    string quality_grade;       // 等级 A/B/C/D/X
};

struct Structure_Zone {
    int start_bar;      // 突破发生的K线索引
    int swing_bar;      // 被突破的swing point的K线索引
    double top_price;
    double bottom_price;
    bool is_bullish;
    bool is_broken;
    int structure_type; // 0=BOS, 1=CHOCH
    string zone_id;
    bool is_drawn; // 标记是否已经绘制
};

// MQL4中结构体不支持color类型，改用全局变量和单独的函数处理

// --- 缠论优化：定义处理后的K线结构体 ---
struct ProcessedBar {
    datetime time;
    double open;
    double high;
    double low;
    double close;
    int original_index;            // 记录合并前最后一根K线的原始索引
    int high_bar_index;            // 包含规则确定的高点索引（受趋势影响，削峰时取较低那根）
    int low_bar_index;             // 包含规则确定的低点索引（受趋势影响）
    // V1.59新增：不受包含规则趋势方向影响，始终追踪实际最高/最低的原始K线
    // 解决"削峰"后原始摆点无法匹配分型的核心问题
    int actual_high_bar_index;     // 实际最大High所在原始K线索引
    int actual_low_bar_index;      // 实际最小Low所在原始K线索引
};

SwingPoint swing_points[];
POI_Zone poi_zones[];
Structure_Zone structure_zones[];
int swing_count = 0;
int poi_count = 0;
int structure_count = 0;


//+------------------------------------------------------------------+
//| 🔐 账号授权系统配置                                              |
//+------------------------------------------------------------------+
// 授权方式选择
bool UseAccountNumberAuth = true;        // 启用账号授权
bool UseAccountNameAuth = false;         // 启用账户名授权
bool UseBrokerAuth = false;              // 启用经纪商授权
bool UseHardwareAuth = true;            // 启用硬件ID授权
bool UseTimeAuth = true;                 // 启用时间授权

// 授权账号列表 (支持多个账号)
string AuthorizedAccounts = "112501337,112527444,8874186,112451289,2100589660,2100589673"; // 授权账号列表(逗号分隔)
string AuthorizedNames = "Demo Account,Real Account";      // 授权账户名列表
string AuthorizedBrokers = "MetaQuotes,DooPrime";  // 授权经纪商列表
string AuthorizedHardwareIDs = "759925988,1722292608,1823293528,184564060,2042538657,2073184317,1324502180,174210046";           // 授权硬件ID列表

// 时间授权设置
datetime AuthStartTime = D'2025.09.21 00:00:00';         // 授权开始时间
datetime AuthEndTime = D'2026.10.31 23:59:59';           // 授权结束时间
int WarningDaysBefore = 7;                               // 到期前警告天数

// 授权失败处理
bool ShowAuthFailureMessage = true;                      // 显示授权失败信息
bool AllowDemoAccount = true;                            // 允许模拟账户使用
int MaxDailyUsage = 0;                                   // 每日最大使用次数(0=无限制)

// 高级安全选项
bool EnableEncryption = true;                            // 启用加密验证
string SecurityKey = "SMC Trading 2024";                 // 安全密钥
bool LogAuthAttempts = true;                             // 记录授权尝试
bool AntiDebugMode = false;                              // 反调试模式
int RecheckInterval = 30;                                // 授权重检间隔(分钟)

// --- 延迟重试机制配置参数 ---
bool EnableAuthRetry = true;                         // 启用授权延迟重试机制
int MaxAuthRetries = 5;                              // 最大重试次数
int AuthRetryIntervals[5] = {1, 3, 5, 10, 15};      // 重试间隔序列(秒)
bool ShowRetryStatus = true;                         // 显示重试状态信息

//+------------------------------------------------------------------+
//| 授权系统全局变量                                                  |
//+------------------------------------------------------------------+
bool g_is_authorized = false;              // 授权状态
bool g_auth_checked = false;               // 是否已检查授权
int g_daily_usage_count = 0;               // 每日使用计数
datetime g_last_usage_date = 0;            // 最后使用日期
string g_auth_failure_reason = "";         // 授权失败原因
bool g_demo_account_detected = false;      // 检测到模拟账户
string g_current_hardware_id = "";         // 当前硬件ID

// --- 延迟重试机制全局变量 ---
bool g_auth_retry_active = false;          // 重试机制是否激活
int g_auth_retry_count = 0;                // 当前重试次数
datetime g_last_auth_attempt = 0;          // 上次授权尝试时间
bool g_account_zero_detected = false;      // 检测到账号为0
string g_retry_timer_name = "SMC_AuthRetryTimer"; // 重试定时器名称

//--- 指标缓冲区
double BOS_Top[];             // Buffer 0: BOS上轨
double BOS_Bottom[];          // Buffer 1: BOS下轨
double CHOCH_Top[];           // Buffer 2: CHoCH上轨
double CHOCH_Bottom[];        // Buffer 3: CHoCH下轨
double FVG_Top[];             // Buffer 4: FVG上轨
double FVG_Bottom[];          // Buffer 5: FVG下轨
double OB_Top[];              // Buffer 6: OB上轨
double OB_Bottom[];           // Buffer 7: OB下轨
double MA21_Buffer[];         // Buffer 8: MA21均线缓冲区
double OB_Quality[];          // Buffer 9: OB质量分(0.0-1.0,DRAW_NONE,供EA经iCustom读取)

// 时间限制相关变量
bool license_valid = true;
datetime last_warning_time = 0;

// 绘制刷新/版本控制
int g_data_version = 0;          // 数据变更版本号（新增/删除/状态变化时递增）
int g_last_drawn_version = -1;   // 上次已绘制的版本号
datetime g_last_full_recalc_time = 0; // 上次完整重算时间

// 运行期信号控制
int g_last_signal_bar_shift = 1000000; // 最后一次触发信号的bar shift（冷却控制，初始化为很大）
int g_last_break_up_bar   = -1;        // 最近一次向上方向的结构突破所在bar（用于绑定驱动OB）
int g_last_break_down_bar = -1;        // 最近一次向下方向的结构突破所在bar
datetime g_last_signal_time = 0;       // 最近一次发出警报的时间（用于冷却）

// 市场结构状态跟踪
int g_market_trend = 0;                // 当前主趋势：1=上升，-1=下降，0=未确定
int g_last_hh_index = -1;              // 最近的HH索引
int g_last_hl_index = -1;              // 最近的HL索引  
int g_last_lh_index = -1;              // 最近的LH索引
int g_last_ll_index = -1;              // 最近的LL索引

// === 方案B：状态机模型的新增变量 ===
int g_trend_state = 0;           // 状态机状态：0=UNDEFINED, 1=UP, -1=DOWN
int g_protected_high_index = -1; // 当前受保护的LH点索引（下降趋势中）
int g_protected_low_index = -1;  // 当前受保护的HL点索引（上升趋势中）
int g_last_bos_bar = -1;         // 最近BOS发生的bar索引
int g_last_choch_bar = -1;       // 最近CHoCH发生的bar索引

// 模式切换控制
bool g_last_mode_state = false;  // 记录上次的CHOCH_InstantTrendUpdate状态

// CHoCH唯一性状态标志 (防止重复标记CHoCH)
bool g_choch_down_occurred_in_uptrend = false;   // 在当前上升趋势中是否已发生向下CHoCH
bool g_choch_up_occurred_in_downtrend = false;   // 在当前下降趋势中是否已发生向上CHoCH

// === V1.54 临时极点追踪变量 ===
int g_temp_high_bar = -1;           // 临时高点K线索引
double g_temp_high_price = 0;       // 临时高点价格
int g_temp_low_bar = -1;            // 临时低点K线索引
double g_temp_low_price = 0;        // 临时低点价格
int g_last_confirmed_high_bar = -1; // 最后确认的SwingHigh的K线索引
int g_last_confirmed_low_bar = -1;  // 最后确认的SwingLow的K线索引

// === V1.55 虚拟摆点扩展变量 ===
int    g_virtual_swing_bar = -1;        // 虚拟摆点的K线索引
double g_virtual_swing_price = 0;       // 虚拟摆点价格
bool   g_virtual_swing_is_high = false; // 虚拟摆点是高点还是低点
int    g_virtual_swing_type = -1;       // 虚拟摆点类型: 10=VHH, 13=VLL
bool   g_virtual_swing_active = false;  // 虚拟摆点是否激活
bool   g_virtual_swing_add_mode = false; // V1.66: true=HL/LH时追加虚拟点, false=HH/LL时替换

// --- 缠论优化：结构体和函数声明 ---
struct FractalPoint {
    int bar_index;      // 在合并后K线数组中的索引
    double price;
    bool is_top;        // true为顶分型, false为底分型
    int original_bar;   // 原始K线索引
    datetime time;      // 分型时间
};

// --- V1.70 ZigZag 转折点结构体 ---
struct ZigZagPivot {
    int    bar_index;   // 转折点所在原始K线索引(series shift)
    double price;       // 转折点价格
    bool   is_high;     // true=高点(峰), false=低点(谷)
};

// 缠论优化全局存储
FractalPoint g_chan_fractals[];     // 缠论分型数组
int          g_chan_fractal_count = 0;
ProcessedBar g_processed_bars[];    // 合并后K线缓存
int          g_processed_bars_count = 0;

int ProcessInclusion(int counted_bars, int rates_total, ProcessedBar& processed_bars[]);
void IdentifyChanFractals(int processed_bars_count, ProcessedBar& processed_bars[]);
bool ValidateSwingPointByChan(int bar_index, double price, bool is_high, double cached_atr = -1.0);
void FilterSwingPointsByChan();
// V1.70 ZigZag 摆点前置过滤
int  CalculateZigZagPivots(int scan_limit, ZigZagPivot &pivots[]);
void FilterSwingPointsByZigZag();
int  FindProcessedBarIndex(int raw_bar, bool is_high);  // V1.58：查找摆点对应的处理后K线索引
bool CheckMA21FilterChan(int bar_index, double price, bool is_high, int force_mode = -1); // V1.59：缠论步骤内MA21过滤(Mode0/1/2)，force_mode=-1时使用全局MA21FilterMode
void DrawFractalMarker(const FractalPoint& fractal);
void CleanupChanFractalObjects();

// V1.53新增函数声明
void ReclassifySwingPoints();       // 重新分类摆点（缠论过滤后调用）
void DrawTrendIndicator();          // 绘制趋势指示器
void CleanupTrendIndicator();       // 清理趋势指示器对象

// V1.54新增函数声明
void UpdateTemporaryExtremes(const double &high[], const double &low[], int rates_total);  // 更新临时极点
void DrawTemporaryExtremes();       // 绘制临时极点标记
void CleanupTemporaryExtremes();    // 清理临时极点对象

// V1.62新增：后置裁剪，确保只保留每种类型最新的N个
void TrimStructureZonesToNewest();
// V1.63新增：验证swing_bar是否在过滤后摆点集合中
bool IsSwingBarInCurrentSet(int bar_index);
// V1.69：V1.64「极短反向」噪声判定（方案A），供 FilterSwingPointsByChan 使用
bool ChanV64_ShouldDiscardOppositeShortNoise(SwingPoint &last_sp, SwingPoint &current_sp, SwingPoint &final_swings[], int final_count);


//+------------------------------------------------------------------+
//| 判断是否为Swing High                                             |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar, const double &high[])
{
    if(bar < StructureLookback || bar >= Bars - StructureLookback) return false;
    
    // 额外的边界检查
    if(bar + StructureLookback >= ArraySize(high) || bar - StructureLookback < 0) return false;
    
    double current_high = high[bar];
    
    // 检查左侧
    for(int i = 1; i <= StructureLookback; i++) {
        if(bar + i >= ArraySize(high) || high[bar + i] >= current_high) return false;
    }
    
    // 检查右侧
    for(int i = 1; i <= StructureLookback; i++) {
        if(bar - i < 0 || high[bar - i] >= current_high) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 判断是否为Swing Low                                              |
//+------------------------------------------------------------------+
bool IsSwingLow(int bar, const double &low[])
{
    if(bar < StructureLookback || bar >= Bars - StructureLookback) return false;
    
    // 额外的边界检查
    if(bar + StructureLookback >= ArraySize(low) || bar - StructureLookback < 0) return false;
    
    double current_low = low[bar];
    
    // 检查左侧
    for(int i = 1; i <= StructureLookback; i++) {
        if(bar + i >= ArraySize(low) || low[bar + i] <= current_low) return false;
    }
    
    // 检查右侧
    for(int i = 1; i <= StructureLookback; i++) {
        if(bar - i < 0 || low[bar - i] <= current_low) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| MA21均线计算函数                                                  |
//+------------------------------------------------------------------+
void CalculateMA21(int rates_total, const double &high[], const double &low[], const double &close[], const double &open[])
{
    if(!EnableMA21Filter) return;
    
    // 确保有足够的数据计算MA21
    if(rates_total < MA21_Period) return;
    
    // 根据MA21_AppliedPrice选择价格数组
    double price_array[];
    ArrayResize(price_array, rates_total);
    
    for(int i = 0; i < rates_total; i++) {
        switch(MA21_AppliedPrice) {
            case PRICE_CLOSE:   price_array[i] = close[i]; break;
            case PRICE_OPEN:    price_array[i] = open[i]; break;
            case PRICE_HIGH:    price_array[i] = high[i]; break;
            case PRICE_LOW:     price_array[i] = low[i]; break;
            case PRICE_MEDIAN:  price_array[i] = (high[i] + low[i]) / 2.0; break;
            case PRICE_TYPICAL: price_array[i] = (high[i] + low[i] + close[i]) / 3.0; break;
            case PRICE_WEIGHTED: price_array[i] = (high[i] + low[i] + close[i] + close[i]) / 4.0; break;
            default: price_array[i] = close[i]; break;
        }
    }
    
    // 计算MA21均线
    for(int i = 0; i < rates_total; i++) {
        if(i < MA21_Period - 1) {
            // 添加边界检查，防止MA21_Buffer数组越界
            if(i >= 0 && i < ArraySize(MA21_Buffer)) {
                MA21_Buffer[i] = EMPTY_VALUE;
            }
            continue;
        }
        
        double sum = 0.0;
        switch(MA21_Method) {
            case MODE_SMA: // 简单移动平均
                for(int j = 0; j < MA21_Period; j++) {
                    int index = i - j;
                    // 添加边界检查，防止数组越界
                    if(index >= 0 && index < ArraySize(price_array)) {
                        sum += price_array[index];
                    }
                }
                // 添加边界检查，防止MA21_Buffer数组越界
                if(i >= 0 && i < ArraySize(MA21_Buffer)) {
                    MA21_Buffer[i] = sum / MA21_Period;
                }
                break;
                
            case MODE_EMA: // 指数移动平均
                if(i == MA21_Period - 1) {
                    // 第一个EMA值使用SMA
                    for(int j = 0; j < MA21_Period; j++) {
                        int index = i - j;
                        // 添加边界检查，防止数组越界
                        if(index >= 0 && index < ArraySize(price_array)) {
                            sum += price_array[index];
                        }
                    }
                    // 添加边界检查，防止MA21_Buffer数组越界
                    if(i >= 0 && i < ArraySize(MA21_Buffer)) {
                        MA21_Buffer[i] = sum / MA21_Period;
                    }
                } else {
                    double multiplier = 2.0 / (MA21_Period + 1.0);
                    // 添加边界检查
                    if(i >= 0 && i < ArraySize(price_array) && i-1 >= 0) {
                        // 添加MA21_Buffer边界检查
                        if(i >= 0 && i < ArraySize(MA21_Buffer) && i-1 >= 0 && i-1 < ArraySize(MA21_Buffer)) {
                            MA21_Buffer[i] = (price_array[i] - MA21_Buffer[i-1]) * multiplier + MA21_Buffer[i-1];
                        }
                    }
                }
                break;
                
            case MODE_SMMA: // 平滑移动平均
                if(i == MA21_Period - 1) {
                    // 第一个SMMA值使用SMA
                    for(int j = 0; j < MA21_Period; j++) {
                        int index = i - j;
                        // 添加边界检查，防止数组越界
                        if(index >= 0 && index < ArraySize(price_array)) {
                            sum += price_array[index];
                        }
                    }
                    MA21_Buffer[i] = sum / MA21_Period;
                } else {
                    // 添加边界检查
                    if(i >= 0 && i < ArraySize(price_array) && i-1 >= 0) {
                        // 添加MA21_Buffer边界检查
                        if(i >= 0 && i < ArraySize(MA21_Buffer) && i-1 >= 0 && i-1 < ArraySize(MA21_Buffer)) {
                            MA21_Buffer[i] = (MA21_Buffer[i-1] * (MA21_Period - 1) + price_array[i]) / MA21_Period;
                        }
                    }
                }
                break;
                
            case MODE_LWMA: // 线性加权移动平均
                {
                    double weight_sum = 0.0;
                    for(int j = 0; j < MA21_Period; j++) {
                        int index = i - j;
                        // 添加边界检查，防止数组越界
                        if(index >= 0 && index < ArraySize(price_array)) {
                            int weight = MA21_Period - j;
                            sum += price_array[index] * weight;
                            weight_sum += weight;
                        }
                    }
                    if(weight_sum > 0) {
                        // 添加边界检查
                        if(i >= 0 && i < ArraySize(MA21_Buffer)) {
                            MA21_Buffer[i] = sum / weight_sum;
                        }
                    } else {
                        // 添加边界检查
                        if(i >= 0 && i < ArraySize(MA21_Buffer)) {
                            MA21_Buffer[i] = EMPTY_VALUE;
                        }
                    }
                }
                break;
                
            default:
                // 添加边界检查
                if(i >= 0 && i < ArraySize(MA21_Buffer)) {
                    MA21_Buffer[i] = EMPTY_VALUE;
                }
                break;
        }
    }
}

//+------------------------------------------------------------------+
//| 计算单个K线的MA21值                                              |
//+------------------------------------------------------------------+
void CalculateMA21SingleBar(int bar, const double &high[], const double &low[], const double &close[], const double &open[])
{
    if(bar >= ArraySize(MA21_Buffer) || bar < 0) return;
    
    double price_array[];
    ArrayResize(price_array, ArraySize(close));
    
    // 根据MA21_AppliedPrice选择价格数组
    switch(MA21_AppliedPrice) {
        case PRICE_CLOSE:
            ArrayCopy(price_array, close);
            break;
        case PRICE_OPEN:
            ArrayCopy(price_array, open);
            break;
        case PRICE_HIGH:
            ArrayCopy(price_array, high);
            break;
        case PRICE_LOW:
            ArrayCopy(price_array, low);
            break;
        case PRICE_MEDIAN:
            for(int i = 0; i < ArraySize(close); i++) {
                price_array[i] = (high[i] + low[i]) / 2.0;
            }
            break;
        case PRICE_TYPICAL:
            for(int i = 0; i < ArraySize(close); i++) {
                price_array[i] = (high[i] + low[i] + close[i]) / 3.0;
            }
            break;
        case PRICE_WEIGHTED:
            for(int i = 0; i < ArraySize(close); i++) {
                price_array[i] = (high[i] + low[i] + 2 * close[i]) / 4.0;
            }
            break;
        default:
            ArrayCopy(price_array, close);
            break;
    }
    
    // 计算MA21值
    switch(MA21_Method) {
        case MODE_SMA:
            if(bar >= MA21_Period - 1) {
                double sum = 0;
                for(int j = 0; j < MA21_Period; j++) {
                    if(bar + j < ArraySize(price_array)) {
                        sum += price_array[bar + j];
                    }
                }
                MA21_Buffer[bar] = sum / MA21_Period;
            }
            break;
            
        case MODE_EMA:
            if(bar >= ArraySize(MA21_Buffer) - 1) {
                MA21_Buffer[bar] = price_array[bar];
            } else {
                double alpha = 2.0 / (MA21_Period + 1.0);
                if(bar + 1 < ArraySize(MA21_Buffer)) {
                    MA21_Buffer[bar] = alpha * price_array[bar] + (1 - alpha) * MA21_Buffer[bar + 1];
                }
            }
            break;
            
        case MODE_SMMA:
            if(bar >= ArraySize(MA21_Buffer) - 1) {
                double sum = 0;
                for(int j = 0; j < MA21_Period && bar + j < ArraySize(price_array); j++) {
                    sum += price_array[bar + j];
                }
                MA21_Buffer[bar] = sum / MA21_Period;
            } else {
                if(bar + 1 < ArraySize(MA21_Buffer)) {
                    MA21_Buffer[bar] = (MA21_Buffer[bar + 1] * (MA21_Period - 1) + price_array[bar]) / MA21_Period;
                }
            }
            break;
            
        case MODE_LWMA:
            if(bar >= MA21_Period - 1) {
                double sum = 0;
                double weight_sum = 0;
                for(int j = 0; j < MA21_Period; j++) {
                    if(bar + j < ArraySize(price_array)) {
                        double weight = MA21_Period - j;
                        sum += price_array[bar + j] * weight;
                        weight_sum += weight;
                    }
                }
                if(weight_sum > 0) {
                    MA21_Buffer[bar] = sum / weight_sum;
                }
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| 检查摆点是否满足MA21过滤条件（原版，用于非缠论模式）             |
//+------------------------------------------------------------------+
bool CheckMA21Filter(int bar_index, double price, bool is_high)
{
    if(!EnableMA21Filter) return true;
    if(bar_index >= ArraySize(MA21_Buffer) || MA21_Buffer[bar_index] == EMPTY_VALUE) return true;

    double ma21_value = MA21_Buffer[bar_index];
    return is_high ? (price > ma21_value) : (price < ma21_value);
}

//+------------------------------------------------------------------+
//| V1.59 缠论步骤内MA21过滤（三种强度模式）                         |
//+------------------------------------------------------------------+
// Mode 0：仅极点H/L突破均线（最快，兼容旧版）
// Mode 1：极点H/L突破 + 极点K线Close同侧（推荐，过滤影线假突破）
// Mode 2：极点H/L突破 + Close同侧 + 分型三根K线中至少MA21ConfirmBars根Close同侧
//         若最新摆点后续K线不足，自动降级为Mode 1
//+------------------------------------------------------------------+
bool CheckMA21FilterChan(int bar_index, double price, bool is_high, int force_mode = -1)
{
    if(!EnableMA21Filter) return true;
    if(bar_index < 0 || bar_index >= ArraySize(MA21_Buffer)) return true;
    if(MA21_Buffer[bar_index] == EMPTY_VALUE) return true;

    // V1.60: force_mode=-1时使用全局MA21FilterMode，否则使用强制模式
    // 缠论结构验证阶段传入force_mode=0，避免Mode=1/2的Close检查删掉射击之星等真实极值点
    int effective_mode = (force_mode >= 0) ? force_mode : MA21FilterMode;

    double ma21 = MA21_Buffer[bar_index];

    // --- 基础检查：极点H/L必须突破均线（所有Mode通用）---
    bool hl_ok = is_high ? (price > ma21) : (price < ma21);
    if(!hl_ok) {
        if(EnableDebugMode)
            Print("CheckMA21FilterChan: Mode=", effective_mode,
                  " H/L未突破均线 bar=", bar_index, " price=", price, " ma21=", ma21);
        return false;
    }
    if(effective_mode == 0) return true;

    // --- Mode 1：连续N根K线的H/L同侧（摆点K线向后连续检查）---
    // 目的：避免单根K线短暂刺破均线即被认定为有效突破的情况
    // 从摆点K线开始，向右（更新方向，bar_index-1, bar_index-2, ...）连续检查
    // 要求连续 MA21ConfirmBars 根K线的High(或Low)都在均线同侧
    // 第一根（bar_index）已通过基础H/L检查，计入consecutive=1
    if(effective_mode == 1)
    {
        int consecutive = 1; // bar_index已通过H/L基础检查，计1根
        for(int k = 1; k < MA21ConfirmBars; k++)
        {
            int b = bar_index - k; // MT4：小index=新，逐步向后（更新的K线）检查
            if(b < 0 || b >= ArraySize(MA21_Buffer) || MA21_Buffer[b] == EMPTY_VALUE) break;

            double hl_b  = is_high ? iHigh(Symbol(), Period(), b)
                                   : iLow(Symbol(), Period(), b);
            double ma21_b = MA21_Buffer[b];
            if(is_high ? (hl_b > ma21_b) : (hl_b < ma21_b))
                consecutive++;
            else
                break; // 不连续，立即停止
        }

        // 连续根数不足时：若MA21ConfirmBars=1则等同Mode 0，否则过滤
        bool mode1_ok = (consecutive >= MA21ConfirmBars);
        if(!mode1_ok && EnableDebugMode)
            Print("CheckMA21FilterChan: Mode=1 连续H/L不足 bar=", bar_index,
                  " consecutive=", consecutive, "/", MA21ConfirmBars,
                  " is_high=", is_high);
        return mode1_ok;
    }

    // --- Mode 2：分型三根K线窗口（bar+1, bar, bar-1）中至少MA21ConfirmBars根Close同侧 ---
    // bar+1 = 左邻（较旧）, bar = 极点, bar-1 = 右邻（较新）
    // 注意：bar-1 对最新摆点可能不存在，此时自动降级为Mode 0（已通过）
    int confirm_count = 0;
    int available_bars = 0;

    for(int offset = -1; offset <= 1; offset++) // offset=-1=右邻, 0=自身, 1=左邻
    {
        int b = bar_index + offset; // MT4: 大index=旧，小index=新
        if(b < 0 || b >= ArraySize(MA21_Buffer)) continue;
        if(MA21_Buffer[b] == EMPTY_VALUE) continue;
        available_bars++;
        double c = iClose(Symbol(), Period(), b);
        double m = MA21_Buffer[b];
        if(is_high ? (c > m) : (c < m)) confirm_count++;
    }

    // 可用K线不足时降级为Mode 0（H/L基础检查已通过）
    if(available_bars < MA21ConfirmBars) {
        if(EnableDebugMode)
            Print("CheckMA21FilterChan: Mode=2 窗口K线不足(", available_bars,
                  " < ", MA21ConfirmBars, ")，降级Mode0通过 bar=", bar_index);
        return true;
    }

    bool mode2_ok = (confirm_count >= MA21ConfirmBars);
    if(!mode2_ok && EnableDebugMode)
        Print("CheckMA21FilterChan: Mode=2 Close确认不足 bar=", bar_index,
              " confirm=", confirm_count, "/", available_bars,
              " required=", MA21ConfirmBars);
    return mode2_ok;
}

//+------------------------------------------------------------------+
//| 原始摆点识别逻辑（向后兼容）                                      |
//+------------------------------------------------------------------+
void IdentifySwingPointsOriginal(int current_bar, const double &high[], const double &low[])
{
    // 检查是否为Swing High
    if(IsSwingHigh(current_bar, high)) {
        AddSwingPoint(current_bar, high[current_bar], true);
    }
    
    // 检查是否为Swing Low
    if(IsSwingLow(current_bar, low)) {
        AddSwingPoint(current_bar, low[current_bar], false);
    }
}

//+------------------------------------------------------------------+
//| 主摆点识别函数（支持条件分支）                                    |
//+------------------------------------------------------------------+
void IdentifySwingPoints(int current_bar, const double &high[], const double &low[])
{
    // 始终使用原始摆点识别逻辑
    // 如果启用缠论优化，后续会通过FilterSwingPointsByChan进行过滤
    IdentifySwingPointsOriginal(current_bar, high, low);
}


//+------------------------------------------------------------------+
//| 🔐 核心授权验证函数                                              |
//+------------------------------------------------------------------+
bool CheckAuthorization() {
    if(g_auth_checked) return g_is_authorized;
    
    g_auth_checked = true;
    g_is_authorized = false;
    g_auth_failure_reason = "";
    
    // 1. 检查模拟账户
    if(IsDemo()) {
        g_demo_account_detected = true;
        if(!AllowDemoAccount) {
            g_auth_failure_reason = "模拟账户未被授权使用";
            return false;
        }
    }
    
    // 2. 时间授权检查
    if(UseTimeAuth) {
        if(!CheckTimeAuthorization()) {
            return false;
        }
    }
    
    // 3. 账号授权检查
    if(UseAccountNumberAuth) {
        // 检测账号是否为0（MT4启动时可能出现）
        long current_account = AccountNumber();
        if(current_account == 0) {
            g_account_zero_detected = true;
            // 如果启用了延迟重试机制，则启动重试
            if(EnableAuthRetry && !g_auth_retry_active) {
                g_auth_failure_reason = "账号信息加载中，正在重试验证...";
                g_auth_checked = false; // 重置检查状态，允许重试
                return false; // 暂时返回失败，等待重试
            } else {
                g_auth_failure_reason = "账号获取失败（账号为0），请检查MT4连接状态";
                return false;
            }
        }
        
        if(!CheckAccountNumberAuth()) {
            return false;
        }
    }
    
    // 4. 账户名授权检查
    if(UseAccountNameAuth) {
        if(!CheckAccountNameAuth()) {
            return false;
        }
    }
    
    // 5. 经纪商授权检查
    if(UseBrokerAuth) {
        if(!CheckBrokerAuth()) {
            return false;
        }
    }
    
    // 6. 硬件ID授权检查
    if(UseHardwareAuth) {
        if(!CheckHardwareAuth()) {
            return false;
        }
    }
    
    // 7. 每日使用次数检查
    if(!CheckDailyUsage()) {
        return false;
    }
    
    // 8. 加密验证
    if(EnableEncryption) {
        if(!CheckEncryptionAuth()) {
            return false;
        }
    }
    
    g_is_authorized = true;
    
    // 记录成功授权
    if(LogAuthAttempts) {
        string log_msg = "授权成功 - 账号: " + IntegerToString(AccountNumber()) + 
                        " | 时间: " + TimeToString(TimeCurrent());
        Print("🔐 " + log_msg);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 时间授权检查                                                      |
//+------------------------------------------------------------------+
bool CheckTimeAuthorization() {
    datetime current_time = TimeCurrent();
    
    // 检查是否在授权时间范围内
    if(current_time < AuthStartTime) {
        g_auth_failure_reason = "授权尚未开始，开始时间: " + TimeToString(AuthStartTime);
        return false;
    }
    
    if(current_time > AuthEndTime) {
        g_auth_failure_reason = "授权已过期，过期时间: " + TimeToString(AuthEndTime);
        return false;
    }
    
    // 到期警告
    int days_remaining = (int)((AuthEndTime - current_time) / 86400);
    if(days_remaining <= WarningDaysBefore && days_remaining > 0) {
        string warning = "⚠️ 授权将在 " + IntegerToString(days_remaining) + " 天后过期！";
        Print(warning);
        Comment(warning);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 账号授权检查                                                      |
//+------------------------------------------------------------------+
bool CheckAccountNumberAuth() {
    string current_account = IntegerToString(AccountNumber());
    string accounts[];
    
    // 解析授权账号列表
    int count = Auth_StringSplit(AuthorizedAccounts, ',', accounts);
    
    for(int i = 0; i < count; i++) {
        Auth_StringTrimLeft(accounts[i]);
        Auth_StringTrimRight(accounts[i]);
        
        if(accounts[i] == current_account) {
            return true;
        }
    }
    
    g_auth_failure_reason = "账号 " + current_account + " 未在授权列表中";
    return false;
}

//+------------------------------------------------------------------+
//| 账户名授权检查                                                    |
//+------------------------------------------------------------------+
bool CheckAccountNameAuth() {
    string current_name = AccountName();
    string names[];
    
    // 解析授权账户名列表
    int count = Auth_StringSplit(AuthorizedNames, ',', names);
    
    for(int i = 0; i < count; i++) {
        Auth_StringTrimLeft(names[i]);
        Auth_StringTrimRight(names[i]);
        
        if(StringFind(current_name, names[i]) >= 0) {
            return true;
        }
    }
    
    g_auth_failure_reason = "账户名 \"" + current_name + "\" 未在授权列表中";
    return false;
}

//+------------------------------------------------------------------+
//| 经纪商授权检查                                                    |
//+------------------------------------------------------------------+
bool CheckBrokerAuth() {
    string current_broker = AccountCompany();
    string brokers[];
    
    // 解析授权经纪商列表
    int count = Auth_StringSplit(AuthorizedBrokers, ',', brokers);
    
    for(int i = 0; i < count; i++) {
        Auth_StringTrimLeft(brokers[i]);
        Auth_StringTrimRight(brokers[i]);
        
        if(StringFind(current_broker, brokers[i]) >= 0) {
            return true;
        }
    }
    
    g_auth_failure_reason = "经纪商 \"" + current_broker + "\" 未在授权列表中";
    return false;
}

//+------------------------------------------------------------------+
//| 硬件ID授权检查                                                   |
//+------------------------------------------------------------------+
bool CheckHardwareAuth() {
    g_current_hardware_id = GenerateHardwareID();
    string hardware_ids[];
    
    // 解析授权硬件ID列表
    int count = Auth_StringSplit(AuthorizedHardwareIDs, ',', hardware_ids);
    
    for(int i = 0; i < count; i++) {
        Auth_StringTrimLeft(hardware_ids[i]);
        Auth_StringTrimRight(hardware_ids[i]);
        
        if(hardware_ids[i] == g_current_hardware_id) {
            return true;
        }
    }
    
    g_auth_failure_reason = "硬件ID \"" + g_current_hardware_id + "\" 未在授权列表中";
    return false;
}

//+------------------------------------------------------------------+
//| 每日使用次数检查                                                  |
//+------------------------------------------------------------------+
bool CheckDailyUsage() {
    if(MaxDailyUsage <= 0) return true; // 无限制
    
    datetime current_date = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    
    // 检查是否是新的一天
    if(current_date != g_last_usage_date) {
        g_daily_usage_count = 0;
        g_last_usage_date = current_date;
    }
    
    if(g_daily_usage_count >= MaxDailyUsage) {
        g_auth_failure_reason = "今日使用次数已达上限 (" + IntegerToString(MaxDailyUsage) + ")";
        return false;
    }
    
    g_daily_usage_count++;
    return true;
}

//+------------------------------------------------------------------+
//| 加密验证检查                                                      |
//+------------------------------------------------------------------+
bool CheckEncryptionAuth() {
    if(SecurityKey == "") return true; // 无密钥则跳过
    
    // 生成验证哈希
    string verification_string = IntegerToString(AccountNumber()) + 
                               AccountName() + 
                               AccountCompany() + 
                               SecurityKey;
    
    // 简单哈希验证（实际应用中可使用更复杂的加密算法）
    int hash_value = 0;
    for(int i = 0; i < StringLen(verification_string); i++) {
        hash_value += StringGetCharacter(verification_string, i) * (i + 1);
    }
    
    // 验证哈希值（这里使用简单的模运算，实际可更复杂）
    if(hash_value % 1000 == 0) {
        g_auth_failure_reason = "加密验证失败";
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 生成硬件ID                                                       |
//+------------------------------------------------------------------+
string GenerateHardwareID() {
    // 基于账号信息和终端信息生成唯一ID
    string base_string = IntegerToString(AccountNumber()) + 
                        AccountName() + 
                        AccountCompany() + 
                        TerminalInfoString(TERMINAL_NAME) +
                        TerminalInfoString(TERMINAL_PATH);
    
    // 简单哈希生成ID
    int hash = 0;
    for(int i = 0; i < StringLen(base_string); i++) {
        hash = hash * 31 + StringGetCharacter(base_string, i);
    }
    
    return IntegerToString(MathAbs(hash));
}

//+------------------------------------------------------------------+
//| 显示授权失败信息                                                  |
//+------------------------------------------------------------------+
void ShowAuthorizationFailure() {
    if(!ShowAuthFailureMessage) return;
    
    // 检查是否在重试状态，显示不同的消息
    if(g_auth_retry_active) {
        string retry_message = "🔄 SMC指标正在验证授权\n\n";
        retry_message += "状态: " + g_auth_failure_reason + "\n";
        retry_message += "重试进度: " + IntegerToString(g_auth_retry_count) + "/" + IntegerToString(MaxAuthRetries) + "\n\n";
        retry_message += "请稍候，系统正在尝试获取账号信息...\n";
        retry_message += "如果长时间无响应，请检查网络连接或重启MT4";
        
        Comment(retry_message);
        Print("🔄 " + g_auth_failure_reason + " (重试 " + IntegerToString(g_auth_retry_count) + "/" + IntegerToString(MaxAuthRetries) + ")");
        
        // 显示重试状态的图表标签
        string retry_obj = "AUTH_RETRY_STATUS";
        if(ObjectFind(0, retry_obj) < 0) {
            ObjectCreate(0, retry_obj, OBJ_LABEL, 0, 0, 0);
        }
        ObjectSetInteger(0, retry_obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, retry_obj, OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, retry_obj, OBJPROP_YDISTANCE, 50);
        ObjectSetInteger(0, retry_obj, OBJPROP_COLOR, clrOrange);
        ObjectSetInteger(0, retry_obj, OBJPROP_FONTSIZE, 12);
        ObjectSetString(0, retry_obj, OBJPROP_TEXT, "🔄 验证中... (" + IntegerToString(g_auth_retry_count) + "/" + IntegerToString(MaxAuthRetries) + ")");
        
        return; // 重试期间不显示失败信息
    }
    
    string message = "🔐 SMC指标授权失败\n\n";
    message += "失败原因: " + g_auth_failure_reason + "\n\n";
    message += "当前信息:\n";
    message += "账号: " + IntegerToString(AccountNumber()) + "\n";
    message += "账户名: " + AccountName() + "\n";
    message += "经纪商: " + AccountCompany() + "\n";
    message += "账户类型: " + (IsDemo() ? "模拟账户" : "真实账户") + "\n";
    
    if(UseHardwareAuth) {
        message += "硬件ID: " + g_current_hardware_id + "\n";
    }
    
    // 如果是账号为0的问题，给出特殊提示
    if(g_account_zero_detected) {
        message += "\n💡 提示：检测到账号信息获取失败\n";
        message += "请尝试以下解决方案：\n";
        message += "1. 检查MT4是否已完全启动\n";
        message += "2. 确认网络连接正常\n";
        message += "3. 重新加载指标或重启MT4\n";
        if(EnableAuthRetry) {
            message += "4. 系统已自动重试" + IntegerToString(MaxAuthRetries) + "次但仍失败\n";
        }
    } else {
    message += "\n请联系开发者获取授权\n";
    message += "联系方式: V:2030988";
    }
    
    Comment(message);
    Print("🔐 " + g_auth_failure_reason);
    
    // 显示图表上的警告
    string warning_obj = "AUTH_WARNING";
    if(ObjectFind(0, warning_obj) < 0) {
        ObjectCreate(0, warning_obj, OBJ_LABEL, 0, 0, 0);
    }
        ObjectSetInteger(0, warning_obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, warning_obj, OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, warning_obj, OBJPROP_YDISTANCE, 50);
        ObjectSetInteger(0, warning_obj, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, warning_obj, OBJPROP_FONTSIZE, 12);
    
    if(g_account_zero_detected) {
        ObjectSetString(0, warning_obj, OBJPROP_TEXT, "🔐 账号信息获取失败 - 请检查MT4连接");
    } else {
        ObjectSetString(0, warning_obj, OBJPROP_TEXT, "🔐 未授权 - 请联系开发者");
    }
    
    // 清理重试状态标签
    string retry_obj = "AUTH_RETRY_STATUS";
    if(ObjectFind(0, retry_obj) >= 0) {
        ObjectDelete(0, retry_obj);
    }
}

//+------------------------------------------------------------------+
//| 显示授权成功信息                                                  |
//+------------------------------------------------------------------+
void ShowAuthorizationSuccess() {
    string message = "🔐 SMC指标授权验证成功\n\n";
    message += "账号: " + IntegerToString(AccountNumber()) + "\n";
    message += "账户名: " + AccountName() + "\n";
    message += "账户类型: " + (IsDemo() ? "模拟账户" : "真实账户") + "\n";
    
    if(UseTimeAuth) {
        int days_remaining = (int)((AuthEndTime - TimeCurrent()) / 86400);
        message += "授权剩余: " + IntegerToString(days_remaining) + " 天\n";
    }
    
    if(MaxDailyUsage > 0) {
        message += "今日剩余使用: " + IntegerToString(MaxDailyUsage - g_daily_usage_count) + " 次\n";
    }
    
    Print("🔐 授权验证成功");
    
    // 移除未授权提示对象（如存在）
    string warning_obj = "AUTH_WARNING";
    if(ObjectFind(0, warning_obj) >= 0) {
        ObjectDelete(0, warning_obj);
    }
    
    // 移除重试状态提示对象（如存在）
    string retry_obj = "AUTH_RETRY_STATUS";
    if(ObjectFind(0, retry_obj) >= 0) {
        ObjectDelete(0, retry_obj);
    }
    
    // 短暂显示成功信息
    Comment(message);
    
    // 3秒后清除信息
    EventSetTimer(3);
}

//+------------------------------------------------------------------+
//| 🔄 启动授权延迟重试机制                                          |
//+------------------------------------------------------------------+
void StartAuthorizationRetry() {
    if(!EnableAuthRetry || g_auth_retry_active) {
        return;
    }
    
    g_auth_retry_active = true;
    g_auth_retry_count = 0;
    g_last_auth_attempt = TimeCurrent();
    
    if(ShowRetryStatus) {
        Print("🔄 启动授权重试机制，最大重试次数: ", MaxAuthRetries);
        Comment("🔄 账号信息加载中，正在重试验证...\n请稍候，最多重试 " + IntegerToString(MaxAuthRetries) + " 次");
    }
    
    // 设置定时器进行重试
    EventSetTimer(1); // 1秒间隔检查
}

//+------------------------------------------------------------------+
//| 🔄 执行授权重试检查                                              |
//+------------------------------------------------------------------+
bool ProcessAuthorizationRetry() {
    if(!g_auth_retry_active) {
        return false;
    }
    
    datetime current_time = TimeCurrent();
    int retry_interval = 1; // 默认1秒间隔
    
    // 获取当前重试间隔
    if(g_auth_retry_count < ArraySize(AuthRetryIntervals)) {
        retry_interval = AuthRetryIntervals[g_auth_retry_count];
    } else {
        retry_interval = AuthRetryIntervals[ArraySize(AuthRetryIntervals) - 1];
    }
    
    // 检查是否到了重试时间
    if(current_time - g_last_auth_attempt < retry_interval) {
        return false; // 还没到重试时间
    }
    
    // 检查是否超过最大重试次数
    if(g_auth_retry_count >= MaxAuthRetries) {
        StopAuthorizationRetry(false); // 重试失败
        return false;
    }
    
    g_auth_retry_count++;
    g_last_auth_attempt = current_time;
    
    if(ShowRetryStatus) {
        Print("🔄 执行第 ", g_auth_retry_count, " 次授权重试...");
        Comment("🔄 正在进行第 " + IntegerToString(g_auth_retry_count) + "/" + IntegerToString(MaxAuthRetries) + " 次重试验证...");
    }
    
    // 重置授权检查状态并重新验证
    g_auth_checked = false;
    g_account_zero_detected = false;
    
    if(CheckAuthorization()) {
        StopAuthorizationRetry(true); // 重试成功
        return true;
    }
    
    // 如果仍然检测到账号为0，继续重试
    if(g_account_zero_detected) {
        if(ShowRetryStatus) {
            Print("🔄 账号仍为0，将在 ", retry_interval, " 秒后重试");
        }
        return false;
    } else {
        // 如果不是账号为0的问题，则停止重试
        StopAuthorizationRetry(false);
        return false;
    }
}

//+------------------------------------------------------------------+
//| 🔄 停止授权重试机制                                              |
//+------------------------------------------------------------------+
void StopAuthorizationRetry(bool success) {
    if(!g_auth_retry_active) {
        return;
    }
    
    g_auth_retry_active = false;
    
    if(success) {
        if(ShowRetryStatus) {
            Print("✅ 授权重试成功！总共重试了 ", g_auth_retry_count, " 次");
            Comment("✅ 授权验证成功！");
        }
        ShowAuthorizationSuccess();
    } else {
        if(ShowRetryStatus) {
            Print("❌ 授权重试失败，已达到最大重试次数 ", MaxAuthRetries);
            Comment("❌ 授权验证失败\n" + g_auth_failure_reason);
        }
        ShowAuthorizationFailure();
    }
    
    // 重置重试相关变量
    g_auth_retry_count = 0;
    g_last_auth_attempt = 0;
    g_account_zero_detected = false;
}

//+------------------------------------------------------------------+
//| 反调试检测                                                        |
//+------------------------------------------------------------------+
bool IsDebuggerPresent() {
    if(!AntiDebugMode) return false;
    
    // 简单的反调试检测
    datetime start_time = GetTickCount();
    Sleep(1);
    datetime end_time = GetTickCount();
    
    // 如果时间差异过大，可能存在调试器
    if(end_time - start_time > 100) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| 获取授权状态（供EA调用）                                          |
//+------------------------------------------------------------------+
bool IsAuthorized() {
    return g_is_authorized;
}

//+------------------------------------------------------------------+
//| 获取授权信息（供EA调用）                                          |
//+------------------------------------------------------------------+
string GetAuthorizationInfo() {
    if(!g_is_authorized) {
        return "未授权: " + g_auth_failure_reason;
    }
    
    string info = "已授权 | 账号: " + IntegerToString(AccountNumber());
    
    if(UseTimeAuth) {
        int days_remaining = (int)((AuthEndTime - TimeCurrent()) / 86400);
        info += " | 剩余: " + IntegerToString(days_remaining) + "天";
    }
    
    if(MaxDailyUsage > 0) {
        info += " | 今日剩余: " + IntegerToString(MaxDailyUsage - g_daily_usage_count);
    }
    
    return info;
}

//+------------------------------------------------------------------+
//| 辅助函数：字符串分割                                              |
//+------------------------------------------------------------------+
int Auth_StringSplit(string str, ushort separator, string &result[]) {
    int count = 0;
    string temp = str;
    uchar sep_char = (uchar)separator;
    string sep = CharToString(sep_char);
    
    while(StringFind(temp, sep) >= 0) {
        int pos = StringFind(temp, sep);
        int new_size = (int)(count + 1);
        ArrayResize(result, new_size);
        result[count] = StringSubstr(temp, 0, pos);
        temp = StringSubstr(temp, pos + 1);
        count++;
    }
    
    if(StringLen(temp) > 0) {
        int new_size = (int)(count + 1);
        ArrayResize(result, new_size);
        result[count] = temp;
        count++;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| 辅助函数：字符串去除左侧空格                                      |
//+------------------------------------------------------------------+
void Auth_StringTrimLeft(string &str) {
    while(StringLen(str) > 0 && StringGetCharacter(str, 0) == ' ') {
        str = StringSubstr(str, 1);
    }
}

//+------------------------------------------------------------------+
//| 辅助函数：字符串去除右侧空格                                      |
//+------------------------------------------------------------------+
void Auth_StringTrimRight(string &str) {
    while(StringLen(str) > 0 && StringGetCharacter(str, StringLen(str) - 1) == ' ') {
        str = StringSubstr(str, 0, StringLen(str) - 1);
    }
}

//+------------------------------------------------------------------+
//| 指标初始化函数                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // 反调试检测
    if(IsDebuggerPresent()) {
        Print("🔐 检测到调试环境，程序退出");
        return INIT_FAILED;
    }
    
    // 授权验证
    if(!CheckAuthorization()) {
        // 检查是否是账号为0的情况且启用了重试机制
        if(g_account_zero_detected && EnableAuthRetry) {
            // 启动延迟重试机制，不立即失败
            StartAuthorizationRetry();
            Print("🔄 检测到账号信息未加载，启动延迟重试机制");
            // 继续初始化，但标记为未授权状态
        } else {
            // 其他授权失败情况，直接返回失败
        ShowAuthorizationFailure();
        return INIT_FAILED;
    }
    } else {
    // 显示授权成功信息
    ShowAuthorizationSuccess();
    }
    
    // 验证性能优化参数
    if(MaxBarsToCalculate < 0) {
        Print("SMC 错误: MaxBarsToCalculate不能为负数，已重置为1000");
        MaxBarsToCalculate = 1000;
    }
    
    if(MaxBarsToCalculate > 0 && MaxBarsToCalculate < StructureLookback * 3) {
        Print("SMC 警告: MaxBarsToCalculate(", MaxBarsToCalculate, ")可能太小，建议至少", StructureLookback * 3, "根K线");
        Print("SMC 提示: 设置为0可计算所有K线，但会影响性能");
    }
    
    if(MaxBarsToCalculate == 0) {
        Print("SMC 提示: 将计算所有K线，这可能影响性能，建议设置为500-2000");
    } else {
        Print("SMC 性能优化: 限制计算", MaxBarsToCalculate, "根K线，可提高运行速度");
    }
    
    // 设置指标缓冲区
    SetIndexBuffer(0, BOS_Top);
    SetIndexBuffer(1, BOS_Bottom);
    SetIndexBuffer(2, CHOCH_Top);
    SetIndexBuffer(3, CHOCH_Bottom);
    SetIndexBuffer(4, FVG_Top);
    SetIndexBuffer(5, FVG_Bottom);
    SetIndexBuffer(6, OB_Top);
    SetIndexBuffer(7, OB_Bottom);
    SetIndexBuffer(8, MA21_Buffer);
    SetIndexBuffer(9, OB_Quality);

    // 设置缓冲区样式 - 所有缓冲区不直接绘制，由图形对象处理
    SetIndexStyle(0, DRAW_NONE);
    SetIndexStyle(1, DRAW_NONE);
    SetIndexStyle(2, DRAW_NONE);
    SetIndexStyle(3, DRAW_NONE);
    SetIndexStyle(4, DRAW_NONE);
    SetIndexStyle(5, DRAW_NONE);
    SetIndexStyle(6, DRAW_NONE);
    SetIndexStyle(7, DRAW_NONE);
    // MA21均线样式设置
    if(ShowMA21Line) {
        SetIndexStyle(8, DRAW_LINE, STYLE_SOLID, MA21_LineWidth, MA21_Color);
    } else {
        SetIndexStyle(8, DRAW_NONE);
    }
    SetIndexStyle(9, DRAW_NONE);

    // 设置缓冲区标签
    SetIndexLabel(0, "BOS Top");
    SetIndexLabel(1, "BOS Bottom");
    SetIndexLabel(2, "CHoCH Top");
    SetIndexLabel(3, "CHoCH Bottom");
    SetIndexLabel(4, "FVG Top");
    SetIndexLabel(5, "FVG Bottom");
    SetIndexLabel(6, "OB Top");
    SetIndexLabel(7, "OB Bottom");
    SetIndexLabel(8, "MA21");
    SetIndexLabel(9, "OB Quality");

    // 设置空值
    SetIndexEmptyValue(0, EMPTY_VALUE);
    SetIndexEmptyValue(1, EMPTY_VALUE);
    SetIndexEmptyValue(2, EMPTY_VALUE);
    SetIndexEmptyValue(3, EMPTY_VALUE);
    SetIndexEmptyValue(4, EMPTY_VALUE);
    SetIndexEmptyValue(5, EMPTY_VALUE);
    SetIndexEmptyValue(6, EMPTY_VALUE);
    SetIndexEmptyValue(7, EMPTY_VALUE);
    SetIndexEmptyValue(8, EMPTY_VALUE);
    SetIndexEmptyValue(9, EMPTY_VALUE);

    // 初始化数组
    ArrayResize(swing_points, 1000);
    ArrayResize(poi_zones, MaxFVGZones + MaxOBZones);
    ArrayResize(structure_zones, MaxBOSZones + MaxCHOCHZones);
    
    // 初始化市场结构状态
    g_market_trend = 0;
    g_last_hh_index = -1;
    g_last_hl_index = -1;
    g_last_lh_index = -1;
    g_last_ll_index = -1;
    
    // 初始化状态机变量
    g_trend_state = 0;
    g_protected_high_index = -1;
    g_protected_low_index = -1;
    g_last_bos_bar = -1;
    g_last_choch_bar = -1;
    g_last_mode_state = CHOCH_InstantTrendUpdate;
    
    // 初始化CHoCH唯一性状态标志
    g_choch_down_occurred_in_uptrend = false;
    g_choch_up_occurred_in_downtrend = false;
    
    // 设置指标名称
    IndicatorShortName("SMC OrderFlow (" + IntegerToString(StructureLookback) + ")");
    
    // 清除所有旧的SMC对象
    ObjectsDeleteAll(0, "SMC_");
    
    // 启动1秒定时器用于更细粒度的刷新（满足收盘后5秒内持续刷新）
    EventSetTimer(1);
    
    // 显示初始化信息
    Comment("SMC指标已加载，正在分析市场结构...");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 指标计算函数                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // 授权检查：如果未授权，则直接停止计算
    if (!g_is_authorized) {
        return 0;
    }

    // 运行时重复授权检查（例如每10分钟）
    static datetime last_recheck = 0;
    if(TimeCurrent() - last_recheck > 600) { // 600秒 = 10分钟
        if(!CheckAuthorization()) {
            ShowAuthorizationFailure();
            g_is_authorized = false; // 标记为未授权
            return 0; // 停止计算
        }
        last_recheck = TimeCurrent();
    }
    
    // 确保有足够的数据
    if(rates_total < StructureLookback * 2 + 10) return(0);
    
    // --- 新K线检测 ---
    static datetime last_bar_time = 0;
    bool is_new_bar = false;
    if(last_bar_time != time[0])
    {
        is_new_bar = true;
        last_bar_time = time[0];
        g_last_full_recalc_time = TimeCurrent();
        g_data_version++; // 新K线触发一次版本递增
    }

    // --- 核心计算逻辑 ---
    // 仅在首次加载或新K线出现时，进行全面的重新计算
    if(prev_calculated == 0 || is_new_bar)
    {
        int limit;
        // 性能优化：限制计算范围
        if(MaxBarsToCalculate > 0) {
            limit = MathMin(rates_total - 1, MaxBarsToCalculate);
        } else {
            limit = rates_total - 1;
        }

        // 重置所有数据结构和图形
        ObjectsDeleteAll(0, "SMC_");
        structure_count = 0;
        swing_count = 0;
        poi_count = 0;
        g_data_version++; // 完整重算导致版本变化
        
        // 首次计算，清空所有缓冲区
        ArrayInitialize(BOS_Top, EMPTY_VALUE);
        ArrayInitialize(BOS_Bottom, EMPTY_VALUE);
        ArrayInitialize(CHOCH_Top, EMPTY_VALUE);
        ArrayInitialize(CHOCH_Bottom, EMPTY_VALUE);
        ArrayInitialize(FVG_Top, EMPTY_VALUE);
        ArrayInitialize(FVG_Bottom, EMPTY_VALUE);
        ArrayInitialize(OB_Top, EMPTY_VALUE);
        ArrayInitialize(OB_Bottom, EMPTY_VALUE);
        ArrayInitialize(MA21_Buffer, EMPTY_VALUE);

        // --- MA21均线计算 ---
        if(ShowMA21Line || EnableMA21Filter) {
            CalculateMA21(rates_total, high, low, close, open);
        }

        // --- 缠论优化预处理：K线包含处理和分型识别 ---
        if(EnableChanOptimization) {
            ArrayResize(g_processed_bars, rates_total);
            g_processed_bars_count = ProcessInclusion(prev_calculated, rates_total, g_processed_bars);
            IdentifyChanFractals(g_processed_bars_count, g_processed_bars);
        }
        // --- 缠论优化预处理结束 ---

        // Print("SMC: Recalculating... Limit=", limit);

        // 主计算循环: 从历史向现在 (i--)
        for(int i = limit; i >= 0; i--) {
            // 计算MA21均线 (每个K线都需要更新)
            if((ShowMA21Line || EnableMA21Filter) && i < rates_total - MA21_Period) {
                CalculateMA21SingleBar(i, high, low, close, open);
            }

            // 识别Swing Points (原有逻辑)
            if (i >= StructureLookback) IdentifySwingPoints(i, high, low);

            // V1.70：缠论或ZigZag任一启用时，BOS/CHOCH检测移到过滤之后
            // 这样可以确保BOS/CHOCH基于过滤后的摆点
            if(!EnableChanOptimization && !EnableZigZagFilter) {
                // 两种过滤均未启用时，在循环中检测BOS/CHOCH
                if (i >= StructureLookback) DetectStructureBreaks(i, high, low, close);
            }

            // 识别FVG (分析当前位置的3K线模式)
            if (i >= 2) IdentifyFVG(i, open, high, low, close);

            // 识别Order Blocks (分析当前位置及历史K线模式)
            if (i >= 5) IdentifyOrderBlocks(i, open, high, low, close);

            // 更新POI区域状态 (检查当前K线是否触及历史POI)
            UpdatePOIStatus(i, high, low, close);

            // 更新缓冲区 (将计算结果存储到指标缓冲区)
            UpdateBuffers(i);
        }

        // --- V1.70 摆点后置过滤：ZigZag(缠论之前) → 缠论 ---
        // ZigZag与缠论开关相互独立；任一启用都需在过滤后重新检测BOS/CHOCH
        FilterSwingPointsByZigZag();          // 内部按 EnableZigZagFilter 门控
        if(EnableChanOptimization) {
            FilterSwingPointsByChan();
        }

        if(EnableChanOptimization || EnableZigZagFilter) {
            // 清空旧结构，确保BOS/CHOCH仅基于过滤后的摆点
            structure_count = 0;
            // 基于过滤后的摆点重新检测BOS/CHOCH（swing_points已为过滤结果）
            for(int i = limit; i >= StructureLookback; i--) {
                DetectStructureBreaks(i, high, low, close);
            }
            // 刷新BOS/CHOCH缓冲区（主循环时structure_count=0未写入，此处补全）
            for(int i = limit; i >= 0; i--) {
                UpdateBuffers(i);
            }
            // 注意：分型标记绘制移到DrawGraphicalObjects之后，避免被清除
        }
        // --- 摆点后置过滤结束 ---

        // V1.62：后置裁剪，确保只保留每种类型最新的N个（删除超出限制的旧对象）
        TrimStructureZonesToNewest();

        g_last_full_recalc_time = TimeCurrent();
    }
    else // K线内部的Tick更新
    {
        // 只需更新当前K线(i=0)对现有POI区域的触及状态
        UpdatePOIStatus(0, high, low, close);
        // 注意：不要在每个tick无条件递增版本号。
        // 只有在数据实际变化时（新增/删除/状态改变）才在对应函数内递增，
        // 否则会导致 DrawGraphicalObjects() 每秒强制刷新。
    }

    // 刷新OB/FVG重叠评分并写入OB_Quality缓冲区(供EA读取)
    if(EnableOBLifecycle) {
        RefreshOBFVGConfluence();
        WriteOBQualityBuffer();
    }

    // 绘制图形对象 (每次都调用，函数内部会判断是否需要重绘)
    DrawGraphicalObjects();

    // 绘制分型标记（必须在DrawGraphicalObjects之后，否则会被清除）
    if(EnableChanOptimization && ShowChanFractals) {
        static datetime last_fractal_draw_time = 0;
        if(Time[0] != last_fractal_draw_time) {
            CleanupChanFractalObjects();
            int max_fractals_to_draw = MathMin(g_chan_fractal_count, 200);
            for(int i = 0; i < max_fractals_to_draw; i++) {
                DrawFractalMarker(g_chan_fractals[i]);
            }
            last_fractal_draw_time = Time[0];
        }
    }

    // V1.55新增：更新虚拟摆点（每个tick更新）
    if(EnableVirtualSwingExtension && swing_count > 0) {
        UpdateVirtualSwingPoint(high, low, rates_total);
    }

    // 绘制虚拟笔（每个tick更新，因为当前价格在变化）
    // 如果虚拟摆点已激活（替代了虚拟笔的功能），则不绘制普通虚拟笔，避免重叠
    if(ShowVirtualStroke && swing_count > 0 && !g_virtual_swing_active) {
        DrawVirtualStroke();
    }

    // V1.54新增：更新并绘制临时极点（每tick更新，解决最后摆点更新不及时的问题）
    if(ShowTemporaryExtreme && swing_count > 0) {
        UpdateTemporaryExtremes(high, low, rates_total);
        DrawTemporaryExtremes();
    }

    return(rates_total);
}

/*
//+------------------------------------------------------------------+
//| 识别Swing Points                                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 判断是否为Swing High                                             |
//+------------------------------------------------------------------+

*/

//+------------------------------------------------------------------+
//| V1.56 过滤连续的同向摆点 (模拟ZigZag行为，确保BOS逻辑与画线一致)    |
//+------------------------------------------------------------------+
void FilterSequentialSwings(int current_index)
{
    if(current_index < 1) return;
    SwingPoint current = swing_points[current_index];
    int prev_valid_idx = -1;
    
    // 向前查找最近的有效摆点 (忽略已作废的点)
    for(int i = current_index - 1; i >= 0; i--) {
        if(swing_points[i].structure_type >= 0) {
            prev_valid_idx = i;
            break;
        }
    }
    
    if(prev_valid_idx < 0) return;
    
    SwingPoint prev = swing_points[prev_valid_idx];
    
    // 规则：如果发现连续同向摆点，只保留极值
    if(current.is_high == prev.is_high) {
        bool keep_current = false;
        if(current.is_high) { 
             // 都是高点，保留更高的
             if(current.price > prev.price) keep_current = true;
        } else { 
             // 都是低点，保留更低的
             if(current.price < prev.price) keep_current = true;
        }
        
        if(keep_current) {
            swing_points[prev_valid_idx].structure_type = -1; // 废弃前一个（因为它不如当前极值）
             // 注意：前一个点被废弃后，BOS扫描将跳过它，解决了BOS出现在被过滤点的问题
             // 关键修补：重新分类当前点，使其基于更早的有效点进行HH/LH判断
             ClassifySwingPoint(current_index);
        } else {
            swing_points[current_index].structure_type = -1; // 废弃当前点（因为它不如前一个极值）
        }
    }
}

//+------------------------------------------------------------------+
//| 添加Swing Point                                                  |
//+------------------------------------------------------------------+
void AddSwingPoint(int bar, double price, bool is_high)
{
    // V1.60: 完全移除AddSwingPoint中的MA21预过滤
    // 原因1: 缠论模式下，MA21由FilterSwingPointsByChan统一处理（Mode=0基础检查）
    // 原因2: 非缠论模式下，在强趋势中MA21预过滤会把所有同向回调点（Low>MA21）全部删除
    //        导致无法构成高低交替的摆点序列，进而造成所有摆点连线消失
    // 修复: MA21过滤仅在缠论步骤（结构+信号层面）执行，不在摆点原始识别层干预
    
    if(swing_count >= ArraySize(swing_points)) {
        ArrayResize(swing_points, swing_count + 100);
    }
    
    swing_points[swing_count].bar_index = bar;
    swing_points[swing_count].price = price;
    swing_points[swing_count].is_high = is_high;
    swing_points[swing_count].is_broken = false;
    swing_points[swing_count].structure_type = -1; // 初始化为未分类
    swing_points[swing_count].is_extreme = false;  // V1.52: 初始化极点标记
    // V1.58: 记录对应的缠论处理后K线索引（用于MinStrokeBars的精确计算）
    swing_points[swing_count].processed_index = (EnableChanOptimization && g_processed_bars_count > 0)
                                                ? FindProcessedBarIndex(bar, is_high)
                                                : -1;
    
    // 分类新的swing point为HH/HL/LH/LL
    ClassifySwingPoint(swing_count);
    
    // V1.56: 解决BOS误触问题
    FilterSequentialSwings(swing_count);

    
    swing_count++;
}

//+------------------------------------------------------------------+
//| 分类Swing Point为HH/HL/LH/LL                                    |
//+------------------------------------------------------------------+
void ClassifySwingPoint(int current_index)
{
    if(current_index < 2) return; // 需要至少3个点才能开始分类

    SwingPoint current = swing_points[current_index];

    int thrPts = GetMinSwingThresholdPoints(current.bar_index);

    if(current.is_high) {
        // === V1.36优化：检查是否为全局最高点 ===
        bool is_global_highest = true;
        for(int j = 0; j < current_index; j++) {
            if(swing_points[j].is_high && swing_points[j].price >= current.price) {
                is_global_highest = false;
                break;
            }
        }

        // 当前是高点，查找前一个高点进行比较
        for(int i = current_index - 1; i >= 0; i--) {
            // V1.56 fix: 忽略被过滤的无效点 (-1)，但保留起始锚点
            if(swing_points[i].is_high && (swing_points[i].structure_type >= 0 || i < 2)) {
                // V1.36优化：如果是全局最高点，强制分类为HH，跳过最小摆幅过滤
                if(is_global_highest) {
                    current.structure_type = 0; // 强制标记为HH
                    g_last_hh_index = current_index;
                    break;
                }

                // 最小摆幅过滤
                if(MathAbs(current.price - swing_points[i].price) < thrPts * Point) {
                    current.structure_type = -1;
                    break;
                }

                if(IsPriceGreater(current.price, swing_points[i].price)) {
                    current.structure_type = 0; // HH
                    g_last_hh_index = current_index;
                } else if(IsPriceLess(current.price, swing_points[i].price)) {
                    current.structure_type = 2; // LH
                    g_last_lh_index = current_index;
                } else {
                    current.structure_type = -1; // 等高，忽略
                }
                break;
            }
        }
    } else {
        // === V1.36优化：检查是否为全局最低点 ===
        bool is_global_lowest = true;
        for(int j = 0; j < current_index; j++) {
            if(!swing_points[j].is_high && swing_points[j].price <= current.price) {
                is_global_lowest = false;
                break;
            }
        }

        // 当前是低点，查找前一个低点进行比较
        for(int i = current_index - 1; i >= 0; i--) {
            // V1.56 fix: 忽略被过滤的无效点 (-1)，但保留起始锚点
            if(!swing_points[i].is_high && (swing_points[i].structure_type >= 0 || i < 2)) {
                // V1.36优化：如果是全局最低点，强制分类为LL，跳过最小摆幅过滤
                if(is_global_lowest) {
                    current.structure_type = 3; // 强制标记为LL
                    g_last_ll_index = current_index;
                    break;
                }

                // 最小摆幅过滤
                if(MathAbs(current.price - swing_points[i].price) < thrPts * Point) {
                    current.structure_type = -1;
                    break;
                }

                if(IsPriceGreater(current.price, swing_points[i].price)) {
                    current.structure_type = 1; // HL
                    g_last_hl_index = current_index;
                } else if(IsPriceLess(current.price, swing_points[i].price)) {
                    current.structure_type = 3; // LL
                    g_last_ll_index = current_index;
                } else {
                    current.structure_type = -1; // 等低，忽略
                }
                break;
            }
        }
    }
    
    swing_points[current_index] = current;
    // 更新市场趋势状态（使用窗口多数派）
    UpdateMarketTrend();
}

//+------------------------------------------------------------------+
//| 更新市场趋势状态 - 双模式版：方案A(序列跟踪) vs 方案B(状态机)    |
//+------------------------------------------------------------------+
void UpdateMarketTrend()
{
    // 检查是否发生了模式切换
    if(g_last_mode_state != CHOCH_InstantTrendUpdate) {
        ResetTrendModeState();
        g_last_mode_state = CHOCH_InstantTrendUpdate;
    }
    
    if(CHOCH_InstantTrendUpdate) {
        // === 方案B：CHoCH驱动的状态机模型 ===
        UpdateTrendStateMachine();
    } else {
        // === 方案A：增强型序列跟踪 ===
        UpdateTrendSequenceTracking();
    }
}

//+------------------------------------------------------------------+
//| 重置趋势模式状态 - 确保模式切换的平滑性                          |
//+------------------------------------------------------------------+
void ResetTrendModeState()
{
    // 重置状态机相关变量
    g_trend_state = 0;
    g_protected_high_index = -1;
    g_protected_low_index = -1;
    g_last_bos_bar = -1;
    g_last_choch_bar = -1;
    
    // 重置CHoCH唯一性标志
    g_choch_down_occurred_in_uptrend = false;
    g_choch_up_occurred_in_downtrend = false;
    
    // 重置主趋势状态，让新模式重新计算
    g_market_trend = 0;
    
    Print("趋势判断模式已切换，状态已重置。当前模式：", 
          CHOCH_InstantTrendUpdate ? "方案B(CHoCH驱动状态机)" : "方案A(增强型序列跟踪)");
}

//+------------------------------------------------------------------+
//| 方案A：增强型序列跟踪 - 基于未破位的连续链条                      |
//+------------------------------------------------------------------+
void UpdateTrendSequenceTracking()
{
    // 寻找未破位的连续结构链条来判断趋势
    int up_chain_length = 0;    // 上升链条长度 (HL->HH->HL->HH...)
    int down_chain_length = 0;  // 下降链条长度 (LH->LL->LH->LL...)
    
    // 从最新的结构点开始向前回溯
    int last_type = -1;
    bool chain_broken = false;
    
    for(int i = swing_count - 1; i >= 0 && !chain_broken; i--) {
        int st = swing_points[i].structure_type;
        if(st == -1 || swing_points[i].is_broken) continue;
        
        if(last_type == -1) {
            last_type = st;
            if(st == 0 || st == 1) up_chain_length = 1;      // HH/HL
            else if(st == 2 || st == 3) down_chain_length = 1; // LH/LL
        } else {
            // 检查是否能形成有效的交替序列
            bool is_valid_up_sequence = false;
            bool is_valid_down_sequence = false;
            
            if((last_type == 0 || last_type == 1) && (st == 0 || st == 1)) {
                // 上升趋势中的有效交替：HH<->HL
                if((last_type == 0 && st == 1) || (last_type == 1 && st == 0)) {
                    is_valid_up_sequence = true;
                }
            } else if((last_type == 2 || last_type == 3) && (st == 2 || st == 3)) {
                // 下降趋势中的有效交替：LH<->LL  
                if((last_type == 2 && st == 3) || (last_type == 3 && st == 2)) {
                    is_valid_down_sequence = true;
                }
            }
            
            if(is_valid_up_sequence) {
                up_chain_length++;
                last_type = st;
            } else if(is_valid_down_sequence) {
                down_chain_length++;
                last_type = st;
            } else {
                chain_broken = true;
            }
        }
    }
    
    // 记录之前的趋势状态
    int previous_trend = g_market_trend;

    // === V1.36优化：降低趋势判断门槛，引入趋势记忆机制 ===

    // 优先方案：连续交替序列（至少2个有效交替点）
    if(up_chain_length >= 2 && up_chain_length > down_chain_length) {
        g_market_trend = 1;  // 上升趋势
    } else if(down_chain_length >= 2 && down_chain_length > up_chain_length) {
        g_market_trend = -1; // 下降趋势
    }
    // 备选方案：单个强势结构点推断趋势
    else {
        // 查找最近的HH和LL结构点
        int latest_hh_idx = -1;
        int latest_ll_idx = -1;

        for(int i = swing_count - 1; i >= 0; i--) {
            if(latest_hh_idx < 0 && swing_points[i].structure_type == 0 && !swing_points[i].is_broken) {
                latest_hh_idx = i; // 找到最近的未破HH
            }
            if(latest_ll_idx < 0 && swing_points[i].structure_type == 3 && !swing_points[i].is_broken) {
                latest_ll_idx = i; // 找到最近的未破LL
            }
            if(latest_hh_idx >= 0 && latest_ll_idx >= 0) break;
        }

        // 根据最近的强势结构点推断趋势
        if(latest_hh_idx >= 0 && (latest_ll_idx < 0 || latest_hh_idx > latest_ll_idx)) {
            g_market_trend = 1; // 最近出现HH → 推断为上升趋势
        } else if(latest_ll_idx >= 0 && (latest_hh_idx < 0 || latest_ll_idx > latest_hh_idx)) {
            g_market_trend = -1; // 最近出现LL → 推断为下降趋势
        }
        // 否则保持之前的趋势（趋势记忆机制）
        // g_market_trend 保持不变
        // 调试日志：趋势变化
        if(EnableDebugMode && DebugTrendChange && previous_trend != g_market_trend) {
            PrintFormat("[方案A] 趋势变化: %s → %s, 上升链=%d, 下降链=%d, HH存在=%s, LL存在=%s",
                        previous_trend == 1 ? "上升" : (previous_trend == -1 ? "下降" : "无"),
                        g_market_trend == 1 ? "上升" : (g_market_trend == -1 ? "下降" : "无"),
                        up_chain_length, down_chain_length,
                        latest_hh_idx >= 0 ? "是" : "否",
                        latest_ll_idx >= 0 ? "是" : "否");
        }        
    }
    
    // CHoCH状态标志重置逻辑
    if(previous_trend != g_market_trend) {
        if(g_market_trend == 1) {
            g_choch_up_occurred_in_downtrend = false;
        } else if(g_market_trend == -1) {
            g_choch_down_occurred_in_uptrend = false;
        }
    }
}

//+------------------------------------------------------------------+
//| 方案B：CHoCH驱动的状态机模型 - 基于受保护点位                     |
//+------------------------------------------------------------------+
void UpdateTrendStateMachine()
{
    // 记录之前的状态
    int previous_state = g_trend_state;
    int previous_trend = g_market_trend;
    
    // 检查是否有最近的BOS/CHoCH事件需要处理
    ProcessRecentStructureBreaks();
    
    // 将状态机状态同步到g_market_trend
    g_market_trend = g_trend_state;
    
    // 更新受保护点位
    UpdateProtectedLevels();
    
    // CHoCH状态标志重置逻辑
    if(previous_trend != g_market_trend) {
        if(g_market_trend == 1) {
            g_choch_up_occurred_in_downtrend = false;
        } else if(g_market_trend == -1) {
            g_choch_down_occurred_in_uptrend = false;
        }
    }
}

//+------------------------------------------------------------------+
//| 处理最近的结构破坏事件 - 状态机转换逻辑                          |
//+------------------------------------------------------------------+
void ProcessRecentStructureBreaks()
{
    // 检查向上CHoCH：最新的LH(受保护高点)被突破
    if(g_trend_state == -1) { // 当前为下降趋势
        int latest_lh_index = FindLatestUnbrokenStructure(2); // LH
        if(latest_lh_index >= 0) {
            SwingPoint latest_lh = swing_points[latest_lh_index];
            bool lh_broken_recently = CheckPriceBreakSince(latest_lh.bar_index, latest_lh.price, true);
            if(lh_broken_recently) {
                g_trend_state = 1; // CHoCH：切换为上升趋势
                g_protected_low_index = -1; // 重置受保护低点
                return;
            }
        }
    }
    
    // 检查向下CHoCH：最新的HL(受保护低点)被突破
    if(g_trend_state == 1) { // 当前为上升趋势
        int latest_hl_index = FindLatestUnbrokenStructure(1); // HL
        if(latest_hl_index >= 0) {
            SwingPoint latest_hl = swing_points[latest_hl_index];
            bool hl_broken_recently = CheckPriceBreakSince(latest_hl.bar_index, latest_hl.price, false);
            if(hl_broken_recently) {
                g_trend_state = -1; // CHoCH：切换为下降趋势
                g_protected_high_index = -1; // 重置受保护高点
                return;
            }
        }
    }
    
    // 如果当前状态为UNDEFINED，检查首次BOS来启动状态机
    if(g_trend_state == 0) {
        // 检查向上BOS：突破HH
        int latest_hh_index = FindLatestUnbrokenStructure(0); // HH
        if(latest_hh_index >= 0) {
            SwingPoint latest_hh = swing_points[latest_hh_index];
            bool hh_broken_recently = CheckPriceBreakSince(latest_hh.bar_index, latest_hh.price, true);
            if(hh_broken_recently) {
                g_trend_state = 1; // 首次向上BOS：启动上升趋势
                return;
            }
        }
        
        // 检查向下BOS：跌破LL
        int latest_ll_index = FindLatestUnbrokenStructure(3); // LL
        if(latest_ll_index >= 0) {
            SwingPoint latest_ll = swing_points[latest_ll_index];
            bool ll_broken_recently = CheckPriceBreakSince(latest_ll.bar_index, latest_ll.price, false);
            if(ll_broken_recently) {
                g_trend_state = -1; // 首次向下BOS：启动下降趋势
                return;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 更新受保护点位 - 维护状态机的关键防守位置                         |
//+------------------------------------------------------------------+
void UpdateProtectedLevels()
{
    if(g_trend_state == 1) {
        // 上升趋势：寻找最新的HL作为受保护低点
        int latest_hl = FindLatestUnbrokenStructure(1);
        if(latest_hl >= 0) {
            g_protected_low_index = latest_hl;
        }
    } else if(g_trend_state == -1) {
        // 下降趋势：寻找最新的LH作为受保护高点
        int latest_lh = FindLatestUnbrokenStructure(2);
        if(latest_lh >= 0) {
            g_protected_high_index = latest_lh;
        }
    }
}

//+------------------------------------------------------------------+
//| 检查价格是否在指定时间点之后被突破 (CHoCH优先规则辅助函数)        |
//+------------------------------------------------------------------+
bool CheckPriceBreakSince(int since_bar, double price, bool check_upward_break)
{
    if(since_bar < 0 || since_bar >= Bars) return false;
    
    // 从since_bar到当前K线，检查是否有价格突破
    for(int i = since_bar - 1; i >= 0; i--) { // 从since_bar的下一根K线开始检查
        if(check_upward_break) {
            // 检查向上突破：高点是否超过price
            if(i < ArraySize(High) && IsPriceGreater(High[i], price)) {
                return true;
            }
        } else {
            // 检查向下突破：低点是否低于price
            if(i < ArraySize(Low) && IsPriceLess(Low[i], price)) {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| 验证受保护的摆动点是否仍然有效 (BOS验证辅助函数)                 |
//+------------------------------------------------------------------+
bool IsProtectedSwingValid(int swing_bar, double swing_price, bool is_protected_low)
{
    if(swing_bar < 0 || swing_bar >= Bars) return false;
    
    // 从受保护摆动点形成后到当前，检查是否被突破
    for(int i = swing_bar - 1; i >= 0; i--) {
        if(is_protected_low) {
            // 检查受保护低点是否被跌破
            if(i < ArraySize(Low) && IsPriceLess(Low[i], swing_price)) {
                return false; // 受保护低点被跌破，结构无效
            }
        } else {
            // 检查受保护高点是否被突破
            if(i < ArraySize(High) && IsPriceGreater(High[i], swing_price)) {
                return false; // 受保护高点被突破，结构无效
            }
        }
    }
    return true; // 受保护摆动点仍然有效
}

//+------------------------------------------------------------------+
//| 检测结构突破 (BOS/CHoCH) - 优化版：增加受保护摆动点验证          |
//+------------------------------------------------------------------+
void DetectStructureBreaks(int current_bar, const double &high[], const double &low[], const double &close[])
{
    if(swing_count < 4) return; // 需要足够的swing points进行分析
    if(current_bar < 0 || current_bar >= ArraySize(close)) return;

    // === V1.36优化：保存当前趋势状态，避免方案B中趋势更新导致的BOS/CHOCH标记错误 ===
    int current_trend = g_market_trend;

    // --- 计算辅助数据：当前K线实体比例与ATR动量 ---
    double candle_high = high[current_bar];
    double candle_low  = low[current_bar];
    double candle_open = iOpen(NULL,0,current_bar);
    double candle_close= close[current_bar];
    double candle_range= MathMax(candle_high - candle_low, Point);
    double candle_body = MathAbs(candle_close - candle_open);
    double body_ratio  = candle_body / candle_range;
    double atr = GetAtrSafe(current_bar);
    double momentum_ratio = candle_range / atr;

    // === BOS (优化版：增加受保护摆动点验证) ===
    // V1.36: 使用保存的趋势状态current_trend，而不是可能已更新的g_market_trend
    if(current_trend == 1) {
        int target_hh_index = FindLatestUnbrokenStructure(0);
        if(target_hh_index >= 0) {
            SwingPoint target_hh = swing_points[target_hh_index];
            
            // === 新增：受保护摆动点验证 ===
            // 找到与该HH配对的HL(受保护低点)
            int protected_hl_index = -1;
            for(int i = target_hh_index + 1; i < swing_count; i++) {
                if(swing_points[i].structure_type == 1) { // HL
                    protected_hl_index = i;
                    break;
                }
            }
            
            bool structure_valid = true;
            if(protected_hl_index >= 0) {
                SwingPoint protected_hl = swing_points[protected_hl_index];
                // 验证受保护低点是否仍然有效（未被跌破）
                structure_valid = IsProtectedSwingValid(protected_hl.bar_index, protected_hl.price, true);
            }
            
            bool hh_broken = (ConfirmBreakClose ? IsPriceGreater(candle_close, target_hh.price)
                                                : IsPriceGreater(candle_high,  target_hh.price));
            bool quality_ok = IsDisplacementOK(body_ratio, momentum_ratio);
            bool fvg_ok = (!RequireFVG_BOS) || HasRecentFVG(current_bar, true, high, low, close);
            
            // 只有在结构仍然有效的情况下才识别BOS
            // V1.63：缠论模式下仅当swing_bar在过滤后摆点集合中时添加（防御性校验）
            if(hh_broken && quality_ok && fvg_ok && structure_valid &&
               (!EnableChanOptimization || IsSwingBarInCurrentSet(target_hh.bar_index))) {
                swing_points[target_hh_index].is_broken = true;
                AddStructureZone(current_bar, target_hh.price, true, 0, target_hh.bar_index);
                g_last_break_up_bar = current_bar;
                // 上升趋势内确认顺势BOS后，说明之前的向下CHoCH（若有）已被否定，允许后续再次检测新的向下CHoCH
                g_choch_down_occurred_in_uptrend = false;

                // V1.36调试日志
                if(EnableDebugMode && DebugBOSCHOCH) {
                    PrintFormat("[BOS] Bar=%d, Price=%.5f, Type=看涨, Trend=上升, Structure=HH突破",
                                current_bar, target_hh.price);
                }
            }
        }
    } else if(current_trend == -1) {
        int target_ll_index = FindLatestUnbrokenStructure(3);
        if(target_ll_index >= 0) {
            SwingPoint target_ll = swing_points[target_ll_index];
            
            // === 新增：受保护摆动点验证 ===
            // 找到与该LL配对的LH(受保护高点)
            int protected_lh_index = -1;
            for(int i = target_ll_index + 1; i < swing_count; i++) {
                if(swing_points[i].structure_type == 2) { // LH
                    protected_lh_index = i;
                    break;
                }
            }
            
            bool structure_valid = true;
            if(protected_lh_index >= 0) {
                SwingPoint protected_lh = swing_points[protected_lh_index];
                // 验证受保护高点是否仍然有效（未被突破）
                structure_valid = IsProtectedSwingValid(protected_lh.bar_index, protected_lh.price, false);
            }
            
            bool ll_broken = (ConfirmBreakClose ? IsPriceLess(candle_close, target_ll.price)
                                                : IsPriceLess(candle_low,   target_ll.price));
            bool quality_ok = IsDisplacementOK(body_ratio, momentum_ratio);
            bool fvg_ok = (!RequireFVG_BOS) || HasRecentFVG(current_bar, false, high, low, close);
            
            // 只有在结构仍然有效的情况下才识别BOS
            // V1.63：缠论模式下仅当swing_bar在过滤后摆点集合中时添加
            if(ll_broken && quality_ok && fvg_ok && structure_valid &&
               (!EnableChanOptimization || IsSwingBarInCurrentSet(target_ll.bar_index))) {
                swing_points[target_ll_index].is_broken = true;
                AddStructureZone(current_bar, target_ll.price, false, 0, target_ll.bar_index);
                g_last_break_down_bar = current_bar;
                // 下降趋势内确认顺势BOS后，说明之前的向上CHoCH（若有）已被否定，允许后续再次检测新的向上CHoCH
                g_choch_up_occurred_in_downtrend = false;

                // V1.36调试日志
                if(EnableDebugMode && DebugBOSCHOCH) {
                    PrintFormat("[BOS] Bar=%d, Price=%.5f, Type=看跌, Trend=下降, Structure=LL突破",
                                current_bar, target_ll.price);
                }
            }
        }
    }

    // === CHoCH (优化版：唯一性规则，防止重复标记) ===
    // V1.36: 使用保存的趋势状态current_trend
    // 向下CHoCH：在上升趋势中，且尚未发生过向下CHoCH
    // 仅当目标HL存在且其时间晚于最近一次顺势BOS之后，才允许触发CHoCH，避免过期结构误判
    if(current_trend == 1 && !g_choch_down_occurred_in_uptrend) {
        int target_hl_index = FindLatestUnbrokenStructure(1);
        if(target_hl_index >= 0) {
            SwingPoint target_hl = swing_points[target_hl_index];
            // 若存在最近的向上BOS，且该BOS比此HL更近，则仍允许CHoCH（BOS之后回落破最近HL才是首个CHoCH）
            // 若此HL比最近BOS更早太多，说明结构可能过期，此处不额外严格限制，只在后续需要时可加窗口过滤
            bool hl_broken = (ConfirmBreakClose ? IsPriceLess(candle_close, target_hl.price)
                                                : IsPriceLess(candle_low,   target_hl.price));
            bool quality_ok = IsDisplacementOK(body_ratio, momentum_ratio);
            bool fvg_ok = (!RequireFVG_CHOCH) || HasRecentFVG(current_bar, false, high, low, close);
            // V1.63：缠论模式下仅当swing_bar在过滤后摆点集合中时添加
            if(hl_broken && quality_ok && fvg_ok &&
               (!EnableChanOptimization || IsSwingBarInCurrentSet(target_hl.bar_index))) {
                swing_points[target_hl_index].is_broken = true;
                AddStructureZone(current_bar, target_hl.price, false, 1, target_hl.bar_index);
                g_last_break_down_bar = current_bar;

                // === 关键：设置状态标志，防止重复标记向下CHoCH ===
                g_choch_down_occurred_in_uptrend = true;

                // V1.36调试日志
                if(EnableDebugMode && DebugBOSCHOCH) {
                    PrintFormat("[CHOCH] Bar=%d, Price=%.5f, Type=看跌, PrevTrend=上升, Structure=HL跌破",
                                current_bar, target_hl.price);
                }
            }
        }
    }
    // 向上CHoCH：在下降趋势中，且尚未发生过向上CHoCH
    // V1.36: 使用保存的趋势状态current_trend
    else if(current_trend == -1 && !g_choch_up_occurred_in_downtrend) {
        int target_lh_index = FindLatestUnbrokenStructure(2);
        if(target_lh_index >= 0) {
            SwingPoint target_lh = swing_points[target_lh_index];
            bool lh_broken = (ConfirmBreakClose ? IsPriceGreater(candle_close, target_lh.price)
                                                : IsPriceGreater(candle_high, target_lh.price));
            bool quality_ok = IsDisplacementOK(body_ratio, momentum_ratio);
            bool fvg_ok = (!RequireFVG_CHOCH) || HasRecentFVG(current_bar, true, high, low, close);
            // V1.63：缠论模式下仅当swing_bar在过滤后摆点集合中时添加
            if(lh_broken && quality_ok && fvg_ok &&
               (!EnableChanOptimization || IsSwingBarInCurrentSet(target_lh.bar_index))) {
                swing_points[target_lh_index].is_broken = true;
                AddStructureZone(current_bar, target_lh.price, true, 1, target_lh.bar_index);
                g_last_break_up_bar = current_bar;

                // === 关键：设置状态标志，防止重复标记向上CHoCH ===
                g_choch_up_occurred_in_downtrend = true;

                // V1.36调试日志
                if(EnableDebugMode && DebugBOSCHOCH) {
                    PrintFormat("[CHOCH] Bar=%d, Price=%.5f, Type=看涨, PrevTrend=下降, Structure=LH突破",
                                current_bar, target_lh.price);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| V1.63：验证 bar 是否在当前 swing_points 中（缠论模式下确保BOS/CHOCH仅基于过滤后摆点）|
//+------------------------------------------------------------------+
bool IsSwingBarInCurrentSet(int bar_index)
{
    for(int k = 0; k < swing_count; k++)
        if(swing_points[k].bar_index == bar_index) return true;
    return false;
}

//+------------------------------------------------------------------+
//| 查找最近未被突破的指定类型结构点                                  |
//+------------------------------------------------------------------+
int FindLatestUnbrokenStructure(int structure_type)
{
    // structure_type: 0=HH, 1=HL, 2=LH, 3=LL
    // 从最新的swing point开始向前查找
    for(int i = swing_count - 1; i >= 0; i--) {
        if(swing_points[i].structure_type == structure_type && !swing_points[i].is_broken) {
            return i;
        }
    }
    return -1; // 未找到
}

//+------------------------------------------------------------------+
//| 识别Fair Value Gap (FVG) - 优化为从旧到新的计算顺序             |
//+------------------------------------------------------------------+
void IdentifyFVG(int current_bar, const double &open[], const double &high[], const double &low[], const double &close[])
{
    // 边界检查：确保能访问当前K线和后面两根K线（MT4标准i--循环）
    if(current_bar < 2) return;
    if(current_bar + 2 >= ArraySize(high)) return;
    
    // 在MT4标准i--循环中，当处理K线current_bar时：
    // current_bar+2 = 更旧的K线（第一根）
    // current_bar+1 = 较旧的K线（第二根，中间）  
    // current_bar   = 当前K线（第三根）
    
    // 预计算 ATR，用于质量评分
    double fvg_atr = iATR(NULL,0,AtrPeriod,current_bar);
    if(fvg_atr <= 0) fvg_atr = MathMax(high[current_bar] - low[current_bar], Point);
    
    // 检查看涨FVG：第一根K线高点 < 第三根K线低点
    if(high[current_bar + 2] < low[current_bar]) {
        double gap_size = low[current_bar] - high[current_bar + 2];
        
        // 确保缺口足够大（至少1个点差）
        if(gap_size >= Point) {
            // 验证中间K线的强势特征
            bool valid_bullish_fvg = close[current_bar + 1] > open[current_bar + 1] && // 中间K线看涨
                                    close[current_bar] > close[current_bar + 1];        // 当前K线延续上涨
            
            if(valid_bullish_fvg) {
                // 质量评分：Gap/ATR + 趋势一致；并进行折/溢价过滤
                double gap_score = MathMin(1.0, gap_size / MathMax(fvg_atr, Point));
                double trend_score = (g_market_trend == 1) ? 1.0 : 0.0;
                double quality = 0.6*gap_score + 0.4*trend_score;
                bool pd_ok = true;
                if(UsePremiumDiscount) {
                    int window = MathMax(StructureLookback * OuterLookbackFactor * 4, 20);
                    int hh_idx = iHighest(NULL,0,MODE_HIGH,window,current_bar);
                    int ll_idx = iLowest(NULL,0,MODE_LOW,window,current_bar);
                    double outer_hi = iHigh(NULL,0,hh_idx);
                    double outer_lo = iLow(NULL,0,ll_idx);
                    double mid50 = (outer_hi + outer_lo) * 0.5;
                    double zone_mid = (low[current_bar] + high[current_bar + 2]) * 0.5;
                    pd_ok = (zone_mid <= mid50);
                    if(pd_ok && PreferGolden62) {
                        double discount62 = outer_lo + 0.62*(outer_hi - outer_lo);
                        pd_ok = (zone_mid <= discount62);
                    }
                }
                if(quality >= FVGQualityThreshold && pd_ok) {
                    // FVG区域标记在中间K线上
                    AddPOIZone(current_bar + 1, low[current_bar], high[current_bar + 2], true, 0);
                }
            }
        }
    }
    
    // 检查看跌FVG：第一根K线低点 > 第三根K线高点
    if(low[current_bar + 2] > high[current_bar]) {
        double gap_size = low[current_bar + 2] - high[current_bar];
        
        // 确保缺口足够大（至少1个点差）
        if(gap_size >= Point) {
            // 验证中间K线的强势特征
            bool valid_bearish_fvg = close[current_bar + 1] < open[current_bar + 1] && // 中间K线看跌
                                    close[current_bar] < close[current_bar + 1];        // 当前K线延续下跌
            
            if(valid_bearish_fvg) {
                double gap_score = MathMin(1.0, gap_size / MathMax(fvg_atr, Point));
                double trend_score = (g_market_trend == -1) ? 1.0 : 0.0;
                double quality = 0.6*gap_score + 0.4*trend_score;
                bool pd_ok = true;
                if(UsePremiumDiscount) {
                    int window = MathMax(StructureLookback * OuterLookbackFactor * 4, 20);
                    int hh_idx = iHighest(NULL,0,MODE_HIGH,window,current_bar);
                    int ll_idx = iLowest(NULL,0,MODE_LOW,window,current_bar);
                    double outer_hi = iHigh(NULL,0,hh_idx);
                    double outer_lo = iLow(NULL,0,ll_idx);
                    double mid50 = (outer_hi + outer_lo) * 0.5;
                    double zone_mid = (low[current_bar + 2] + high[current_bar]) * 0.5;
                    pd_ok = (zone_mid >= mid50);
                    if(pd_ok && PreferGolden62) {
                        double premium38 = outer_hi - 0.62*(outer_hi - outer_lo); // 约等于上侧38%线
                        pd_ok = (zone_mid >= premium38);
                    }
                }
                if(quality >= FVGQualityThreshold && pd_ok) {
                    // FVG区域标记在中间K线上
                    AddPOIZone(current_bar + 1, low[current_bar + 2], high[current_bar], false, 0);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 识别Order Blocks - 优化为从旧到新的计算顺序                     |
//+------------------------------------------------------------------+
void IdentifyOrderBlocks(int current_bar, const double &open[], const double &high[], 
                        const double &low[], const double &close[])
{
    // 边界检查：确保能访问当前K线和前面的K线
    if(current_bar < 5) return;  // 需要足够的历史数据
    if(current_bar >= ArraySize(high)) return;
    
    // 计算当前K线和前一根K线的波动范围
    double current_range = high[current_bar] - low[current_bar];
    double prev_range = high[current_bar - 1] - low[current_bar - 1];
    
    // 避免除零错误
    if(prev_range <= 0) prev_range = Point;
    
    // 检查看涨Order Block：当前K线强势上涨
    bool strong_bullish = (close[current_bar] > open[current_bar]) &&                    // 当前K线看涨
                         (close[current_bar] - open[current_bar] > current_range * 0.6) && // 实体占比大
                         (close[current_bar] > close[current_bar - 1]) &&                 // 高于前一根收盘
                         (current_range > prev_range * 1.2);                             // 波动幅度增大
    
    bool allow_bullish_ob = (!OB_OnlyDrive) || (current_bar == g_last_break_up_bar);
    if(strong_bullish && allow_bullish_ob) {
        // 寻找前面最近的看跌K线作为Order Block
        for(int i = current_bar - 1; i >= MathMax(current_bar - 5, 0); i--) {
            if(close[i] < open[i]) { // 找到看跌K线
                AddPOIZone(i, high[i], low[i], true, 1);
                if(EnableOBDebug) {
                    Print("SMC OB创建: 看涨Order Block at bar ", i, " 时间: ", TimeToString(Time[i]), 
                          " 价格范围: ", DoubleToString(low[i], Digits), " - ", DoubleToString(high[i], Digits),
                          " 触发K线: ", current_bar, " 强势比率: ", DoubleToString(current_range/prev_range, 2));
                }
                break;
            }
        }
    }
    
    // 检查看跌Order Block：当前K线强势下跌
    bool strong_bearish = (close[current_bar] < open[current_bar]) &&                    // 当前K线看跌
                         (open[current_bar] - close[current_bar] > current_range * 0.6) && // 实体占比大
                         (close[current_bar] < close[current_bar - 1]) &&                 // 低于前一根收盘
                         (current_range > prev_range * 1.2);                             // 波动幅度增大
    
    bool allow_bearish_ob = (!OB_OnlyDrive) || (current_bar == g_last_break_down_bar);
    if(strong_bearish && allow_bearish_ob) {
        // 寻找前面最近的看涨K线作为Order Block
        for(int i = current_bar - 1; i >= MathMax(current_bar - 5, 0); i--) {
            if(close[i] > open[i]) { // 找到看涨K线
                AddPOIZone(i, high[i], low[i], false, 1);
                if(EnableOBDebug) {
                    Print("SMC OB创建: 看跌Order Block at bar ", i, " 时间: ", TimeToString(Time[i]), 
                          " 价格范围: ", DoubleToString(low[i], Digits), " - ", DoubleToString(high[i], Digits),
                          " 触发K线: ", current_bar, " 强势比率: ", DoubleToString(current_range/prev_range, 2));
                }
                break;
            }
        }
    }
}



//+------------------------------------------------------------------+
//| 删除最旧的POI区域（滑动窗口机制）                                |
//+------------------------------------------------------------------+
void RemoveOldestPOIZone()
{
    if(poi_count <= 0) return;
    
    // 删除最旧区域对应的图形对象
    string type_prefix = (poi_zones[0].poi_type == 0) ? "FVG" : "OB";
    string obj_name = "SMC_Zone_" + type_prefix + "_" + IntegerToString(poi_zones[0].start_bar);
    string label_name = "SMC_ZoneLabel_" + type_prefix + "_" + IntegerToString(poi_zones[0].start_bar);
    string border_name = obj_name + "_Border";
    
    ObjectDelete(obj_name);
    ObjectDelete(label_name);
    ObjectDelete(border_name); // 删除边框对象
    
    // Print("SMC: 删除最旧的", type_prefix, "区域 at bar ", poi_zones[0].start_bar, " 时间: ", TimeToString(Time[poi_zones[0].start_bar]));
    
    // 将数组元素左移（删除第一个元素）
    for(int i = 0; i < poi_count - 1; i++) {
        poi_zones[i] = poi_zones[i + 1];
    }
    
    poi_count--;
    g_data_version++; // 删除旧POI，版本递增
}

//+------------------------------------------------------------------+
//| 计算指定类型POI区域的数量                                        |
//+------------------------------------------------------------------+
int CountPOIZonesByType(int poi_type)
{
    int count = 0;
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type == poi_type) {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| 删除最旧的指定类型POI区域                                        |
//+------------------------------------------------------------------+
void RemoveOldestPOIZoneByType(int target_type)
{
    if(poi_count <= 0) return;
    
    // 查找最旧的指定类型区域
    int oldest_index = -1;
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type == target_type) {
            oldest_index = i;
            break;
        }
    }
    
    if(oldest_index == -1) return; // 没有找到指定类型的区域
    
    // 删除最旧区域对应的图形对象
    string type_prefix = (target_type == 0) ? "FVG" : "OB";
    string obj_name = "SMC_Zone_" + type_prefix + "_" + IntegerToString(poi_zones[oldest_index].start_bar);
    string label_name = "SMC_ZoneLabel_" + type_prefix + "_" + IntegerToString(poi_zones[oldest_index].start_bar);
    
    ObjectDelete(obj_name);
    ObjectDelete(label_name);
    
    // Print("SMC: 删除最旧的", type_prefix, "区域 at bar ", poi_zones[oldest_index].start_bar);
    
    // 将数组元素左移（删除指定索引的元素）
    for(int i = oldest_index; i < poi_count - 1; i++) {
        poi_zones[i] = poi_zones[i + 1];
    }
    
    poi_count--;
    g_data_version++; // 删除旧POI（按类型），版本递增
}

//+------------------------------------------------------------------+
//| 添加POI区域（带滑动窗口机制）                                    |
//+------------------------------------------------------------------+
void AddPOIZone(int bar, double top, double bottom, bool is_bullish, int type)
{
    // 检查指定类型是否达到最大数量限制
    int current_type_count = CountPOIZonesByType(type);
    int max_count = (type == 0) ? MaxFVGZones : MaxOBZones; // 0=FVG, 1=OB
    
    if(current_type_count >= max_count) {
        RemoveOldestPOIZoneByType(type);
    }
    
    // 确保不会超出数组边界
    if(poi_count >= ArraySize(poi_zones)) {
        Print("警告: POI区域数组已满，无法添加新区域");
        return;
    }
    
    poi_zones[poi_count].start_bar = bar;
    poi_zones[poi_count].top_price = top;
    poi_zones[poi_count].bottom_price = bottom;
    poi_zones[poi_count].is_bullish = is_bullish;
    poi_zones[poi_count].is_mitigated = false;
    poi_zones[poi_count].poi_type = type;
    poi_zones[poi_count].zone_id = "POI_" + IntegerToString(bar) + "_" + IntegerToString(type);
    poi_zones[poi_count].is_drawn = false;
    poi_zones[poi_count].trigger_count = 0;
    
    // 初始化OB生命周期字段
    if(type == 1 && EnableOBLifecycle) { // 仅对Order Block启用生命周期
        poi_zones[poi_count].touch_count = 0;
        poi_zones[poi_count].status = 0;           // 0=Fresh (全新)
        poi_zones[poi_count].last_touch_bar = -1;
        poi_zones[poi_count].first_break_bar = -1;
        poi_zones[poi_count].break_momentum = 0.0;
    } else {
        // FVG或未启用生命周期时的默认值
        poi_zones[poi_count].touch_count = 0;
        poi_zones[poi_count].status = -1;          // -1表示不使用生命周期
        poi_zones[poi_count].last_touch_bar = -1;
        poi_zones[poi_count].first_break_bar = -1;
        poi_zones[poi_count].break_momentum = 0.0;
    }

    // 初始化OB/FVG重叠与质量评分字段（FVG保留默认值，不参与评分）
    poi_zones[poi_count].has_fvg_overlap = false;
    poi_zones[poi_count].overlap_fvg_bar = -1;
    poi_zones[poi_count].overlap_ratio   = 0.0;
    poi_zones[poi_count].quality_score   = 0.0;
    poi_zones[poi_count].quality_grade   = "D";

    // string type_name = (type == 0) ? "FVG" : "OB";
    // Print("SMC: 添加新的", type_name, "区域 at bar ", bar, " 时间: ", TimeToString(Time[bar]), 
    //       " 当前总数: ", poi_count + 1, "/", MaxPOIZones * 2);
    
    poi_count++;
    g_data_version++; // 新增POI区域，版本递增
}

//+------------------------------------------------------------------+
//| 删除最旧的指定类型结构区域（滑动窗口机制）                       |
//| V1.62: 按 start_bar 最大（时间最旧）删除，而非数组顺序           |
//|        确保 Max=1 时保留最新发现的，Max=N 时保留最近N个           |
//+------------------------------------------------------------------+
void RemoveOldestStructureZone(int target_type)
{
    if(structure_count <= 0) return;
    
    // 查找 start_bar 最大的（时间最旧的）指定类型区域
    // MT4: bar index 越大 = 越旧（更靠图表左侧）
    int oldest_index = -1;
    int max_start_bar = -1;
    for(int i = 0; i < structure_count; i++) {
        if(structure_zones[i].structure_type == target_type &&
           structure_zones[i].start_bar > max_start_bar) {
            max_start_bar = structure_zones[i].start_bar;
            oldest_index = i;
        }
    }
    
    if(oldest_index == -1) return; // 没有找到指定类型的区域
    
    // 删除最旧区域对应的图形对象
    string type_prefix = (target_type == 0) ? "BOS" : "CHOCH";
    string direction_suffix = structure_zones[oldest_index].is_bullish ? "_up" : "_down";
    string obj_name = "SMC_Struct_" + type_prefix + "_" + IntegerToString(structure_zones[oldest_index].start_bar) + direction_suffix;
    string label_name = "SMC_StructLabel_" + type_prefix + "_" + IntegerToString(structure_zones[oldest_index].start_bar) + direction_suffix;
    
    ObjectDelete(obj_name);
    ObjectDelete(label_name);
    
    // Print("SMC: 删除最旧的", type_prefix, direction_suffix, "区域 at bar ", structure_zones[oldest_index].start_bar, " 时间: ", TimeToString(Time[structure_zones[oldest_index].start_bar]));
    
    // 将数组元素左移（删除指定索引的元素）
    for(int i = oldest_index; i < structure_count - 1; i++) {
        structure_zones[i] = structure_zones[i + 1];
    }
    
    structure_count--;
    g_data_version++; // 删除旧结构区，版本递增
}

//+------------------------------------------------------------------+
//| 计算指定类型结构区域的数量                                       |
//+------------------------------------------------------------------+
int CountStructureZones(int structure_type)
{
    int count = 0;
    for(int i = 0; i < structure_count; i++) {
        if(structure_zones[i].structure_type == structure_type) {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| V1.62：后置裁剪，确保只保留每种类型最新的N个                     |
//| 在BOS/CHOCH检测循环结束后调用，删除超出限制的旧对象              |
//+------------------------------------------------------------------+
void TrimStructureZonesToNewest()
{
    for(int t = 0; t <= 1; t++) { // 0=BOS, 1=CHOCH
        int max_count = (t == 0) ? MaxBOSZones : MaxCHOCHZones;
        while(CountStructureZones(t) > max_count)
            RemoveOldestStructureZone(t);
    }
}

//+------------------------------------------------------------------+
//| 添加结构区域（带滑动窗口机制）                                   |
//+------------------------------------------------------------------+
void AddStructureZone(int bar, double break_price, bool is_bullish, int structure_type, int swing_bar)
{
    // 检查指定类型是否达到最大数量限制
    int current_type_count = CountStructureZones(structure_type);
    int max_count = (structure_type == 0) ? MaxBOSZones : MaxCHOCHZones;
    
    if(current_type_count >= max_count) {
        RemoveOldestStructureZone(structure_type);
    }
    
    // 确保不会超出数组边界
    if(structure_count >= ArraySize(structure_zones)) {
        Print("警告: 结构区域数组已满，无法添加新区域");
        return;
    }
    
    // 对于结构突破，我们只需要标记被突破的价格水平，top和bottom是同一个价格
    double top_price = break_price;
    double bottom_price = break_price;
    
    structure_zones[structure_count].start_bar = bar;
    structure_zones[structure_count].swing_bar = swing_bar;
    structure_zones[structure_count].top_price = top_price;
    structure_zones[structure_count].bottom_price = bottom_price;
    structure_zones[structure_count].is_bullish = is_bullish;
    structure_zones[structure_count].is_broken = false;
    structure_zones[structure_count].structure_type = structure_type;
    
    string direction_suffix = is_bullish ? "_up" : "_down";
    structure_zones[structure_count].zone_id = "STRUCT_" + IntegerToString(bar) + "_" + IntegerToString(structure_type) + direction_suffix;
    structure_zones[structure_count].is_drawn = false;
    
    string type_name = (structure_type == 0) ? "BOS" : "CHoCH";
    string direction_name = is_bullish ? "向上" : "向下";
    
    // Print("SMC: 添加新的", type_name, direction_name, "区域 at bar ", bar, " 时间: ", TimeToString(Time[bar]), 
    //       " 价格范围: ", DoubleToString(bottom_price, Digits), "-", DoubleToString(top_price, Digits),
    //       " 当前", type_name, "总数: ", current_type_count + 1, "/", max_count);
    
    structure_count++;
    g_data_version++; // 新增结构区，版本递增
    
    // 立即触发图表重绘
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 更新POI状态                                                      |
//+------------------------------------------------------------------+
void UpdatePOIStatus(int current_bar, const double &high[], const double &low[], const double &close[])
{
    for(int i = 0; i < poi_count; i++) {
        // 边界检查
        if(current_bar < 0 || current_bar >= ArraySize(high)) continue;
        
        if(poi_zones[i].poi_type == 0) { // FVG - 保持原有逻辑
            ProcessFVGStatus(i, current_bar, high, low, close);
        } else if(poi_zones[i].poi_type == 1 && EnableOBLifecycle) { // Order Block - 新的生命周期逻辑
            ProcessOBLifecycle(i, current_bar, high, low, close);
        } else if(poi_zones[i].poi_type == 1) { // Order Block - 传统逻辑（向后兼容）
            ProcessOBTraditional(i, current_bar, high, low, close);
        }
    }
}

//+------------------------------------------------------------------+
//| 处理FVG状态（保持原有逻辑）                                       |
//+------------------------------------------------------------------+
void ProcessFVGStatus(int index, int current_bar, const double &high[], const double &low[], const double &close[])
{
    if(poi_zones[index].is_mitigated) return;
        
        bool is_mitigated = false;
        string mitigation_reason = "";
        
    if(poi_zones[index].is_bullish) {
                // 看涨FVG：只有价格跌破底部边界才算被完全触及
        if(close[current_bar] < poi_zones[index].bottom_price || 
           low[current_bar] < poi_zones[index].bottom_price) {
                    is_mitigated = true;
                    mitigation_reason = "完全跌破底部边界";
                }
            } else {
                // 看跌FVG：只有价格突破顶部边界才算被完全触及
        if(close[current_bar] > poi_zones[index].top_price || 
           high[current_bar] > poi_zones[index].top_price) {
                    is_mitigated = true;
                    mitigation_reason = "完全突破顶部边界";
            }
        }
        
        if(is_mitigated) {
        poi_zones[index].is_mitigated = true;
        g_data_version++;
        
        string direction = poi_zones[index].is_bullish ? "看涨" : "看跌";
            
            if(EnableAlerts && AlertOnPOIEntry) {
                bool cooled = (TimeCurrent() - g_last_signal_time) >= (CooldownBars * PeriodSeconds());
            bool zone_available = (poi_zones[index].trigger_count < MaxTriggersPerZone);
                if(cooled && zone_available) {
                Alert("SMC: ", direction, " FVG 被完全触及 at ", Symbol(), " - ", mitigation_reason);
                    g_last_signal_time = TimeCurrent();
                poi_zones[index].trigger_count++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 处理OB传统状态（向后兼容）                                        |
//+------------------------------------------------------------------+
void ProcessOBTraditional(int index, int current_bar, const double &high[], const double &low[], const double &close[])
{
    if(poi_zones[index].is_mitigated) return;
    
    if(low[current_bar] <= poi_zones[index].top_price && 
       high[current_bar] >= poi_zones[index].bottom_price) {
        poi_zones[index].is_mitigated = true;
        g_data_version++;
        
        if(EnableOBDebug) {
            string direction = poi_zones[index].is_bullish ? "看涨" : "看跌";
            Print("SMC OB传统触及: ", direction, "OB区域被触及 at bar ", current_bar, 
                  " 时间: ", TimeToString(Time[current_bar]));
        }
    }
}

//+------------------------------------------------------------------+
//| 处理OB生命周期状态机（核心功能）                                  |
//+------------------------------------------------------------------+
void ProcessOBLifecycle(int index, int current_bar, const double &high[], const double &low[], const double &close[])
{
    if(poi_zones[index].status == 4) return; // 已失效，跳过
    
    bool price_in_zone = (low[current_bar] <= poi_zones[index].top_price && 
                         high[current_bar] >= poi_zones[index].bottom_price);
    
    bool bullish_break = false, bearish_break = false;
    double momentum = 0.0;
    
    // 计算突破情况和动能
    if(poi_zones[index].is_bullish) {
        // 多头OB：检查是否收盘突破上方或下方
        if(close[current_bar] > poi_zones[index].top_price) {
            bullish_break = true;
            momentum = CalculateBarMomentum(current_bar, high, low, close);
        } else if(close[current_bar] < poi_zones[index].bottom_price) {
            bearish_break = true;
            momentum = CalculateBarMomentum(current_bar, high, low, close);
        }
    } else {
        // 空头OB：检查是否收盘突破上方或下方
        if(close[current_bar] < poi_zones[index].bottom_price) {
            bearish_break = true;
            momentum = CalculateBarMomentum(current_bar, high, low, close);
        } else if(close[current_bar] > poi_zones[index].top_price) {
            bullish_break = true;
            momentum = CalculateBarMomentum(current_bar, high, low, close);
        }
    }
    
    // 状态机逻辑
    switch(poi_zones[index].status) {
        case 0: // Fresh -> Tested 或 (未触及即被击穿) -> Broken_Once
            if(price_in_zone && IsValidTouch(index, current_bar)) {
                poi_zones[index].status = 1;
                poi_zones[index].touch_count = 1;
                poi_zones[index].last_touch_bar = current_bar;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "首次触及", "Fresh -> Tested");
            } else if((poi_zones[index].is_bullish && bearish_break) ||
                      (!poi_zones[index].is_bullish && bullish_break)) {
                // 未登记任何有效触及即被反向收盘击穿：直接进入观察状态
                poi_zones[index].status = 3;
                poi_zones[index].first_break_bar = current_bar;
                poi_zones[index].break_momentum = momentum;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "未触及即被击穿", "Fresh -> Broken_Once");
            }
            break;
            
        case 1: // Tested -> Weakened 或 -> Broken_Once
        case 2: // Weakened -> Broken_Once
            if(price_in_zone && IsValidTouch(index, current_bar)) {
                poi_zones[index].status = 2;
                poi_zones[index].touch_count++;
                poi_zones[index].last_touch_bar = current_bar;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "再次触及", "-> Weakened");
            } else if((poi_zones[index].is_bullish && bearish_break) || (!poi_zones[index].is_bullish && bullish_break)) {
                poi_zones[index].status = 3;
                poi_zones[index].first_break_bar = current_bar;
                poi_zones[index].break_momentum = momentum;
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "首次突破", "-> Broken_Once");
            }
            break;
            
        case 3: // Broken_Once -> Invalid 或 -> Weakened (假突破复活)
            // 失效必须用"反向破坏方向"确认：多头看向下破底，空头看向上破顶
            if((poi_zones[index].is_bullish && bearish_break) || (!poi_zones[index].is_bullish && bullish_break)) {
                // 双重确认失效
                bool has_momentum = !RequireMomentumOnBreak || momentum >= BreakMomentumATR;
                if(has_momentum) {
                    poi_zones[index].status = 4; // Invalid
                    g_data_version++;
                    LogOBLifecycleEvent(index, current_bar, "确认失效", "-> Invalid");
                }
            } else if(price_in_zone && close[current_bar] > poi_zones[index].bottom_price && 
                     close[current_bar] < poi_zones[index].top_price) {
                // 假突破，价格重新回到区域内
                poi_zones[index].status = 2; // Weakened
                g_data_version++;
                LogOBLifecycleEvent(index, current_bar, "假突破复活", "-> Weakened");
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| 检查是否为有效触及（冷却期逻辑）                                  |
//+------------------------------------------------------------------+
bool IsValidTouch(int index, int current_bar)
{
    if(poi_zones[index].last_touch_bar < 0) return true; // 首次触及
    return (current_bar - poi_zones[index].last_touch_bar) >= OBCooldownBars;
}

//+------------------------------------------------------------------+
//| 计算K线动能强度（实体/ATR比值）                                   |
//+------------------------------------------------------------------+
double CalculateBarMomentum(int bar, const double &high[], const double &low[], const double &close[])
{
    if(bar < 0 || bar >= ArraySize(high)) return 0.0;
    
    double body_size = MathAbs(close[bar] - Open[bar]);
    double atr_value = iATR(Symbol(), Period(), AtrPeriod, bar);
    
    if(atr_value <= 0) return 0.0;
    return body_size / atr_value;
}

//+------------------------------------------------------------------+
//| 记录OB生命周期事件日志                                            |
//+------------------------------------------------------------------+
void LogOBLifecycleEvent(int index, int current_bar, string event_type, string transition)
{
    if(!ShowOBLifecycleInfo) return;
    
    string direction = poi_zones[index].is_bullish ? "看涨" : "看跌";
    string status_names[] = {"Fresh", "Tested", "Weakened", "Broken_Once", "Invalid"};
    string current_status = (poi_zones[index].status >= 0 && poi_zones[index].status <= 4) ? 
                           status_names[poi_zones[index].status] : "Unknown";
    
    // Print("SMC OB生命周期: ", direction, "OB ", event_type, " at bar ", current_bar, 
    //       " | ", transition, " | 状态: ", current_status, 
    //       " | 触及次数: ", poi_zones[index].touch_count,
    //       " | 价格: ", DoubleToString(poi_zones[index].bottom_price, Digits), 
    //       "-", DoubleToString(poi_zones[index].top_price, Digits));
}

//+------------------------------------------------------------------+
//| 检查OB是否应该跳过显示                                            |
//+------------------------------------------------------------------+
bool ShouldSkipOB(int index, string &skip_reason)
{
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑
        if(poi_zones[index].status == 4 && RemoveInvalidOB) { // Invalid且设置移除
            skip_reason = "失效已移除";
            return true;
        }
        if(HideLowQualityOB && poi_zones[index].quality_score < MinVisibleOBQualityScore) {
            skip_reason = "低质量隐藏";
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

//+------------------------------------------------------------------+
//| 获取OB显示颜色                                                    |
//+------------------------------------------------------------------+
color GetOBDisplayColor(int index)
{
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑
        switch(poi_zones[index].status) {
            case 0: // Fresh：原色
                return poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color;

            case 1: // Tested：略暗
                return poi_zones[index].is_bullish ? clrSeaGreen : clrIndianRed;

            case 2: // Weakened：更暗
                return poi_zones[index].is_bullish ? clrDarkGreen : clrSaddleBrown;

            case 3: // Broken_Once：警戒色
                return clrOrange;

            case 4: // Invalid：灰色
                return Mitigated_POI_Color;

            default:
                return poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color;
        }
    } else {
        // 传统逻辑（向后兼容）
        return poi_zones[index].is_mitigated ? Mitigated_POI_Color :
               (poi_zones[index].is_bullish ? Bullish_OB_Color : Bearish_OB_Color);
    }
}

//+------------------------------------------------------------------+
//| 获取OB显示标签                                                    |
//+------------------------------------------------------------------+
string GetOBDisplayLabel(int index)
{
    string direction = poi_zones[index].is_bullish ? "Bullish" : "Bearish";
    
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        // 使用生命周期逻辑：方向 + OB[+FVG] + 状态 + [等级]
        string fvg_tag   = poi_zones[index].has_fvg_overlap ? "+FVG" : "";
        string grade_tag = ShowOBQualityGrade ? (" [" + poi_zones[index].quality_grade + "]") : "";
        string state_tag = "";
        switch(poi_zones[index].status) {
            case 0: state_tag = "";         break; // Fresh
            case 1: state_tag = " Tested";  break;
            case 2: state_tag = " Weak";    break;
            case 3: state_tag = " Watch";   break;
            case 4: state_tag = " Invalid"; break;
            default: state_tag = "";        break;
        }
        return direction + " OB" + fvg_tag + state_tag + grade_tag;
    } else {
        // 传统逻辑（向后兼容）
        string label = direction + " OB";
        if(poi_zones[index].is_mitigated) label += " (Mitigated)";
        return label;
    }
}

//+------------------------------------------------------------------+
//| 获取OB等级名称                                                    |
//+------------------------------------------------------------------+
string GetOBLevelName(int index)
{
    if(EnableOBLifecycle && poi_zones[index].status >= 0) {
        switch(poi_zones[index].status) {
            case 0: return "High";
            case 1:
            case 2:
            case 3: return "Mid";
            case 4: return "Invalid";
            default: return "Unknown";
        }
    } else {
        return poi_zones[index].is_mitigated ? "Mitigated" : "Active";
    }
}

//+------------------------------------------------------------------+
//| 计算OB与指定FVG的价格重叠比例(以OB宽度为分母)                      |
//+------------------------------------------------------------------+
double GetOBFVGOverlapRatio(int ob_index, int fvg_index)
{
    double ob_top     = poi_zones[ob_index].top_price;
    double ob_bottom  = poi_zones[ob_index].bottom_price;
    double fvg_top    = poi_zones[fvg_index].top_price;
    double fvg_bottom = poi_zones[fvg_index].bottom_price;

    double overlap_low  = MathMax(ob_bottom, fvg_bottom);
    double overlap_high = MathMin(ob_top, fvg_top);
    if(overlap_high <= overlap_low) return 0.0;

    double ob_width = ob_top - ob_bottom;
    if(ob_width <= 0.0) return 0.0;
    return (overlap_high - overlap_low) / ob_width;
}

//+------------------------------------------------------------------+
//| 根据分数返回等级标签                                              |
//+------------------------------------------------------------------+
string GetOBGradeLabel(double score)
{
    if(score >= 0.80) return "A";
    if(score >= 0.60) return "B";
    if(score >= 0.40) return "C";
    if(score >  0.00) return "D";
    return "X";
}

//+------------------------------------------------------------------+
//| 计算单个OB的质量分(基础分按状态 + 重叠/趋势加分)                   |
//+------------------------------------------------------------------+
double CalculateOBQualityScore(int ob_index)
{
    double base = 0.0;
    switch(poi_zones[ob_index].status) {
        case 0: base = 0.80; break; // Fresh
        case 1: base = 0.65; break; // Tested
        case 2: base = 0.45; break; // Weakened
        case 3: base = 0.20; break; // Broken_Once
        case 4: base = 0.00; break; // Invalid
        default: base = 0.00; break;
    }

    double bonus = 0.0;
    // 同向FVG重叠加分
    if(poi_zones[ob_index].has_fvg_overlap) {
        bonus += 0.15;
        if(poi_zones[ob_index].overlap_ratio >= MinOBFVGOverlapRatio) bonus += 0.05;
    }
    // 与当前主趋势方向一致加分 (g_market_trend: 1=上升, -1=下降)
    if((poi_zones[ob_index].is_bullish  && g_market_trend == 1) ||
       (!poi_zones[ob_index].is_bullish && g_market_trend == -1)) {
        bonus += 0.05;
    }

    double score = base + bonus;
    if(score < 0.0) score = 0.0;
    if(score > 1.0) score = 1.0;
    return score;
}

//+------------------------------------------------------------------+
//| 刷新所有OB的OB/FVG重叠与质量评分(全量扫描)                         |
//+------------------------------------------------------------------+
void RefreshOBFVGConfluence()
{
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type != 1) continue; // 仅OB
        if(poi_zones[i].status < 0) continue;     // 未启用生命周期的OB跳过

        // 重置重叠信息
        poi_zones[i].has_fvg_overlap = false;
        poi_zones[i].overlap_fvg_bar = -1;
        poi_zones[i].overlap_ratio   = 0.0;

        // 扫描同向、未完全触及的FVG，取最大重叠比例
        if(EnableOBFVGConfluence) {
            for(int j = 0; j < poi_count; j++) {
                if(poi_zones[j].poi_type != 0) continue;                         // 仅FVG
                if(poi_zones[j].is_bullish != poi_zones[i].is_bullish) continue; // 同向
                if(poi_zones[j].is_mitigated) continue;                          // 已触及FVG不加分
                double ratio = GetOBFVGOverlapRatio(i, j);
                if(ratio > poi_zones[i].overlap_ratio) {
                    poi_zones[i].overlap_ratio   = ratio;
                    poi_zones[i].overlap_fvg_bar = poi_zones[j].start_bar;
                    poi_zones[i].has_fvg_overlap = true;
                }
            }
        }

        // 计算质量分与等级
        poi_zones[i].quality_score = CalculateOBQualityScore(i);
        poi_zones[i].quality_grade = GetOBGradeLabel(poi_zones[i].quality_score);
    }
}

//+------------------------------------------------------------------+
//| 把每个OB的质量分写入OB_Quality缓冲区(锚点K线;同锚点取最高分)       |
//+------------------------------------------------------------------+
void WriteOBQualityBuffer()
{
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type != 1) continue;
        if(poi_zones[i].status < 0) continue;
        int bar = poi_zones[i].start_bar;
        if(bar < 0 || bar >= ArraySize(OB_Quality)) continue;
        double existing = OB_Quality[bar];
        if(existing == EMPTY_VALUE || poi_zones[i].quality_score > existing) {
            OB_Quality[bar] = poi_zones[i].quality_score;
        }
    }
}

//+------------------------------------------------------------------+
//| 更新缓冲区                                                       |
//+------------------------------------------------------------------+
void UpdateBuffers(int current_bar)
{
    // 边界检查，防止数组越界
    if(current_bar < 0 || current_bar >= ArraySize(BOS_Top)) {
        Print("警告: UpdateBuffers数组越界，current_bar=", current_bar, " ArraySize=", ArraySize(BOS_Top));
        return;
    }
    
    // 初始化当前K线的所有缓冲区
    BOS_Top[current_bar] = EMPTY_VALUE;
    BOS_Bottom[current_bar] = EMPTY_VALUE;
    CHOCH_Top[current_bar] = EMPTY_VALUE;
    CHOCH_Bottom[current_bar] = EMPTY_VALUE;
    FVG_Top[current_bar] = EMPTY_VALUE;
    FVG_Bottom[current_bar] = EMPTY_VALUE;
    OB_Top[current_bar] = EMPTY_VALUE;
    OB_Bottom[current_bar] = EMPTY_VALUE;
    OB_Quality[current_bar] = EMPTY_VALUE;

    // 更新结构区域缓冲区 (BOS/CHOCH) - 与K线同步显示实际数值
    for(int i = 0; i < structure_count; i++) {
        // 检查当前K线是否有结构区域形成
        if(structure_zones[i].start_bar == current_bar) {
            if(structure_zones[i].structure_type == 0) { // BOS
                BOS_Top[current_bar] = structure_zones[i].top_price;
                BOS_Bottom[current_bar] = structure_zones[i].bottom_price;
            } else { // CHoCH
                CHOCH_Top[current_bar] = structure_zones[i].top_price;
                CHOCH_Bottom[current_bar] = structure_zones[i].bottom_price;
            }
        }
    }
    
    // 更新POI区域缓冲区 (FVG/OB) - 分开处理不同类型
    
    // 1. 处理FVG缓冲区 - FVG标记在实际形成的K线上
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type == 0 && poi_zones[i].start_bar == current_bar) { // FVG
            FVG_Top[current_bar] = poi_zones[i].top_price;
            FVG_Bottom[current_bar] = poi_zones[i].bottom_price;
            // Print("SMC: 设置FVG缓冲区 at bar ", current_bar, " Top=", 
            //       DoubleToString(poi_zones[i].top_price, Digits), " Bottom=", DoubleToString(poi_zones[i].bottom_price, Digits));
        }
    }
    
    // 2. 处理OB缓冲区 - OB标记在实际形成的K线上
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type == 1 && poi_zones[i].start_bar == current_bar) { // Order Block
            OB_Top[current_bar] = poi_zones[i].top_price;
            OB_Bottom[current_bar] = poi_zones[i].bottom_price;
            // Print("SMC: 设置OB缓冲区 at bar ", current_bar, " Top=", DoubleToString(poi_zones[i].top_price, Digits), 
            //       " Bottom=", DoubleToString(poi_zones[i].bottom_price, Digits));
        }
    }
}

//+------------------------------------------------------------------+
//| 绘制图形对象                                                     |
//+------------------------------------------------------------------+
void DrawGraphicalObjects()
{
    static datetime last_update = 0;
    static bool first_draw = true;
    static int last_structure_count = 0;
    static int last_poi_count = 0;
    static int last_draw_version = -1;
    
    datetime current_time = TimeCurrent();
    bool force_refresh = false;
    
    // 数据数量变化触发强制刷新
    if(structure_count != last_structure_count || poi_count != last_poi_count) {
        force_refresh = true;
        last_structure_count = structure_count;
        last_poi_count = poi_count;
    }
    
    // 版本变化触发强制刷新
    if(g_data_version != last_draw_version) {
        force_refresh = true;
    }
    
    // 收盘后5秒内：强制刷新（仅在实盘/前向环境启用，避免测试器中恒为真导致持续强制刷新）
    bool within_5s_after_close = false;
    if(!IsTesting() && !IsOptimization()) {
        if(Bars > 0) {
            datetime current_bar_time = Time[0];
            if(MathAbs(TimeCurrent() - current_bar_time) <= 2) within_5s_after_close = true;
        }
        if(MathAbs(TimeCurrent() - g_last_full_recalc_time) <= 2) within_5s_after_close = true;
    }
    // 先关闭，如果出现不准确的情况再打开
    // if(within_5s_after_close) force_refresh = true;
    
    // 限制重绘频率，但允许强制刷新
    if(current_time - last_update < 1 && !first_draw && !force_refresh) return;
    
    // 首次绘制或强制刷新时清除所有旧的SMC图形对象
    if(first_draw || force_refresh) {
        for(int j = ObjectsTotal(0, -1, -1) - 1; j >= 0; j--) {
            string obj_name = ObjectName(0, j, false, -1);
            if(StringFind(obj_name, "SMC_") == 0) {
                ObjectDelete(obj_name);
            }
        }
        
        // 重置所有绘制标记，强制重绘所有对象
        for(int k = 0; k < structure_count; k++) {
            structure_zones[k].is_drawn = false;
        }
        for(int k = 0; k < poi_count; k++) {
            poi_zones[k].is_drawn = false;
        }
        
        if(first_draw) {
            Print("SMC: 首次绘制，清除所有旧图形对象");
            first_draw = false;
        } else {
            // Print("SMC: 强制刷新，重绘所有图形对象 (结构:", structure_count, ", POI:", poi_count, ")");
        }
    }
    
    // 绘制BOS结构区域（只绘制未绘制的）
    if(ShowBOS) {
        for(int i = 0; i < structure_count; i++) {
            if(structure_zones[i].structure_type == 0 && !structure_zones[i].is_drawn) { // BOS
                DrawStructureZone(i, "BOS", BOS_Color);
                structure_zones[i].is_drawn = true;
            }
        }
    }
    
    // 绘制CHOCH结构区域（只绘制未绘制的）
    if(ShowCHOCH) {
        for(int i = 0; i < structure_count; i++) {
            if(structure_zones[i].structure_type == 1 && !structure_zones[i].is_drawn) { // CHOCH
                DrawStructureZone(i, "CHOCH", CHOCH_Color);
                structure_zones[i].is_drawn = true;
            }
        }
    }
    
    // 绘制FVG区域（只绘制未绘制的）
    if(ShowFVG) {
        int fvg_drawn = 0, fvg_skipped = 0;
        for(int i = 0; i < poi_count; i++) {
            if(poi_zones[i].poi_type == 0 && !poi_zones[i].is_drawn) { // FVG且未绘制
                // 检查是否应该跳过已触及的区域
                if(!ShowMitigatedPOI && poi_zones[i].is_mitigated) {
                    fvg_skipped++;
                    poi_zones[i].is_drawn = true; // 标记为已处理，避免重复检查
                    continue;
                }
                
                color zone_color = poi_zones[i].is_mitigated ? Mitigated_POI_Color :
                                  (poi_zones[i].is_bullish ? Bullish_FVG_Color : Bearish_FVG_Color);
                string label_text = poi_zones[i].is_bullish ? "Bullish FVG" : "Bearish FVG";
                if(poi_zones[i].is_mitigated) label_text += " (Mitigated)";
                
                DrawPOIZone(i, "FVG", zone_color, label_text);
                poi_zones[i].is_drawn = true;
                fvg_drawn++;
            }
        }
    }
    
    // 绘制Order Block区域（支持生命周期显示）
    if(ShowOrderBlocks) {
        int ob_drawn = 0, ob_skipped = 0;
        int ob_fresh = 0, ob_tested = 0, ob_weakened = 0, ob_broken = 0, ob_invalid = 0;
        
        // 统计OB区域生命周期状态
        for(int i = 0; i < poi_count; i++) {
            if(poi_zones[i].poi_type == 1) { // Order Block
                if(EnableOBLifecycle && poi_zones[i].status >= 0) {
                    switch(poi_zones[i].status) {
                        case 0: ob_fresh++; break;
                        case 1: ob_tested++; break;
                        case 2: ob_weakened++; break;
                        case 3: ob_broken++; break;
                        case 4: ob_invalid++; break;
                    }
                }
            }
        }
        
        for(int i = 0; i < poi_count; i++) {
            if(poi_zones[i].poi_type == 1 && (!poi_zones[i].is_drawn || ForceOBRedraw)) { // Order Block且未绘制或强制重绘
                
                // 检查是否应该跳过
                string skip_reason = "";
                if(ShouldSkipOB(i, skip_reason)) {
                    ob_skipped++;
                    poi_zones[i].is_drawn = true;
                    
                    if(EnableOBDebug) {
                        string direction = poi_zones[i].is_bullish ? "看涨" : "看跌";
                        Print("SMC OB调试: 跳过", skip_reason, direction, "OB区域 at bar ", poi_zones[i].start_bar);
                    }
                    continue;
                }
                
                // 获取显示信息
                color zone_color = GetOBDisplayColor(i);
                string zone_label = GetOBDisplayLabel(i);
                string level_name = GetOBLevelName(i);
                
                // 绘制OB区域
                DrawPOIZone(i, "OB", zone_color, zone_label);
                poi_zones[i].is_drawn = true;
                ob_drawn++;
                
                if(EnableOBDebug) {
                    string direction = poi_zones[i].is_bullish ? "看涨" : "看跌";
                    Print("SMC OB调试: 绘制", direction, "OB区域 at bar ", poi_zones[i].start_bar, 
                          " 等级: ", level_name, " 颜色: ", IntegerToString(zone_color),
                          " 价格: ", DoubleToString(poi_zones[i].bottom_price, Digits), "-", DoubleToString(poi_zones[i].top_price, Digits));
                }
            }
        }
        
        // 显示OB生命周期状态信息
        if(EnableOBDebug && ShowOBStatusInfo && EnableOBLifecycle && (ob_drawn > 0 || ob_skipped > 0)) {
            Print("SMC OB生命周期状态: Fresh=", ob_fresh, " Tested=", ob_tested, " Weakened=", ob_weakened, 
                  " Broken=", ob_broken, " Invalid=", ob_invalid, " 本次绘制=", ob_drawn, " 跳过=", ob_skipped);
        }
    }
    
    // 绘制摆点连线
    if(ShowSwingConnections) {
        DrawSwingConnections();
    }

    // V1.53新增：绘制趋势指示器
    DrawTrendIndicator();

    last_update = current_time;
    last_draw_version = g_data_version;
    g_last_drawn_version = g_data_version;
    
    // 统计有效区域数量
    int active_fvg = 0, active_ob = 0, mitigated_fvg = 0, mitigated_ob = 0;
    for(int i = 0; i < poi_count; i++) {
        if(poi_zones[i].poi_type == 0) { // FVG
            if(poi_zones[i].is_mitigated) mitigated_fvg++;
            else active_fvg++;
        } else { // OB
            if(poi_zones[i].is_mitigated) mitigated_ob++;
            else active_ob++;
        }
    }
    
    // 统计BOS和CHoCH数量
    int bos_count = CountStructureZones(0);
    int choch_count = CountStructureZones(1);
    
    // 更新调试信息
    string debug_info = "SMC: BOS=" + IntegerToString(bos_count) + "/" + IntegerToString(MaxBOSZones) +
                       " | CHoCH=" + IntegerToString(choch_count) + "/" + IntegerToString(MaxCHOCHZones) +
                       " | FVG=" + IntegerToString(active_fvg) + "/" + IntegerToString(MaxFVGZones) +
                       " | OB=" + IntegerToString(active_ob) + "/" + IntegerToString(MaxOBZones) +
                       " | 已触及(FVG/OB)=" + IntegerToString(mitigated_fvg) + "/" + IntegerToString(mitigated_ob) +
                       " | Swing=" + IntegerToString(swing_count) +
                       " | 强制刷新=" + (force_refresh ? "是" : "否") +
                       " | ver=" + IntegerToString(g_data_version);
    Comment(debug_info);
    
    // 可选绘制Premium/Discount参考线
    if(ShowPremiumDiscountLines && UsePremiumDiscount) {
        int window = MathMax(StructureLookback * OuterLookbackFactor * 4, 20);
        int hh_idx = iHighest(NULL,0,MODE_HIGH,window,0);
        int ll_idx = iLowest(NULL,0,MODE_LOW,window,0);
        double outer_hi = iHigh(NULL,0,hh_idx);
        double outer_lo = iLow(NULL,0,ll_idx);
        double mid50 = (outer_hi + outer_lo) * 0.5;
        double disc62 = outer_lo + 0.62*(outer_hi - outer_lo);
        double prem38 = outer_hi - 0.62*(outer_hi - outer_lo);

        string o50 = "SMC_PD_50";
        string o62 = "SMC_PD_62";
        string o38 = "SMC_PD_38";
        datetime t0 = Time[Bars-1];
        datetime t1 = TimeCurrent() + PeriodSeconds()*100;
        // 50%
        if(ObjectFind(0,o50) < 0) ObjectCreate(0,o50,OBJ_TREND,0,t0,mid50,t1,mid50);
        ObjectSetInteger(0,o50,OBJPROP_COLOR,clrSilver);
        ObjectSetInteger(0,o50,OBJPROP_STYLE,STYLE_DOT);
        // 62%
        if(ObjectFind(0,o62) < 0) ObjectCreate(0,o62,OBJ_TREND,0,t0,disc62,t1,disc62);
        ObjectSetInteger(0,o62,OBJPROP_COLOR,clrDarkGreen);
        ObjectSetInteger(0,o62,OBJPROP_STYLE,STYLE_DOT);
        // 38%（上侧对称用于空头优先）
        if(ObjectFind(0,o38) < 0) ObjectCreate(0,o38,OBJ_TREND,0,t0,prem38,t1,prem38);
        ObjectSetInteger(0,o38,OBJPROP_COLOR,clrFireBrick);
        ObjectSetInteger(0,o38,OBJPROP_STYLE,STYLE_DOT);
    }

    // 确保图表更新
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| 绘制结构区域 (BOS/CHOCH)                                         |
//+------------------------------------------------------------------+
void DrawStructureZone(int zone_index, string type_name, color zone_color)
{
    Structure_Zone zone = structure_zones[zone_index];
    
    // 概念修正：对于结构突破，top_price和bottom_price是相同的，代表被突破的价格水平
    if(zone.start_bar < 0 || zone.start_bar >= Bars) return;
    
    // 添加方向后缀到对象名称
    string direction_suffix = zone.is_bullish ? "_up" : "_down";
    string obj_name = "SMC_Struct_" + type_name + "_" + IntegerToString(zone.start_bar) + direction_suffix;
    
    // --- 修正：射线从被突破的摆点开始向右延伸 ---
    // 起点：被突破的摆点时间（swing_bar），这才是正确的SMC概念
    datetime ray_start_time;
    if(zone.swing_bar >= 0 && zone.swing_bar < Bars) {
        ray_start_time = Time[zone.swing_bar];  // 从被突破的摆点开始
    } else {
        ray_start_time = Time[zone.start_bar];  // 备用：从突破发生点开始
        Print("SMC 警告: ", type_name, " 无效的swing_bar索引 (", zone.swing_bar, ")，射线起点改为突破点");
    }
    // 第二点：位于右侧的未来时间，用于定义射线方向
    datetime ray_dir_time = TimeCurrent() + PeriodSeconds() * 100;
    
    // 创建趋势线并设为向右射线
    if(ObjectCreate(0, obj_name, OBJ_TREND, 0, ray_start_time, zone.top_price, ray_dir_time, zone.top_price))
    {
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
        // 尽量兼容：开启右侧射线
        ObjectSetInteger(0, obj_name, OBJPROP_RAY, true);
        ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);
    }
    
    // 添加标签（也包含方向信息）
    string label_name = "SMC_StructLabel_" + type_name + "_" + IntegerToString(zone.start_bar) + direction_suffix;
    
    // 动态计算标签偏移，避免写死
    double atr_val = iATR(NULL, 0, AtrPeriod, zone.start_bar);
    double label_offset = atr_val * 0.2; // 使用ATR的20%作为偏移量
    if(label_offset <= 0) label_offset = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10; // 兜底

    // 向上突破标签在线上方，向下突破在线下方
    double label_price = zone.is_bullish ? zone.top_price + label_offset : zone.top_price - label_offset;
    
    string label_text = type_name + (zone.is_bullish ? "↑" : "↓");
    
    // 标签绘制在被突破的摆点位置（射线起点）
    if(ObjectCreate(0, label_name, OBJ_TEXT, 0, ray_start_time, label_price))
    {
        ObjectSetString(0, label_name, OBJPROP_TEXT, label_text);
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, label_name, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, zone.is_bullish ? ANCHOR_LEFT_LOWER: ANCHOR_LEFT_UPPER);
    }
}

//+------------------------------------------------------------------+
//| 绘制POI区域 (FVG/OB)                                             |
//+------------------------------------------------------------------+
void DrawPOIZone(int zone_index, string type_prefix, color zone_color, string label_text)
{
    POI_Zone zone = poi_zones[zone_index];
    
    if(zone.start_bar < 0 || zone.start_bar >= Bars) return;
    if(zone.top_price <= zone.bottom_price) return;
    
    string obj_name = "SMC_Zone_" + type_prefix + "_" + IntegerToString(zone.start_bar);
    
    // 安全获取起始时间，添加边界检查和有效性验证
    datetime start_time;
    if(zone.start_bar >= 0 && zone.start_bar < ArraySize(Time) && zone.start_bar < Bars) {
        start_time = Time[zone.start_bar];
        // 验证时间有效性
        if(start_time <= 0) {
            // 如果时间无效，使用备用策略：当前时间减去适当的周期
            start_time = TimeCurrent() - PeriodSeconds() * (zone.start_bar + 1);
            Print("SMC 警告: ", type_prefix, " 区域时间无效，使用备用时间策略 bar=", zone.start_bar);
        }
        // 额外验证：确保时间不会超过当前时间太多
        if(start_time > TimeCurrent()) {
            start_time = TimeCurrent() - PeriodSeconds() * MathMax(1, zone.start_bar);
            Print("SMC 警告: ", type_prefix, " 区域时间超前，已调整 bar=", zone.start_bar);
        }
    } else {
        // 边界越界时的备用策略：使用相对时间计算
        int safe_offset = MathMax(1, MathMin(zone.start_bar, 50)); // 限制在合理范围内
        start_time = TimeCurrent() - PeriodSeconds() * safe_offset;
        Print("SMC 警告: ", type_prefix, " 区域bar索引越界 (", zone.start_bar, "/", Bars, ")，使用备用时间偏移=", safe_offset);
    }
    
    datetime end_time = TimeCurrent() + PeriodSeconds() * 100;
    
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
    
    // 添加标签
    string label_name = "SMC_ZoneLabel_" + type_prefix + "_" + IntegerToString(zone.start_bar);
    double label_price = zone.top_price + (zone.top_price - zone.bottom_price) * 0.05;
    
    if(ObjectCreate(0, label_name, OBJ_TEXT, 0, start_time, label_price))
    {
        ObjectSetString(0, label_name, OBJPROP_TEXT, label_text);
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, zone_color);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, label_name, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    }
}

//+------------------------------------------------------------------+
//| 绘制摆点连线 - 两阶段极值点优先算法 (ZigZag v2.0)                 |
//+------------------------------------------------------------------+
void DrawSwingConnections()
{
    // V1.55 优化：清除旧的ZigZag连线和标签，防止重影（特别是当摆点被虚拟点替换时）
    ObjectsDeleteAll(0, "SMC_ZigZag");

    // 创建按时间排序的摆点数组
    struct SwingTimePoint {
        int bar_index;
        double price;
        bool is_high;
        int structure_type; // 0=HH, 1=HL, 2=LH, 3=LL
        datetime time;
    };
    
    SwingTimePoint sorted_swings[];
    int local_swing_count = 0;
    
    // 收集所有摆点并添加时间信息
    for(int i = 0; i < swing_count; i++) {
        if(swing_points[i].structure_type >= 0) { // 只处理已分类的摆点
            ArrayResize(sorted_swings, local_swing_count + 1);
            
            // V1.55 虚拟摆点逻辑 | V1.66: HL/LH时追加虚拟点，HH/LL时替换
            bool is_last = (i == swing_count - 1);
            bool use_replace = (is_last && g_virtual_swing_active && !g_virtual_swing_add_mode);
            bool use_add = (is_last && g_virtual_swing_active && g_virtual_swing_add_mode);
            
            if(use_replace) {
                // HH/LL: 用虚拟点替换最后摆点
                sorted_swings[local_swing_count].bar_index = g_virtual_swing_bar;
                sorted_swings[local_swing_count].price = g_virtual_swing_price;
                sorted_swings[local_swing_count].is_high = g_virtual_swing_is_high;
                sorted_swings[local_swing_count].structure_type = g_virtual_swing_type;
                sorted_swings[local_swing_count].time = (g_virtual_swing_bar >= 0 && g_virtual_swing_bar < Bars)
                    ? Time[g_virtual_swing_bar] : TimeCurrent();
            }
            else {
                // 正常添加或use_add时先添加最后摆点
                sorted_swings[local_swing_count].bar_index = swing_points[i].bar_index;
                sorted_swings[local_swing_count].price = swing_points[i].price;
                sorted_swings[local_swing_count].is_high = swing_points[i].is_high;
                sorted_swings[local_swing_count].structure_type = swing_points[i].structure_type;
                sorted_swings[local_swing_count].time = (swing_points[i].bar_index >= 0 && swing_points[i].bar_index < Bars)
                    ? Time[swing_points[i].bar_index] : TimeCurrent();
            }
            local_swing_count++;
            
            // V1.66: HL/LH时追加虚拟点，使最后一笔连接到未确认极值（如当前K线最低）
            if(use_add) {
                ArrayResize(sorted_swings, local_swing_count + 1);
                sorted_swings[local_swing_count].bar_index = g_virtual_swing_bar;
                sorted_swings[local_swing_count].price = g_virtual_swing_price;
                sorted_swings[local_swing_count].is_high = g_virtual_swing_is_high;
                sorted_swings[local_swing_count].structure_type = g_virtual_swing_type;
                sorted_swings[local_swing_count].time = (g_virtual_swing_bar >= 0 && g_virtual_swing_bar < Bars)
                    ? Time[g_virtual_swing_bar] : TimeCurrent();
                local_swing_count++;
            }
        }
    }
    
    // 如果摆点数量不足，无法绘制连线
    if(local_swing_count < 2) return;
    
    // 按时间排序（从旧到新）
    for(int i = 0; i < local_swing_count - 1; i++) {
        for(int j = i + 1; j < local_swing_count; j++) {
            if(sorted_swings[i].time > sorted_swings[j].time) {
                SwingTimePoint temp = sorted_swings[i];
                sorted_swings[i] = sorted_swings[j];
                sorted_swings[j] = temp;
            }
        }
    }
    
    // ========== 阶段一：筛选合并 - 生成纯净的ZigZag节点 ==========
    SwingTimePoint zigzag_points[];
    int zigzag_count = 0;
    
    // 初始化：添加第一个摆点作为起点
    ArrayResize(zigzag_points, 1);
    zigzag_points[0] = sorted_swings[0];
    zigzag_count = 1;
    
    // 遍历剩余摆点，应用极值点优先逻辑
    for(int i = 1; i < local_swing_count; i++) {
        SwingTimePoint current_swing = sorted_swings[i];
        SwingTimePoint last_zigzag = zigzag_points[zigzag_count - 1];
        
        // 规则1：如果当前点与最后一个ZigZag点类型不同 -> 确认转向，直接添加
        if(current_swing.is_high != last_zigzag.is_high) {
            ArrayResize(zigzag_points, zigzag_count + 1);
            zigzag_points[zigzag_count] = current_swing;
            zigzag_count++;
        }
        // 规则2：如果当前点与最后一个ZigZag点类型相同 -> 比较极值，保留更极端的点
        else {
            bool should_replace = false;
            
            if(current_swing.is_high) {
                // 两个都是高点，比较价格，保留更高的
                if(current_swing.price > last_zigzag.price) {
                    should_replace = true;
                }
            } else {
                // 两个都是低点，比较价格，保留更低的
                if(current_swing.price < last_zigzag.price) {
                    should_replace = true;
                }
            }
            
            // 如果当前点更极端，替换最后一个ZigZag点
            if(should_replace) {
                zigzag_points[zigzag_count - 1] = current_swing;
            }
            // 否则忽略当前点，保持原有的ZigZag点不变
        }
    }
    
    // 如果筛选后的ZigZag节点不足，无法绘制连线
    if(zigzag_count < 2) return;
    
    
    // ========== 阶段二：绘制连接 - 基于纯净的ZigZag节点 ==========
    for(int i = 0; i < zigzag_count - 1; i++) {
        SwingTimePoint current_point = zigzag_points[i];
        SwingTimePoint next_point = zigzag_points[i + 1];
        
        // === 绘制连线 ===
        string line_name = "SMC_ZigZagLine_" + IntegerToString(current_point.bar_index) + "_to_" + IntegerToString(next_point.bar_index);
        
        // 智能颜色和样式选择
        color line_color = SwingConnection_Color;
        int line_style = STYLE_SOLID;
        int line_width = 1;
        
        // 根据连接的摆点类型确定颜色和样式
        bool is_bullish_connection = false;
        bool is_bearish_connection = false;
        bool is_trend_change = false;
        
        // 判断连接类型
        if((current_point.structure_type == 0 || current_point.structure_type == 1) && 
           (next_point.structure_type == 0 || next_point.structure_type == 1)) {
            is_bullish_connection = true; // 上升趋势内的连接
        }
        else if((current_point.structure_type == 2 || current_point.structure_type == 3) && 
                (next_point.structure_type == 2 || next_point.structure_type == 3)) {
            is_bearish_connection = true; // 下降趋势内的连接
        }
        else {
            is_trend_change = true; // 趋势转换连接
        }
        
        // V1.55 虚拟摆点样式覆盖
        if(current_point.structure_type >= 10 || next_point.structure_type >= 10) {
            line_style = VirtualSwingExtension_Style;
            if(next_point.structure_type == 10) line_color = VHH_Color;
            else if(next_point.structure_type == 13) line_color = VLL_Color;
        }
        
        // 设置样式
        if(is_bullish_connection) {
            line_color = BullishSwing_Color;
            line_width = 1;
        }
        else if(is_bearish_connection) {
            line_color = BearishSwing_Color;
            line_width = 1;
        }
        else if(is_trend_change) {
            line_color = SwingConnection_Color;
            line_style = STYLE_DASHDOT;
            line_width = 2;
        }
        
        // 创建趋势线
        if(ObjectCreate(0, line_name, OBJ_TREND, 0, current_point.time, current_point.price, next_point.time, next_point.price)) {
            ObjectSetInteger(0, line_name, OBJPROP_COLOR, line_color);
            ObjectSetInteger(0, line_name, OBJPROP_WIDTH, line_width);
            ObjectSetInteger(0, line_name, OBJPROP_STYLE, line_style);
            ObjectSetInteger(0, line_name, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, line_name, OBJPROP_RAY_LEFT, false);
        }
        
        // 添加摆点标签
        string current_type_text = "";
        switch(current_point.structure_type) {
            case 0: current_type_text = "HH"; break;
            case 1: current_type_text = "HL"; break;
            case 2: current_type_text = "LH"; break;
            case 3: current_type_text = "LL"; break;
            case 10: current_type_text = "VHH"; break; // V1.55
            case 13: current_type_text = "VLL"; break; // V1.55
        }
        
        string label_name = "SMC_ZigZagLabel_" + IntegerToString(current_point.bar_index);
        double label_offset = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 15;
        double label_price = current_point.is_high ? current_point.price + label_offset : current_point.price - label_offset;
        
        if(ObjectCreate(0, label_name, OBJ_TEXT, 0, current_point.time, label_price)) {
            ObjectSetString(0, label_name, OBJPROP_TEXT, current_type_text);
            ObjectSetInteger(0, label_name, OBJPROP_COLOR, line_color);
            ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 9);
            ObjectSetString(0, label_name, OBJPROP_FONT, "Arial Bold");
            ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, current_point.is_high ? ANCHOR_UPPER : ANCHOR_LOWER);
        }
    }
    
    // 为最后一个ZigZag点添加标签
    if(zigzag_count > 0) {
        SwingTimePoint last_point = zigzag_points[zigzag_count - 1];
        string last_type_text = "";
        switch(last_point.structure_type) {
            case 0: last_type_text = "HH"; break;
            case 1: last_type_text = "HL"; break;
            case 2: last_type_text = "LH"; break;
            case 3: last_type_text = "LL"; break;
            case 10: last_type_text = "VHH"; break; // V1.55
            case 13: last_type_text = "VLL"; break; // V1.55
        }
        
        string last_label_name = "SMC_ZigZagLabel_" + IntegerToString(last_point.bar_index);
        double last_label_offset = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 15;
        double last_label_price = last_point.is_high ? last_point.price + last_label_offset : last_point.price - last_label_offset;
        
        if(ObjectCreate(0, last_label_name, OBJ_TEXT, 0, last_point.time, last_label_price)) {
            ObjectSetString(0, last_label_name, OBJPROP_TEXT, last_type_text);
            ObjectSetInteger(0, last_label_name, OBJPROP_COLOR, SwingConnection_Color);
            ObjectSetInteger(0, last_label_name, OBJPROP_FONTSIZE, 9);
            ObjectSetString(0, last_label_name, OBJPROP_FONT, "Arial Bold");
            ObjectSetInteger(0, last_label_name, OBJPROP_ANCHOR, last_point.is_high ? ANCHOR_UPPER : ANCHOR_LOWER);
        }
    }
}

//+------------------------------------------------------------------+
//| 辅助函数                                                         |
//+------------------------------------------------------------------+

double GetAtrSafe(int bar)
{
    double atr = iATR(NULL,0,AtrPeriod,bar);
    if(atr <= 0) atr = MathMax(iHigh(NULL,0,bar) - iLow(NULL,0,bar), Point);
    return atr;
}

int GetMinSwingThresholdPoints(int bar)
{
    if(SwingMinPoints > 0) return SwingMinPoints;
    double atr = GetAtrSafe(bar);
    double threshold = atr * SwingMinAtr;
    int pts = (int)MathMax(1, MathRound(threshold / Point));
    return pts;
}

bool IsPriceGreater(double a, double b)
{
    return a > (b + EqualTolerancePoints * Point);
}

bool IsPriceLess(double a, double b)
{
    return a < (b - EqualTolerancePoints * Point);
}

bool IsDisplacementOK(double body_ratio, double momentum_ratio)
{
    if(!RequireDisplacement) return true;
    return (body_ratio >= MinBodyRatio && momentum_ratio >= MinAtrMomentum);
}

bool HasRecentFVG(int current_bar, bool bullish, const double &high[], const double &low[], const double &close[])
{
    // 参照 IdentifyFVG 的索引定义：current_bar 为第三根
    if(current_bar < 2) return false;
    if(current_bar + 2 >= ArraySize(high)) return false;
    if(bullish) {
        // 看涨FVG：第一根高点 < 第三根低点
        if(high[current_bar + 2] < low[current_bar]) return true;
    } else {
        // 看跌FVG：第一根低点 > 第三根高点
        if(low[current_bar + 2] > high[current_bar]) return true;
    }
    return false;
}

int GetSwingIndex(int bar_index, bool is_high)
{
    for(int i = 0; i < swing_count; i++) {
        if(swing_points[i].bar_index == bar_index && swing_points[i].is_high == is_high) {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| 缠论优化：K线包含关系处理                                         |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 缠论优化：K线包含关系处理                                         |
//+------------------------------------------------------------------+
int ProcessInclusion(int counted_bars, int rates_total, ProcessedBar& processed_bars[])
{
    ArraySetAsSeries(processed_bars, false);
    int processed_count = 0;
    
    bool debug = EnableDebugMode; // 使用全局调试开关
    // if(debug) Print("=== 开始包含处理 Total:", rates_total, " ===");

    int start_bar = rates_total - 1;
    if(counted_bars > 1) {
        // Full recalculation for simplicity/correctness
    }

    int trend = 0; // 0: undecided, 1: up, -1: down

    for(int i = start_bar; i >= 0; i--) {
        // 1. 初始化第一根K线
        if(processed_count == 0) {
            processed_bars[processed_count].time = Time[i];
            processed_bars[processed_count].open = Open[i];
            processed_bars[processed_count].high = High[i];
            processed_bars[processed_count].low = Low[i];
            processed_bars[processed_count].close = Close[i];
            processed_bars[processed_count].original_index = i;
            processed_bars[processed_count].high_bar_index = i;
            processed_bars[processed_count].low_bar_index = i;
            processed_bars[processed_count].actual_high_bar_index = i; // V1.59
            processed_bars[processed_count].actual_low_bar_index = i;  // V1.59
            processed_count++;
            continue;
        }

        // 获取上一根处理后的K线
        ProcessedBar last_processed_bar = processed_bars[processed_count - 1];
        
        // 2. 动态更新趋势 (核心修复：确保趋势随行情实时更新)
        if(processed_count > 1) {
            ProcessedBar prev_bar = processed_bars[processed_count - 2];
            
            // 严格的趋势判定规则
            if(last_processed_bar.high > prev_bar.high) trend = 1;
            else if(last_processed_bar.low < prev_bar.low) trend = -1;
            // 如果高点没创新高且低点没创新低（非包含但也不明确），维持原趋势
        }
        // V1.58修复：仅有1根已处理K线时trend=0，用该K线的开收盘方向初始化
        // 避免第一次包含关系因trend=0走"向下处理"的错误默认
        else if(processed_count == 1 && trend == 0) {
            trend = (processed_bars[0].close >= processed_bars[0].open) ? 1 : -1;
        }

        // check inclusion
        bool is_included = (High[i] <= last_processed_bar.high && Low[i] >= last_processed_bar.low) || 
                           (High[i] >= last_processed_bar.high && Low[i] <= last_processed_bar.low);

        if(is_included) {
            // [调试诊断] 捕获削峰现象 (高点被压低)
            if(debug && trend != 1 && High[i] > last_processed_bar.high && i < 200) {
                 Print("⚠️ 削峰警告! Bar[", i, "] Time:", TimeToString(Time[i]), 
                       " Trend:", trend, " High:", High[i], " > Last:", last_processed_bar.high, " (强制取Min)");
            }

            if(trend == 1) { // 上涨趋势：取Max-High, Max-Low
                if(High[i] > last_processed_bar.high) {
                    processed_bars[processed_count - 1].high = High[i];
                    processed_bars[processed_count - 1].high_bar_index = i;
                }
                if(Low[i] > last_processed_bar.low) {
                    processed_bars[processed_count - 1].low = Low[i];
                    processed_bars[processed_count - 1].low_bar_index = i;
                }
            } 
            else { // 下跌或未知趋势：取Min-High, Min-Low
                if(High[i] < last_processed_bar.high) {
                    processed_bars[processed_count - 1].high = High[i];
                    processed_bars[processed_count - 1].high_bar_index = i;
                }
                if(Low[i] < last_processed_bar.low) {
                    processed_bars[processed_count - 1].low = Low[i];
                    processed_bars[processed_count - 1].low_bar_index = i;
                }
            }

            // V1.59：不论趋势方向，始终追踪本处理后K线的实际最高/最低原始K线索引
            // 这解决了"削峰"现象：downtrend下原始高点被压低时，actual字段仍保留真实极值bar
            // 使 ValidateSwingPointByChan 能通过 actual_high_bar_index 找到对应的原始摆点
            if(High[i] > High[processed_bars[processed_count - 1].actual_high_bar_index]) {
                processed_bars[processed_count - 1].actual_high_bar_index = i;
            }
            if(Low[i] < Low[processed_bars[processed_count - 1].actual_low_bar_index]) {
                processed_bars[processed_count - 1].actual_low_bar_index = i;
            }
        } 
        else {
            // 新K线加入
            processed_bars[processed_count].time = Time[i];
            processed_bars[processed_count].open = Open[i];
            processed_bars[processed_count].high = High[i];
            processed_bars[processed_count].low = Low[i];
            processed_bars[processed_count].close = Close[i];
            processed_bars[processed_count].original_index = i;
            processed_bars[processed_count].high_bar_index = i;
            processed_bars[processed_count].low_bar_index = i;
            processed_bars[processed_count].actual_high_bar_index = i; // V1.59
            processed_bars[processed_count].actual_low_bar_index = i;  // V1.59
            processed_count++;
        }
    }
    
    ArraySetAsSeries(processed_bars, true);
    return processed_count;
}

//+------------------------------------------------------------------+
//| V1.58：查找摆点原始bar在处理后K线数组中的索引                    |
//+------------------------------------------------------------------+
int FindProcessedBarIndex(int raw_bar, bool is_high)
{
    // g_processed_bars经ArraySetAsSeries(true)后，索引0=最新
    // 优先：通过 high_bar_index / low_bar_index 精确匹配
    for(int i = 0; i < g_processed_bars_count; i++)
    {
        if(is_high && g_processed_bars[i].high_bar_index == raw_bar) return i;
        if(!is_high && g_processed_bars[i].low_bar_index == raw_bar) return i;
    }
    // V1.59：次优先：通过 actual_high/low_bar_index 匹配（处理削峰情况）
    // 当 raw_bar 是被"削峰"的那根K线时，high_bar_index不记录它，但actual_high_bar_index会记录
    for(int i = 0; i < g_processed_bars_count; i++)
    {
        if(is_high && g_processed_bars[i].actual_high_bar_index == raw_bar) return i;
        if(!is_high && g_processed_bars[i].actual_low_bar_index == raw_bar) return i;
    }
    // 回退：original_index搜索（容差±1）
    for(int i = 0; i < g_processed_bars_count; i++)
    {
        if(MathAbs(g_processed_bars[i].original_index - raw_bar) <= 1) return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| 缠论优化：识别分型（仅识别，不生成笔）                           |
//+------------------------------------------------------------------+
void IdentifyChanFractals(int processed_bars_count, ProcessedBar& processed_bars[])
{
    if(processed_bars_count < 5) {
        if(EnableDebugMode) Print("IdentifyChanFractals: processed_bars_count=", processed_bars_count, " 太少，跳过");
        return;
    }

    g_chan_fractal_count = 0;
    ArrayResize(g_chan_fractals, processed_bars_count);

    // 识别所有分型
    for(int i = 1; i < processed_bars_count - 1; i++)
    {
        ProcessedBar prev_bar = processed_bars[i+1];
        ProcessedBar curr_bar = processed_bars[i];
        ProcessedBar next_bar = processed_bars[i-1];

        // 顶分型：中间K线的高点和低点都是三根中最高的
        if(curr_bar.high > prev_bar.high && curr_bar.high > next_bar.high &&
           curr_bar.low > prev_bar.low && curr_bar.low > next_bar.low)
        {
            g_chan_fractals[g_chan_fractal_count].bar_index = i;
            g_chan_fractals[g_chan_fractal_count].price = curr_bar.high;
            g_chan_fractals[g_chan_fractal_count].is_top = true;
            g_chan_fractals[g_chan_fractal_count].original_bar = curr_bar.high_bar_index;
            g_chan_fractals[g_chan_fractal_count].time = curr_bar.time;
            g_chan_fractal_count++;
        }
        // 底分型：中间K线的高点和低点都是三根中最低的
        else if(curr_bar.low < prev_bar.low && curr_bar.low < next_bar.low &&
                curr_bar.high < prev_bar.high && curr_bar.high < next_bar.high)
        {
            g_chan_fractals[g_chan_fractal_count].bar_index = i;
            g_chan_fractals[g_chan_fractal_count].price = curr_bar.low;
            g_chan_fractals[g_chan_fractal_count].is_top = false;
            g_chan_fractals[g_chan_fractal_count].original_bar = curr_bar.low_bar_index;
            g_chan_fractals[g_chan_fractal_count].time = curr_bar.time;
            g_chan_fractal_count++;
        }
    }

    if(EnableDebugMode) Print("IdentifyChanFractals: processed_bars=", processed_bars_count, ", fractals=", g_chan_fractal_count);

    // V1.49诊断：打印所有分型（仅在调试模式下）
    if(EnableDebugMode) {
        Print("=== V1.49 分型列表（最近100个）===");
        int max_print = MathMin(g_chan_fractal_count, 100);
        for(int d = 0; d < max_print; d++) {
            Print("  fractal[", d, "]: ", (g_chan_fractals[d].is_top ? "顶" : "底"),
                  " bar_index=", g_chan_fractals[d].bar_index,
                  " original_bar=", g_chan_fractals[d].original_bar,
                  " price=", g_chan_fractals[d].price,
                  " time=", TimeToString(g_chan_fractals[d].time));
        }
    }
}

//+------------------------------------------------------------------+
//| 验证摆点是否符合缠论分型条件                                      |
//+------------------------------------------------------------------+
// cached_atr：由调用方（FilterSwingPointsByChan）统一计算并传入，避免每次摆点都调用 iATR()
bool ValidateSwingPointByChan(int bar_index, double price, bool is_high, double cached_atr = -1.0)
{
    // 查找该摆点位置是否对应有效的缠论分型
    // 由于K线包含处理，分型位置可能有偏移，需要放宽匹配条件
    int tolerance_bars = StructureLookback + 2; // 位置容差

    // V1.51优化：增大价格容差，因为K线包含处理会导致价格偏移
    // V1.59性能优化：优先使用调用方传入的缓存ATR，避免每个摆点都独立调用 iATR()
    double atr_value = (cached_atr > 0) ? cached_atr : iATR(Symbol(), Period(), AtrPeriod, 0);
    double tolerance_price = atr_value * 0.5;

    // V1.59b：预计算swing在处理后K线空间中的位置
    // 使用更新后的FindProcessedBarIndex（支持actual_high/low_bar_index搜索），
    // 确保削峰情况下也能找到对应的处理后K线索引
    int swing_proc_idx = FindProcessedBarIndex(bar_index, is_high);

    // V1.49诊断：记录最接近的分型匹配情况
    int closest_fractal_idx = -1;
    int closest_bar_diff = 999999;
    double closest_price_diff = 999999;

    for(int i = 0; i < g_chan_fractal_count; i++)
    {
        FractalPoint fractal = g_chan_fractals[i];

        // 检查类型匹配（高点对应顶分型，低点对应底分型）
        if(fractal.is_top != is_high) continue;

        int bar_diff = MathAbs(fractal.original_bar - bar_index);
        double price_diff = MathAbs(fractal.price - price);

        // 记录最接近的匹配
        if(bar_diff < closest_bar_diff || (bar_diff == closest_bar_diff && price_diff < closest_price_diff))
        {
            closest_bar_diff = bar_diff;
            closest_price_diff = price_diff;
            closest_fractal_idx = i;
        }

        // 匹配路径1（V1.51）：原始K线位置即时信任
        // 当raw bar距离分型original_bar <= 3时，完全信任位置，不检查价格
        // 3是阈值原因：削峰后分型可能偏移1-3根raw bar（原来<=2偶尔不够）
        if(bar_diff <= 3)
        {
            if(EnableDebugMode)
                Print("V1.59b 路径1(raw bar_diff)通过: swing bar=", bar_index,
                      " fractal original_bar=", fractal.original_bar, " bar_diff=", bar_diff);
            return true;
        }
        // 匹配路径2：原始位置+价格双重容差
        else if(bar_diff <= tolerance_bars && price_diff <= tolerance_price)
        {
            return true;
        }

        // 匹配路径3（V1.59b）：处理后K线空间距离检查（核心修复：削峰导致的分型匹配失败）
        // 原理：削峰后，swing bar被合并到分型所在处理后K线的相邻processed bar中。
        //       例：bar=13削峰后在processed_bar[3555]，fractal[6]在processed_bar[3556]
        //       二者在processed空间距离仅为1，应视为匹配。
        // 使用actual_high/low_bar_index确保FindProcessedBarIndex能正确找到被削峰的bar
        if(swing_proc_idx >= 0)
        {
            int proc_diff = MathAbs(fractal.bar_index - swing_proc_idx);
            if(proc_diff <= 2) // processed K线空间内相邻（<=2处理后K线）
            {
                if(EnableDebugMode)
                    Print("V1.59b 路径3(processed空间)通过: swing bar=", bar_index,
                          " swing_proc_idx=", swing_proc_idx,
                          " fractal.bar_index=", fractal.bar_index,
                          " proc_diff=", proc_diff);
                return true;
            }
        }
    }

    // V1.49诊断：打印未匹配的摆点信息
    if(EnableDebugMode && closest_fractal_idx >= 0)
    {
        FractalPoint closest = g_chan_fractals[closest_fractal_idx];
        Print("V1.51 ValidateSwingPointByChan 失败: ",
              (is_high ? "高点" : "低点"), " bar=", bar_index, " price=", price,
              " | 最近分型: ", (closest.is_top ? "顶" : "底"),
              " original_bar=", closest.original_bar,
              " price=", closest.price,
              " | bar差=", closest_bar_diff, "(容差=", tolerance_bars, ")",
              " price差=", closest_price_diff, "(容差=", tolerance_price, ")");
    }
    else if(EnableDebugMode)
    {
        Print("V1.51 ValidateSwingPointByChan 失败: ",
              (is_high ? "高点" : "低点"), " bar=", bar_index, " price=", price,
              " | 没有找到同类型的分型！");
    }

    return false;
}

//+------------------------------------------------------------------+
//| V1.69：V1.64「极短反向」噪声判定（方案A）                          |
//| 仅当回抽未突破栈内最近同向极值时，才允许丢弃 current（保留原5210类语义）；|
//| 若 current 为新低(相对最近低点)或新高(相对最近高点)，视为结构延伸，走回溯。|
//+------------------------------------------------------------------+
bool ChanV64_ShouldDiscardOppositeShortNoise(SwingPoint &last_sp, SwingPoint &current_sp, SwingPoint &final_swings[], int final_count)
{
    double tol = EqualTolerancePoints * Point;

    if(final_count < 2)
        return true;

    if(last_sp.is_high && !current_sp.is_high)
    {
        bool found = false;
        double ref_low = 0;
        for(int i = final_count - 2; i >= 0; i--)
        {
            if(!final_swings[i].is_high)
            {
                ref_low = final_swings[i].price;
                found = true;
                break;
            }
        }
        if(!found)
            return true;
        // 与 IsPriceLess 一致：明确低于最近低点 = 下跌延伸，不得当噪声丢 current
        if(current_sp.price < ref_low - tol)
            return false;
        return true;
    }

    if(!last_sp.is_high && current_sp.is_high)
    {
        bool found = false;
        double ref_high = 0;
        for(int i = final_count - 2; i >= 0; i--)
        {
            if(final_swings[i].is_high)
            {
                ref_high = final_swings[i].price;
                found = true;
                break;
            }
        }
        if(!found)
            return true;
        if(current_sp.price > ref_high + tol)
            return false;
        return true;
    }

    return true;
}

//+------------------------------------------------------------------+
//| 缠论优化：过滤不符合条件的摆点                                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| V1.70 内部重写标准MT4 ZigZag算法，输出严格交替转折点骨架          |
//| scan_limit: 扫描的最大bar shift(含)；pivots: 输出(按时间旧->新)   |
//| 返回转折点数量                                                    |
//+------------------------------------------------------------------+
int CalculateZigZagPivots(int scan_limit, ZigZagPivot &pivots[])
{
    int size = scan_limit + 1;
    // 数据不足以容纳一个ZigZag窗口
    if(size < ZigZag_Depth + ZigZag_Backstep + 1) return 0;

    // 两个标记缓冲：series索引(0=最新)，0.0表示该bar非转折候选
    double zz_high[];
    double zz_low[];
    ArrayResize(zz_high, size);
    ArrayResize(zz_low, size);
    for(int i = 0; i < size; i++) { zz_high[i] = 0.0; zz_low[i] = 0.0; }

    double deviation = ZigZag_Deviation * Point;
    double lastlow  = 0.0;
    double lasthigh = 0.0;

    // 从旧(大shift)到新(小shift)扫描
    for(int shift = scan_limit - ZigZag_Backstep; shift >= 0; shift--)
    {
        // --- 低点候选 ---
        int lowest_idx = iLowest(Symbol(), Period(), MODE_LOW, ZigZag_Depth, shift);
        if(lowest_idx < 0) continue;
        double cur_low = iLow(Symbol(), Period(), shift);
        double val = iLow(Symbol(), Period(), lowest_idx);
        if(val == lastlow) {
            val = 0.0;
        } else {
            lastlow = val;
            if(cur_low - val > deviation) {
                val = 0.0;
            } else {
                for(int back = 1; back <= ZigZag_Backstep; back++) {
                    int b = shift + back;
                    if(b < size && zz_low[b] != 0.0 && zz_low[b] > val) zz_low[b] = 0.0;
                }
            }
        }
        zz_low[shift] = (cur_low == val) ? val : 0.0;

        // --- 高点候选 ---
        int highest_idx = iHighest(Symbol(), Period(), MODE_HIGH, ZigZag_Depth, shift);
        if(highest_idx < 0) continue;
        double cur_high = iHigh(Symbol(), Period(), shift);
        val = iHigh(Symbol(), Period(), highest_idx);
        if(val == lasthigh) {
            val = 0.0;
        } else {
            lasthigh = val;
            if(val - cur_high > deviation) {
                val = 0.0;
            } else {
                for(int back = 1; back <= ZigZag_Backstep; back++) {
                    int b = shift + back;
                    if(b < size && zz_high[b] != 0.0 && zz_high[b] < val) zz_high[b] = 0.0;
                }
            }
        }
        zz_high[shift] = (cur_high == val) ? val : 0.0;
    }

    // 提取严格交替转折点(时间旧->新)：同类型相邻时保留更极端者
    ArrayResize(pivots, size);
    int pivot_count = 0;
    int last_type = 0; // 0=none, 1=high, -1=low
    for(int shift = scan_limit; shift >= 0; shift--)
    {
        bool has_high = (zz_high[shift] != 0.0);
        bool has_low  = (zz_low[shift]  != 0.0);

        // 低点
        if(has_low) {
            if(last_type == -1 && pivot_count > 0) {
                // 连续低点：保留更低者(更极端)
                if(zz_low[shift] < pivots[pivot_count - 1].price) {
                    pivots[pivot_count - 1].bar_index = shift;
                    pivots[pivot_count - 1].price     = zz_low[shift];
                }
            } else {
                pivots[pivot_count].bar_index = shift;
                pivots[pivot_count].price     = zz_low[shift];
                pivots[pivot_count].is_high   = false;
                pivot_count++;
                last_type = -1;
            }
        }
        // 高点
        if(has_high) {
            if(last_type == 1 && pivot_count > 0) {
                // 连续高点：保留更高者(更极端)
                if(zz_high[shift] > pivots[pivot_count - 1].price) {
                    pivots[pivot_count - 1].bar_index = shift;
                    pivots[pivot_count - 1].price     = zz_high[shift];
                }
            } else {
                pivots[pivot_count].bar_index = shift;
                pivots[pivot_count].price     = zz_high[shift];
                pivots[pivot_count].is_high   = true;
                pivot_count++;
                last_type = 1;
            }
        }
    }

    ArrayResize(pivots, pivot_count);
    if(EnableDebugMode)
        Print("CalculateZigZagPivots: scan_limit=", scan_limit, " 转折点数=", pivot_count);
    return pivot_count;
}

//+------------------------------------------------------------------+
//| V1.70 ZigZag 摆点前置过滤：以ZigZag交替骨架对原始摆点做严格交集    |
//| 仿 FilterSwingPointsByChan 写回模式，操作全局 swing_points/count   |
//+------------------------------------------------------------------+
void FilterSwingPointsByZigZag()
{
    if(!EnableZigZagFilter) return;
    if(swing_count < 2) return;

    // 扫描范围与主循环 limit 保持一致
    int scan_limit;
    if(MaxBarsToCalculate > 0) scan_limit = MathMin(Bars - 1, MaxBarsToCalculate);
    else                       scan_limit = Bars - 1;

    ZigZagPivot pivots[];
    int pivot_count = CalculateZigZagPivots(scan_limit, pivots);
    if(pivot_count == 0) {
        if(EnableDebugMode) Print("FilterSwingPointsByZigZag: 无转折点，保留原摆点");
        return; // 降级保护
    }

    // 转折点占用标记(严格一对一匹配)
    bool pivot_used[];
    ArrayResize(pivot_used, pivot_count);
    for(int p = 0; p < pivot_count; p++) pivot_used[p] = false;

    SwingPoint filtered[];
    ArrayResize(filtered, swing_count);
    int filtered_count = 0;

    // 遍历原始摆点(保持原时间顺序)，保留与未占用转折点同类型且bar距离<=窗口的最近者
    for(int i = 0; i < swing_count; i++)
    {
        int best_p    = -1;
        int best_dist = ZigZag_MatchWindow + 1;
        for(int p = 0; p < pivot_count; p++)
        {
            if(pivot_used[p]) continue;
            if(pivots[p].is_high != swing_points[i].is_high) continue;
            int dist = MathAbs(pivots[p].bar_index - swing_points[i].bar_index);
            if(dist <= ZigZag_MatchWindow && dist < best_dist) {
                best_dist = dist;
                best_p    = p;
            }
        }
        if(best_p >= 0) {
            pivot_used[best_p] = true;
            filtered[filtered_count] = swing_points[i]; // 继承全部元数据
            filtered_count++;
        } else if(EnableDebugMode) {
            Print("FilterSwingPointsByZigZag: 剔除未确认摆点 ",
                  (swing_points[i].is_high ? "高" : "低"),
                  " bar=", swing_points[i].bar_index,
                  " price=", swing_points[i].price);
        }
    }

    if(EnableDebugMode)
        Print("FilterSwingPointsByZigZag: 原始=", swing_count, " 过滤后=", filtered_count);

    if(filtered_count < 2) {
        if(EnableDebugMode) Print("FilterSwingPointsByZigZag: 过滤后不足2点，保留原摆点");
        return; // 降级保护
    }

    // 写回全局数组
    ArrayResize(swing_points, filtered_count);
    for(int i = 0; i < filtered_count; i++) swing_points[i] = filtered[i];
    swing_count = filtered_count;

    // 删除部分摆点后重新分类HH/HL/LH/LL与趋势(与缠论过滤一致)
    ReclassifySwingPoints();
}

void FilterSwingPointsByChan()
{
    int original_count = swing_count;
    if(EnableDebugMode) Print("FilterSwingPointsByChan: 开始过滤, 原始摆点数=", swing_count, ", 分型数=", g_chan_fractal_count);

    // V1.48诊断：打印所有原始摆点
    if(EnableDebugMode) {
        Print("=== V1.48 原始摆点列表 ===");
        for(int d = 0; d < swing_count; d++) {
            Print("  swing[", d, "]: ", (swing_points[d].is_high ? "高" : "低"),
                  " bar=", swing_points[d].bar_index, " price=", swing_points[d].price);
        }
    }

    if(swing_count < 2) {
        if(EnableDebugMode) Print("FilterSwingPointsByChan: 摆点太少，跳过过滤");
        return;
    }

    // 如果没有识别到分型，跳过过滤（保留原有摆点）
    if(g_chan_fractal_count == 0) {
        if(EnableDebugMode) Print("FilterSwingPointsByChan: 无分型数据，保留原有摆点");
        return;
    }

    // V1.59性能优化：统一计算ATR，传递给 ValidateSwingPointByChan 和幅度过滤，避免在每个摆点内重复调用 iATR()
    double current_atr = iATR(Symbol(), Period(), AtrPeriod, 0);

    // 创建临时数组存储过滤后的摆点
    SwingPoint filtered_swings[];
    ArrayResize(filtered_swings, swing_count);
    int filtered_count = 0;

    // 第一遍：分型验证 + MA21均线过滤（缠论步骤内，包含处理之后）
    for(int i = 0; i < swing_count; i++)
    {
        SwingPoint sp = swing_points[i];

        // 1. 缠论分型验证（传入缓存ATR，避免每次单独调用 iATR）
        if(!ValidateSwingPointByChan(sp.bar_index, sp.price, sp.is_high, current_atr))
        {
            if(EnableDebugMode)
                Print("V1.49 第一遍过滤(分型): 删除 ", (sp.is_high ? "高点" : "低点"),
                      " bar=", sp.bar_index, " price=", sp.price);
            continue;
        }

        // V1.60：2. MA21均线过滤（缠论结构验证阶段强制使用Mode=0：仅H/L基础检查）
        // 原因：Mode=1/2的Close检查会把射击之星等真实极值点（如新高后收盘低于MA21）错误过滤
        //       导致真实HH被删除，而次高点被误标为HH。结构验证只做基础H/L方向检查即可。
        //       Mode=1/2可在未来BOS/CHOCH信号确认阶段使用（区分结构识别 vs 信号质量）。
        if(!CheckMA21FilterChan(sp.bar_index, sp.price, sp.is_high, 0))
        {
            if(EnableDebugMode)
                Print("V1.60 第一遍过滤(MA21 Mode=0): 删除 ",
                      (sp.is_high ? "高点" : "低点"),
                      " bar=", sp.bar_index, " price=", sp.price,
                      " ma21=", (sp.bar_index < ArraySize(MA21_Buffer) ? MA21_Buffer[sp.bar_index] : 0));
            continue;
        }

        filtered_swings[filtered_count] = sp;
        filtered_count++;
    }

    if(EnableDebugMode) Print("FilterSwingPointsByChan: 分型+MA21过滤后剩余=", filtered_count);

    // 如果过滤后没有摆点，保留原有摆点
    if(filtered_count < 2) {
        if(EnableDebugMode) Print("FilterSwingPointsByChan: 过滤后摆点不足，保留原有摆点");
        return;
    }

    // === V1.52新增：极点识别 ===
    // 在第二遍过滤之前，标记极点（极高/极低），后续回溯时保护这些点
    if(EnableExtremeProtection)
    {
        for(int i = 0; i < filtered_count; i++)
        {
            filtered_swings[i].is_extreme = false; // 先重置

            if(filtered_swings[i].is_high)  // 当前是高点
            {
                // 找前一个高点
                int prev_high_idx = -1;
                for(int j = i - 1; j >= 0; j--) {
                    if(filtered_swings[j].is_high) { prev_high_idx = j; break; }
                }
                // 找后一个高点
                int next_high_idx = -1;
                for(int j = i + 1; j < filtered_count; j++) {
                    if(filtered_swings[j].is_high) { next_high_idx = j; break; }
                }

                // 判断是否为极高点
                if(prev_high_idx >= 0 && next_high_idx >= 0)
                {
                    if(filtered_swings[i].price > filtered_swings[prev_high_idx].price &&
                       filtered_swings[i].price > filtered_swings[next_high_idx].price)
                    {
                        filtered_swings[i].is_extreme = true;
                        if(DebugExtremePoints) {
                            Print("V1.52 极点识别: 极高点 bar=", filtered_swings[i].bar_index,
                                  " price=", filtered_swings[i].price,
                                  " (prev=", filtered_swings[prev_high_idx].price,
                                  ", next=", filtered_swings[next_high_idx].price, ")");
                        }
                    }
                }
            }
            else  // 当前是低点
            {
                // 找前一个低点
                int prev_low_idx = -1;
                for(int j = i - 1; j >= 0; j--) {
                    if(!filtered_swings[j].is_high) { prev_low_idx = j; break; }
                }
                // 找后一个低点
                int next_low_idx = -1;
                for(int j = i + 1; j < filtered_count; j++) {
                    if(!filtered_swings[j].is_high) { next_low_idx = j; break; }
                }

                // 判断是否为极低点
                if(prev_low_idx >= 0 && next_low_idx >= 0)
                {
                    if(filtered_swings[i].price < filtered_swings[prev_low_idx].price &&
                       filtered_swings[i].price < filtered_swings[next_low_idx].price)
                    {
                        filtered_swings[i].is_extreme = true;
                        if(DebugExtremePoints) {
                            Print("V1.52 极点识别: 极低点 bar=", filtered_swings[i].bar_index,
                                  " price=", filtered_swings[i].price,
                                  " (prev=", filtered_swings[prev_low_idx].price,
                                  ", next=", filtered_swings[next_low_idx].price, ")");
                        }
                    }
                }
            }
        }
    }
    // === V1.52极点识别结束 ===

    // 第二遍：过滤不符合笔条件的摆点（K线数、幅度）
    // V1.40优化：简单成对删除机制 + 详细调试日志
    SwingPoint final_swings[];
    ArrayResize(final_swings, filtered_count);
    int final_count = 0;

    // 调试：打印第一遍过滤后的摆点列表
    if(EnableDebugMode) {
        Print("=== V1.45 第二遍过滤开始（纯回溯机制）===");
        Print("filtered_count=", filtered_count, ", MinStrokeBars=", MinStrokeBars);
        for(int d = 0; d < filtered_count; d++) {
            Print("  filtered[", d, "]: ", (filtered_swings[d].is_high ? "高" : "低"),
                  " bar=", filtered_swings[d].bar_index, " price=", filtered_swings[d].price);
        }
    }

    // === V1.45：纯回溯删除机制（缠论核心原则）===
    // 核心原则：
    // 1. 摆点成对出现（高-低交替）
    // 2. 如果当前点与前一点不能成笔，删除前一点，让当前点与更前面的点比较
    // 3. 如果回溯后遇到同向点，保留更极端的那个
    // 4. 持续回溯直到：找到能成笔的配对 或 final为空

    for(int i = 0; i < filtered_count; i++)
    {
        SwingPoint current_sp = filtered_swings[i];

        // 第一个摆点直接保留
        if(final_count == 0)
        {
            final_swings[final_count] = current_sp;
            final_count++;
            if(EnableDebugMode) {
                Print("i=", i, ": 首个摆点 ", (current_sp.is_high ? "高" : "低"),
                      "(bar=", current_sp.bar_index, ", price=", current_sp.price, ") → 直接保留");
            }
            continue;
        }

        if(EnableDebugMode) {
            Print("i=", i, ": 处理 ", (current_sp.is_high ? "高" : "低"),
                  "(bar=", current_sp.bar_index, ", price=", current_sp.price, ")");
        }

        // 回溯循环：持续检查直到找到有效配对或final为空
        bool point_handled = false;
        while(!point_handled && final_count > 0)
        {
            SwingPoint last_sp = final_swings[final_count - 1];

            if(EnableDebugMode) {
                Print("    比较: current ", (current_sp.is_high ? "高" : "低"), "(bar=", current_sp.bar_index,
                      ") vs last ", (last_sp.is_high ? "高" : "低"), "(bar=", last_sp.bar_index, ")");
            }

            // 情况1：同向摆点
            if(current_sp.is_high == last_sp.is_high)
            {
                // V1.58优化5：明确分类等价情况（等高/等低）
                // 三种严格情况：current更极端 / last更极端 / 等价
                int compare_result = 0; // 0=等价, 1=current更极端, -1=last更极端
                if(current_sp.is_high)
                {
                    if(current_sp.price > last_sp.price)       compare_result =  1;
                    else if(current_sp.price < last_sp.price)  compare_result = -1;
                    // 等于时 compare_result = 0：等高保留先出现的last，丢弃current
                }
                else
                {
                    if(current_sp.price < last_sp.price)       compare_result =  1;
                    else if(current_sp.price > last_sp.price)  compare_result = -1;
                    // 等于时 compare_result = 0：等低保留先出现的last，丢弃current
                }

                // V1.52极点保护：同向比较时的极点保护
                if(EnableExtremeProtection)
                {
                    // 如果last是极点，不能被替换（即使current更极端，也保留last）
                    if(last_sp.is_extreme && !current_sp.is_extreme)
                    {
                        if(EnableDebugMode || DebugExtremePoints) {
                            Print("    → V1.52 极点保护: last是极点，不能被替换，丢弃current");
                        }
                        point_handled = true;
                        break;
                    }
                    // 如果current是极点而last不是，用current替换last
                    if(current_sp.is_extreme && !last_sp.is_extreme)
                    {
                        final_swings[final_count - 1] = current_sp;
                        if(EnableDebugMode || DebugExtremePoints) {
                            Print("    → V1.52 极点保护: current是极点，替换非极点last");
                        }
                        point_handled = true;
                        break;
                    }
                    // 两个都是极点，按价格比较决定（compare_result已计算）
                }

                if(compare_result == 1)
                {
                    // current更极端，用current替换last
                    // V1.58说明：替换后pre_last→current的距离和幅度均不小于原pre_last→last，无需再验笔
                    final_swings[final_count - 1] = current_sp;
                    if(EnableDebugMode) {
                        Print("    → 同向: current更极端(", current_sp.price, " vs ", last_sp.price,
                              "), 替换final[", (final_count-1), "]");
                    }
                }
                else if(compare_result == -1)
                {
                    // last更极端，保留last，丢弃current
                    if(EnableDebugMode) {
                        Print("    → 同向: last更极端(", last_sp.price, " vs ", current_sp.price,
                              "), 丢弃current");
                    }
                }
                else
                {
                    // 等价（等高/等低）：保留先出现的last，丢弃current（缠论先到先得原则）
                    if(EnableDebugMode) {
                        Print("    → 同向: 等价(", current_sp.price, " == ", last_sp.price,
                              "), 保留先出现的last，丢弃current");
                    }
                }
                point_handled = true;
                break;
            }

            // 情况2：反向摆点，检查是否成笔
            // V1.58优化1：优先使用处理后K线索引差（缠论标准）；未能获取时回退到原始bar_index差
            int bar_count = MathAbs(current_sp.bar_index - last_sp.bar_index);
            int stroke_bars = bar_count; // 实际用于判断的笔长度
            bool use_processed = (current_sp.processed_index >= 0 && last_sp.processed_index >= 0);
            if(use_processed)
            {
                stroke_bars = MathAbs(current_sp.processed_index - last_sp.processed_index);
            }

            if(EnableDebugMode) {
                Print("    → 反向: 原始K线数=", bar_count,
                      use_processed ? StringFormat(", 处理后K线数=%d", stroke_bars) : "",
                      (stroke_bars >= MinStrokeBars ? " >= " : " < "), MinStrokeBars);
            }

            // 检查K线数（使用更精确的stroke_bars）
            if(stroke_bars < MinStrokeBars)
            {
                // V1.58优化4：极点保护 + 处理后K线精确判断
                // 若last是极点且stroke_bars < MinStrokeBars，尝试降低门槛（减半）
                // 若降低后仍满足，则允许成笔（保留极点的同时维持缠论笔定义）
                // 若仍不足，回溯删除last（极点也服从缠论回溯原则）
                if(EnableExtremeProtection && last_sp.is_extreme)
                {
                    int reduced_threshold = MathMax(1, MinStrokeBars / 2);
                    if(stroke_bars >= reduced_threshold)
                    {
                        // 降低门槛后成笔：极点作为笔的端点，接受此笔
                        final_swings[final_count] = current_sp;
                        final_count++;
                        if(EnableDebugMode || DebugExtremePoints) {
                            Print("    → V1.58 极点降门槛成笔: stroke=", stroke_bars,
                                  " >= reduced=", reduced_threshold, "，接受此笔");
                        }
                        point_handled = true;
                        break;
                    }
                    else
                    {
                        // V1.64：stroke极短(<=2)时，current为噪音，丢弃current保留last（含极点）
                        // V1.69方案A：若current为相对栈内最近低点的新低（或对称新高），不得丢弃，应回溯last
                        if(stroke_bars <= 2) {
                            if(ChanV64_ShouldDiscardOppositeShortNoise(last_sp, current_sp, final_swings, final_count)) {
                                if(EnableDebugMode || DebugExtremePoints) {
                                    Print("    → V1.64 极短笔(stroke=", stroke_bars, ")且last为极点：current视作噪音，丢弃current保留last");
                                }
                                point_handled = true;
                                break;
                            }
                            if(EnableDebugMode || DebugExtremePoints) {
                                Print("    → V1.69 极短反向+延伸极值：不按噪声丢current，回溯删除last");
                            }
                            final_count--;
                            continue;
                        }
                        // 即使降低门槛后也不成笔，回溯（极点也服从缠论原则）
                        if(EnableDebugMode || DebugExtremePoints) {
                            Print("    → V1.58 极点回溯: stroke=", stroke_bars,
                                  " < reduced=", reduced_threshold, "，回溯删除极点last");
                        }
                        final_count--;
                        continue;
                    }
                }

                // V1.64：当stroke极短(<=2)时，current多半为噪音（如新高后的1根K线小回调）
                // V1.69方案A：新低/新高相对栈内最近同向极值为「延伸」时，不得丢弃current，改回溯last
                // 例：高(bar=38,5210.58)与低(bar=37,5182.56)仅1根且低不破前低，仍丢弃低；真LL破前低则回溯
                if(stroke_bars <= 2) {
                    if(ChanV64_ShouldDiscardOppositeShortNoise(last_sp, current_sp, final_swings, final_count)) {
                        if(EnableDebugMode) {
                            Print("    → V1.64 极短笔(stroke=", stroke_bars, ")，current视作噪音，丢弃current保留last");
                        }
                        point_handled = true;
                        break;
                    }
                    if(EnableDebugMode) {
                        Print("    → V1.69 极短反向+延伸极值：不按噪声丢current，回溯删除last");
                    }
                    final_count--;
                    continue;
                }

                // V1.57修复：不成笔时按缠论原则回溯 - 删除last，让current与更前面的点比较
                if(EnableDebugMode) {
                    Print("    → 不成笔(stroke=", stroke_bars, " < ", MinStrokeBars,
                          ")！回溯: 删除last(", (last_sp.is_high ? "高" : "低"),
                          ", bar=", last_sp.bar_index,
                          "), current(", (current_sp.is_high ? "高" : "低"),
                          ", bar=", current_sp.bar_index, ")与更前点比较");
                }
                final_count--;
                // 不break，继续while循环让current与新的last比较
                continue;
            }

            // 检查幅度（如果启用）
            if(MinStrokeATR > 0 && current_atr > 0)
            {
                double amplitude = MathAbs(current_sp.price - last_sp.price);
                double min_amplitude = MinStrokeATR * current_atr;
                if(amplitude < min_amplitude)
                {
                    // V1.58优化4：幅度不足时的极点处理（同bar_count策略一致）
                    if(EnableExtremeProtection && last_sp.is_extreme)
                    {
                        double reduced_amplitude = min_amplitude * 0.5;
                        if(amplitude >= reduced_amplitude)
                        {
                            final_swings[final_count] = current_sp;
                            final_count++;
                            if(EnableDebugMode || DebugExtremePoints) {
                                Print("    → V1.58 极点降幅度门槛成笔: amplitude=", amplitude,
                                      " >= reduced=", reduced_amplitude);
                            }
                            point_handled = true;
                            break;
                        }
                        else
                        {
                            if(EnableDebugMode || DebugExtremePoints) {
                                Print("    → V1.58 极点幅度回溯: amplitude=", amplitude,
                                      " < reduced=", reduced_amplitude, "，回溯删除极点last");
                            }
                            final_count--;
                            continue;
                        }
                    }
                    // V1.57修复：幅度不足时同样回溯 - 删除last
                    if(EnableDebugMode) {
                        Print("    → 幅度不足(", amplitude, " < ", min_amplitude,
                              ")！回溯: 删除last, current与更前点比较");
                    }
                    final_count--;
                    continue;
                }
            }

            // 成笔！保留current
            final_swings[final_count] = current_sp;
            final_count++;
            if(EnableDebugMode) {
                Print("    → 成笔！添加current, final_count=", final_count);
            }
            point_handled = true;
            break;
        }

        // 如果回溯到final为空，current成为第一个摆点
        if(final_count == 0 && !point_handled)
        {
            final_swings[final_count] = current_sp;
            final_count++;
            if(EnableDebugMode) {
                Print("    → 回溯到空，current成为首个摆点, final_count=", final_count);
            }
        }
    }

    // 调试：打印最终结果
    if(EnableDebugMode) {
        Print("=== 第二遍过滤结束 ===");
        Print("最终保留摆点数: ", final_count);
        for(int d = 0; d < final_count; d++) {
            Print("  final[", d, "]: ", (final_swings[d].is_high ? "高" : "低"),
                  " bar=", final_swings[d].bar_index, " price=", final_swings[d].price);
        }
    }

    // 将过滤结果写回原数组
    ArrayResize(swing_points, final_count);
    for(int i = 0; i < final_count; i++)
    {
        swing_points[i] = final_swings[i];
    }
    swing_count = final_count;

    // === V1.53新增：过滤后重新分类摆点 ===
    // 由于缠论过滤删除了部分摆点，需要重新计算HH/HL/LH/LL分类和趋势
    ReclassifySwingPoints();
}

//+------------------------------------------------------------------+
//| V1.53新增：重新分类所有摆点（缠论过滤后调用）                      |
//+------------------------------------------------------------------+
void ReclassifySwingPoints()
{
    if(swing_count < 2) {
        if(EnableDebugMode) {
            Print("ReclassifySwingPoints: 摆点数量不足(", swing_count, ")，跳过重新分类");
        }
        return;
    }

    if(EnableDebugMode) {
        Print("=== V1.53 ReclassifySwingPoints 开始 ===");
        Print("摆点总数: ", swing_count);
    }

    // 重置全局趋势跟踪变量
    g_last_hh_index = -1;
    g_last_hl_index = -1;
    g_last_lh_index = -1;
    g_last_ll_index = -1;
    g_market_trend = 0;

    // 重置状态机变量
    g_trend_state = 0;
    g_protected_high_index = -1;
    g_protected_low_index = -1;

    // 重置CHoCH唯一性状态标志
    g_choch_down_occurred_in_uptrend = false;
    g_choch_up_occurred_in_downtrend = false;

    // 重置所有摆点的分类
    for(int i = 0; i < swing_count; i++) {
        swing_points[i].structure_type = -1; // 重置为未分类
        swing_points[i].is_broken = false;   // 重置突破状态
    }

    // 按时间顺序重新分类每个摆点
    // 注意：swing_points已经按时间顺序排列（bar_index从大到小，即从旧到新）
    for(int i = 0; i < swing_count; i++) {
        ClassifySwingPoint(i);

        if(EnableDebugMode) {
            string type_str = "";
            switch(swing_points[i].structure_type) {
                case 0: type_str = "HH"; break;
                case 1: type_str = "HL"; break;
                case 2: type_str = "LH"; break;
                case 3: type_str = "LL"; break;
                default: type_str = "未分类"; break;
            }
            Print("  重新分类 swing[", i, "]: ", (swing_points[i].is_high ? "高" : "低"),
                  " bar=", swing_points[i].bar_index, " price=", swing_points[i].price,
                  " → ", type_str);
        }
    }

    // 最终更新趋势
    UpdateMarketTrend();

    if(EnableDebugMode) {
        string trend_str = (g_market_trend == 1) ? "上升" : ((g_market_trend == -1) ? "下降" : "未定");
        Print("=== V1.53 ReclassifySwingPoints 完成 ===");
        Print("最终趋势: ", trend_str);
    }
}

//+------------------------------------------------------------------+
//| V1.53新增：绘制趋势指示器                                          |
//+------------------------------------------------------------------+
void DrawTrendIndicator()
{
    if(!ShowTrendIndicator) return;

    string obj_name = "SMC_TrendIndicator";
    string trend_text = "";
    color trend_color = NeutralTrend_Color;

    // 根据趋势状态设置显示内容
    if(g_market_trend == 1) {
        trend_text = "▲ 上升趋势";
        trend_color = UpTrend_Color;
    } else if(g_market_trend == -1) {
        trend_text = "▼ 下降趋势";
        trend_color = DownTrend_Color;
    } else {
        trend_text = "◆ 震荡/未定";
        trend_color = NeutralTrend_Color;
    }

    // 创建或更新标签对象
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
    }

    ObjectSetInteger(0, obj_name, OBJPROP_CORNER, TrendIndicator_Corner);
    ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, TrendIndicator_XOffset);
    ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, TrendIndicator_YOffset);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, trend_color);
    ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, TrendIndicator_FontSize);
    ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial Bold");
    ObjectSetString(0, obj_name, OBJPROP_TEXT, trend_text);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);

    // 添加趋势详情标签（显示关键结构点信息）
    string detail_obj = "SMC_TrendDetail";
    string detail_text = "";

    // 统计当前结构点
    int hh_count = 0, hl_count = 0, lh_count = 0, ll_count = 0;
    for(int i = 0; i < swing_count; i++) {
        if(!swing_points[i].is_broken) {
            switch(swing_points[i].structure_type) {
                case 0: hh_count++; break;
                case 1: hl_count++; break;
                case 2: lh_count++; break;
                case 3: ll_count++; break;
            }
        }
    }

    detail_text = "HH:" + IntegerToString(hh_count) + " HL:" + IntegerToString(hl_count) +
                  " LH:" + IntegerToString(lh_count) + " LL:" + IntegerToString(ll_count);

    if(ObjectFind(0, detail_obj) < 0) {
        ObjectCreate(0, detail_obj, OBJ_LABEL, 0, 0, 0);
    }

    ObjectSetInteger(0, detail_obj, OBJPROP_CORNER, TrendIndicator_Corner);
    ObjectSetInteger(0, detail_obj, OBJPROP_XDISTANCE, TrendIndicator_XOffset);
    ObjectSetInteger(0, detail_obj, OBJPROP_YDISTANCE, TrendIndicator_YOffset + TrendIndicator_FontSize + 5);
    ObjectSetInteger(0, detail_obj, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, detail_obj, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, detail_obj, OBJPROP_FONT, "Arial");
    ObjectSetString(0, detail_obj, OBJPROP_TEXT, detail_text);
    ObjectSetInteger(0, detail_obj, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, detail_obj, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| V1.53新增：清理趋势指示器对象                                      |
//+------------------------------------------------------------------+
void CleanupTrendIndicator()
{
    string obj_name = "SMC_TrendIndicator";
    string detail_obj = "SMC_TrendDetail";

    if(ObjectFind(0, obj_name) >= 0) {
        ObjectDelete(0, obj_name);
    }
    if(ObjectFind(0, detail_obj) >= 0) {
        ObjectDelete(0, detail_obj);
    }
}

//+------------------------------------------------------------------+
//| 绘制分型标记                                                      |
//+------------------------------------------------------------------+
void DrawFractalMarker(const FractalPoint& fractal)
{
    string obj_name = "SMC_ChanFractal_" + (fractal.is_top ? "Top_" : "Bottom_") +
                      IntegerToString(fractal.time);

    // 删除旧对象
    if(ObjectFind(0, obj_name) >= 0) {
        ObjectDelete(0, obj_name);
    }

    // 确定标记代码和颜色
    int arrow_code;
    color arrow_color;
    double price_offset = iATR(Symbol(), Period(), AtrPeriod, 0) * 0.3;
    double price;

    if(fractal.is_top) {
        arrow_code = 218; // 向下箭头
        arrow_color = TopFractalColor;
        price = fractal.price + price_offset;
    } else {
        arrow_code = 217; // 向上箭头
        arrow_color = BottomFractalColor;
        price = fractal.price - price_offset;
    }

    // 创建箭头对象
    if(!ObjectCreate(0, obj_name, OBJ_ARROW, 0, fractal.time, price)) {
        return;
    }

    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, arrow_code);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, arrow_color);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| 清理缠论分型对象                                                  |
//+------------------------------------------------------------------+
void CleanupChanFractalObjects()
{
    for(int i = ObjectsTotal() - 1; i >= 0; i--) {
        string obj_name = ObjectName(i);
        if(StringFind(obj_name, "SMC_ChanFractal") == 0) {
            ObjectDelete(0, obj_name);
        }
    }
}

//+------------------------------------------------------------------+
//| 绘制虚拟笔（从最后摆点到当前极值）                                |
//+------------------------------------------------------------------+
void DrawVirtualStroke()
{
    string obj_name = "SMC_VirtualStroke";

    // 删除旧的虚拟笔
    if(ObjectFind(0, obj_name) >= 0) {
        ObjectDelete(0, obj_name);
    }

    // 检查是否有足够的摆点
    if(swing_count < 1) return;

    // 获取最后一个摆点
    SwingPoint last_sp = swing_points[swing_count - 1];

    // 从最后摆点到当前K线，寻找极值点
    double extreme_price = 0;
    int extreme_bar = 0;
    datetime extreme_time = 0;
    bool found = false;

    if(last_sp.is_high) {
        // 最后是高点，寻找之后的最低点
        extreme_price = DBL_MAX;
        for(int i = 0; i < last_sp.bar_index; i++) {
            if(Low[i] < extreme_price) {
                extreme_price = Low[i];
                extreme_bar = i;
                extreme_time = Time[i];
                found = true;
            }
        }
        // 检查是否形成有效的下跌虚拟笔
        if(!found || extreme_price >= last_sp.price) return;
    } else {
        // 最后是低点，寻找之后的最高点
        extreme_price = -DBL_MAX;
        for(int i = 0; i < last_sp.bar_index; i++) {
            if(High[i] > extreme_price) {
                extreme_price = High[i];
                extreme_bar = i;
                extreme_time = Time[i];
                found = true;
            }
        }
        // 检查是否形成有效的上涨虚拟笔
        if(!found || extreme_price <= last_sp.price) return;
    }

    // 可选：检查最小K线数
    int bar_count = MathAbs(extreme_bar - last_sp.bar_index);
    if(bar_count < MinStrokeBars) return;

    // 可选：检查最小幅度
    if(MinStrokeATR > 0) {
        double current_atr = iATR(Symbol(), Period(), AtrPeriod, 0);
        double amplitude = MathAbs(extreme_price - last_sp.price);
        if(current_atr > 0 && amplitude < MinStrokeATR * current_atr) return;
    }

    // 创建虚拟笔（虚线）
    datetime start_time = Time[last_sp.bar_index];
    double start_price = last_sp.price;

    if(!ObjectCreate(0, obj_name, OBJ_TREND, 0,
                     start_time, start_price,
                     extreme_time, extreme_price)) {
        return;
    }

    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, VirtualStrokeColor);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DOT);  // 虚线
    ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
}


//+------------------------------------------------------------------+
//| V1.55新增：更新虚拟摆点（每个tick调用）                            |
//| V1.66扩展：支持HL/LH作为最后摆点时延伸至未确认极值                  |
//| 场景：最后摆点为HL，当前K线最低5016远低于HL，但因需5根反向K线确认   |
//|       最低点尚未成为摆点。缠论要求应连接到真实极值，故将未确认的    |
//|       最低/最高点作为虚拟摆点延伸，忽略摆点确认要求。              |
//+------------------------------------------------------------------+
void UpdateVirtualSwingPoint(const double &high[], const double &low[], int rates_total)
{
    g_virtual_swing_active = false;
    g_virtual_swing_add_mode = false;
    
    if(!EnableVirtualSwingExtension) return;
    if(swing_count < 1) return;
    
    // 获取最后一个确认的摆点
    SwingPoint last_sp = swing_points[swing_count - 1];
    
    // V1.66：支持四种类型 0=HH, 1=HL, 2=LH, 3=LL
    // HH/LL: 延伸至更高/更低极值（原逻辑）
    // HL: 延伸至更低低点(VLL)，解决"最后是HL但当前最低未确认"的问题
    // LH: 延伸至更高高点(VHH)，解决"最后是LH但当前最高未确认"的问题
    if(last_sp.structure_type < 0 || last_sp.structure_type > 3) return;
    
    int search_start = last_sp.bar_index - 1;  // 从最后摆点的下一根K线开始搜索
    if(search_start < 0) search_start = 0;
    
    // 高点类型(0=HH, 2=LH)：找VHH（更高高点）
    if(last_sp.structure_type == 0 || last_sp.structure_type == 2) {
        double max_high = -DBL_MAX;
        int max_bar = -1;
        for(int i = search_start; i >= 0; i--) {
            if(i < ArraySize(high) && high[i] > max_high) {
                max_high = high[i];
                max_bar = i;
            }
        }
        if(max_high > last_sp.price) {
            g_virtual_swing_active = true;
            g_virtual_swing_add_mode = (last_sp.structure_type == 2); // LH时追加
            g_virtual_swing_bar = max_bar;
            g_virtual_swing_price = max_high;
            g_virtual_swing_is_high = true;
            g_virtual_swing_type = 10; // VHH
        }
    }
    // 低点类型(1=HL, 3=LL)：找VLL（更低低点）
    else if(last_sp.structure_type == 1 || last_sp.structure_type == 3) {
        double min_low = DBL_MAX;
        int min_bar = -1;
        for(int i = search_start; i >= 0; i--) {
            if(i < ArraySize(low) && low[i] < min_low) {
                min_low = low[i];
                min_bar = i;
            }
        }
        if(min_low < last_sp.price) {
            g_virtual_swing_active = true;
            g_virtual_swing_add_mode = (last_sp.structure_type == 1); // HL时追加
            g_virtual_swing_bar = min_bar;
            g_virtual_swing_price = min_low;
            g_virtual_swing_is_high = false;
            g_virtual_swing_type = 13; // VLL
        }
    }
    
    // V1.55: 如果虚拟摆点激活，强制清除冲突的虚拟笔对象
    if(g_virtual_swing_active) {
        if(ObjectFind(0, "SMC_VirtualStroke") >= 0) {
            ObjectDelete(0, "SMC_VirtualStroke");
        }
    }
}

//+------------------------------------------------------------------+
//| V1.54新增：更新临时极点（每tick调用）                              |
//| 解决最后摆点更新不及时的问题                                       |
//+------------------------------------------------------------------+
void UpdateTemporaryExtremes(const double &high[], const double &low[], int rates_total)
{
    if(!ShowTemporaryExtreme) return;
    if(swing_count < 1) return;

    // 获取最后一个确认的摆点
    SwingPoint last_sp = swing_points[swing_count - 1];
    int search_start = last_sp.bar_index - 1;  // 从最后摆点的下一根K线开始搜索

    // 边界检查
    if(search_start < 0) search_start = 0;

    // 重置临时极点
    g_temp_high_bar = -1;
    g_temp_high_price = -DBL_MAX;
    g_temp_low_bar = -1;
    g_temp_low_price = DBL_MAX;

    // 根据最后摆点类型决定搜索方向
    if(last_sp.is_high) {
        // 最后是高点，搜索之后的最低点作为临时低点
        for(int i = search_start; i >= 0; i--) {
            if(i < ArraySize(low) && low[i] < g_temp_low_price) {
                g_temp_low_price = low[i];
                g_temp_low_bar = i;
            }
        }
        // 同时搜索是否有更高的高点（可能形成新的高点）
        for(int i = search_start; i >= 0; i--) {
            if(i < ArraySize(high) && high[i] > g_temp_high_price) {
                g_temp_high_price = high[i];
                g_temp_high_bar = i;
            }
        }
        // 如果新高点高于最后摆点，则临时高点有效，临时低点无效
        if(g_temp_high_price > last_sp.price) {
            g_temp_low_bar = -1;  // 清除临时低点
            g_temp_low_price = DBL_MAX;
        } else {
            g_temp_high_bar = -1;  // 清除临时高点
            g_temp_high_price = -DBL_MAX;
        }
    } else {
        // 最后是低点，搜索之后的最高点作为临时高点
        for(int i = search_start; i >= 0; i--) {
            if(i < ArraySize(high) && high[i] > g_temp_high_price) {
                g_temp_high_price = high[i];
                g_temp_high_bar = i;
            }
        }
        // 同时搜索是否有更低的低点（可能形成新的低点）
        for(int i = search_start; i >= 0; i--) {
            if(i < ArraySize(low) && low[i] < g_temp_low_price) {
                g_temp_low_price = low[i];
                g_temp_low_bar = i;
            }
        }
        // 如果新低点低于最后摆点，则临时低点有效，临时高点无效
        if(g_temp_low_price < last_sp.price) {
            g_temp_high_bar = -1;  // 清除临时高点
            g_temp_high_price = -DBL_MAX;
        } else {
            g_temp_low_bar = -1;  // 清除临时低点
            g_temp_low_price = DBL_MAX;
        }
    }

    // 记录最后确认的摆点位置
    g_last_confirmed_high_bar = -1;
    g_last_confirmed_low_bar = -1;
    for(int i = swing_count - 1; i >= 0; i--) {
        if(swing_points[i].is_high && g_last_confirmed_high_bar < 0) {
            g_last_confirmed_high_bar = swing_points[i].bar_index;
        }
        if(!swing_points[i].is_high && g_last_confirmed_low_bar < 0) {
            g_last_confirmed_low_bar = swing_points[i].bar_index;
        }
        if(g_last_confirmed_high_bar >= 0 && g_last_confirmed_low_bar >= 0) break;
    }
}

//+------------------------------------------------------------------+
//| V1.54新增：绘制临时极点标记                                        |
//+------------------------------------------------------------------+
void DrawTemporaryExtremes()
{
    if(!ShowTemporaryExtreme) return;

    // 清理旧的临时极点对象
    CleanupTemporaryExtremes();

    double atr_offset = iATR(Symbol(), Period(), AtrPeriod, 0) * 0.5;

    // 绘制临时高点
    if(g_temp_high_bar >= 0 && g_temp_high_price > -DBL_MAX) {
        string obj_name = "SMC_TempExtreme_High";
        datetime obj_time = Time[g_temp_high_bar];
        double obj_price = g_temp_high_price + atr_offset;

        if(ObjectFind(0, obj_name) < 0) {
            ObjectCreate(0, obj_name, OBJ_ARROW, 0, obj_time, obj_price);
        } else {
            ObjectMove(0, obj_name, 0, obj_time, obj_price);
        }

        ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 218);  // 向下箭头
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, TempExtremeHigh_Color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, TempExtremeArrowSize);
        ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
        ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);

        // 添加文字标签
        string label_name = "SMC_TempExtreme_High_Label";
        if(ObjectFind(0, label_name) < 0) {
            ObjectCreate(0, label_name, OBJ_TEXT, 0, obj_time, obj_price + atr_offset * 0.3);
        } else {
            ObjectMove(0, label_name, 0, obj_time, obj_price + atr_offset * 0.3);
        }
        ObjectSetString(0, label_name, OBJPROP_TEXT, "TH");
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, TempExtremeHigh_Color);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LOWER);
        ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
    }

    // 绘制临时低点
    if(g_temp_low_bar >= 0 && g_temp_low_price < DBL_MAX) {
        string obj_name = "SMC_TempExtreme_Low";
        datetime obj_time = Time[g_temp_low_bar];
        double obj_price = g_temp_low_price - atr_offset;

        if(ObjectFind(0, obj_name) < 0) {
            ObjectCreate(0, obj_name, OBJ_ARROW, 0, obj_time, obj_price);
        } else {
            ObjectMove(0, obj_name, 0, obj_time, obj_price);
        }

        ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 217);  // 向上箭头
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, TempExtremeLow_Color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, TempExtremeArrowSize);
        ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
        ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);

        // 添加文字标签
        string label_name = "SMC_TempExtreme_Low_Label";
        if(ObjectFind(0, label_name) < 0) {
            ObjectCreate(0, label_name, OBJ_TEXT, 0, obj_time, obj_price - atr_offset * 0.3);
        } else {
            ObjectMove(0, label_name, 0, obj_time, obj_price - atr_offset * 0.3);
        }
        ObjectSetString(0, label_name, OBJPROP_TEXT, "TL");
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, TempExtremeLow_Color);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_UPPER);
        ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
    }
}

//+------------------------------------------------------------------+
//| V1.54新增：清理临时极点对象                                        |
//+------------------------------------------------------------------+
void CleanupTemporaryExtremes()
{
    string objects[] = {
        "SMC_TempExtreme_High",
        "SMC_TempExtreme_Low",
        "SMC_TempExtreme_High_Label",
        "SMC_TempExtreme_Low_Label"
    };

    for(int i = 0; i < ArraySize(objects); i++) {
        if(ObjectFind(0, objects[i]) >= 0) {
            ObjectDelete(0, objects[i]);
        }
    }
}


//+------------------------------------------------------------------+
//| 指标反初始化函数                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 清除所有SMC相关的图形对象
    for(int i = ObjectsTotal() - 1; i >= 0; i--) {
        string obj_name = ObjectName(i);
        if(StringFind(obj_name, "SMC_") == 0) {
            ObjectDelete(obj_name);
        }
    }
    
    // 同时确保移除未授权提示对象
    string warning_obj = "AUTH_WARNING";
    if(ObjectFind(0, warning_obj) >= 0) {
        ObjectDelete(0, warning_obj);
    }
    
    // 停止定时器
    EventKillTimer();
    
    // 清除注释
    Comment("");
    
    // 根据卸载原因显示信息
    switch(reason) {
        case REASON_REMOVE:
            Print("SMC指标已被移除");
            break;
        case REASON_RECOMPILE:
            Print("SMC指标重新编译");
            break;
        case REASON_CHARTCHANGE:
            Print("SMC指标因图表变化而卸载");
            break;
        default:
            Print("SMC指标已卸载，原因代码: ", reason);
            break;
    }
}
//+------------------------------------------------------------------+
//| 定时器处理函数                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    // 处理授权重试机制
    if(g_auth_retry_active) {
        ProcessAuthorizationRetry();
        return; // 重试期间不执行其他操作
    }
    
    // 授权检查：如果未授权，则不执行任何操作
    if (!g_is_authorized) {
        return;
    }

    // 定期重新验证授权（例如每10分钟）
    static datetime last_recheck = 0;
    if(RecheckInterval > 0 && TimeCurrent() - last_recheck > RecheckInterval * 60) {
        if(!CheckAuthorization()) {
            ShowAuthorizationFailure();
            g_is_authorized = false; // 标记为未授权
            ObjectsDeleteAll(0, "SMC_"); // 清理图形对象
            Comment("授权已失效，指标已停用。");
            return; // 停止后续操作
        }
        last_recheck = TimeCurrent();
    }
    
    // 1秒心跳：若版本未绘制或处于K线完成后的5秒窗口内，则主动重绘对象
    DrawGraphicalObjects();
}
//+------------------------------------------------------------------+