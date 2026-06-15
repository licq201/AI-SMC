//+------------------------------------------------------------------+
//| TestReadOBQuality.mq4                                            |
//| 验证 SMC 指标的 OB_Quality(索引9) 可被 EA/脚本经 iCustom 读取     |
//| 用法：编译后拖到 XAUUSD 图表(指标须已挂在同图表或可被加载)        |
//+------------------------------------------------------------------+
#property strict
#property show_inputs

input int ScanBars = 500;   // 向左扫描的K线数

void OnStart()
{
    string ind = "SMC_OrderFlow_Indicator_v1.70_zig";
    int found = 0;
    int limit = MathMin(ScanBars, Bars);

    for(int shift = 0; shift < limit; shift++) {
        // 不传 input 参数：iCustom 使用指标默认参数；9=OB_Quality buffer 索引
        double q = iCustom(Symbol(), Period(), ind, 9, shift);
        if(q != EMPTY_VALUE) {
            found++;
            Print("OB_Quality @ shift ", shift, " (", TimeToString(Time[shift]),
                  ") = ", DoubleToString(q, 2));
        }
    }
    Print("TestReadOBQuality: 在 ", limit, " 根K线内发现 ", found,
          " 个OB质量分锚点。", (found > 0 ? "通道可读 ✓" : "未读到，检查指标是否已加载/EnableOBLifecycle"));
}
