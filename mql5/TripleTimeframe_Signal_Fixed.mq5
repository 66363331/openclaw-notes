//+------------------------------------------------------------------+
//| 三重周期交易信号指标 - 修复版                                     |
//| Triple Timeframe Signal Indicator - Fixed                       |
//| H1/M15 EMA趋势 + M3威科夫量价进场                                |
//+------------------------------------------------------------------+
#property copyright "Jassica for HoneyRay"
#property link      ""
#property version   "2.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//--- 画图设置
#property indicator_type1   DRAW_ARROW
#property indicator_type2   DRAW_ARROW
#property indicator_type3   DRAW_NONE
#property indicator_type4   DRAW_NONE

#property indicator_color1  clrLime
#property indicator_color2  clrRed
#property indicator_color3  clrYellow
#property indicator_color4  clrDodgerBlue

#property indicator_label1  "Buy Signal"
#property indicator_label2  "Sell Signal"
#property indicator_label3  "Trend Strength"
#property indicator_label4  "Volume Confirm"

//+------------------------------------------------------------------+
//| 枚举定义                                                          |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_NONE = 0,   // 无趋势
   TREND_BULL = 1,   // 多头
   TREND_BEAR = -1   // 空头
};

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input group "=== H1 & M15 EMA 设置 ==="
input int      Inp_EMA_Fast     = 20;       // 快线EMA
input int      Inp_EMA_Mid      = 50;       // 中线EMA
input int      Inp_EMA_Slow     = 200;      // 慢线EMA

input group "=== M3 威科夫量价设置 ==="
input int      Inp_VolumeLookback = 20;     // 成交量回看周期
input double   Inp_VolumeRatio    = 1.5;    // 放量倍数(>1.5倍)
input double   Inp_BodyRatio      = 0.6;    // 实体占比(>60%)
input int      Inp_SignalCooldown = 5;      // 信号冷却( bars)

input group "=== 提醒设置 ==="
input bool     Inp_AlertEnabled       = true;   // 启用弹窗提醒
input bool     Inp_SendNotification   = true;   // 发送手机推送
input bool     Inp_PlaySound          = true;   // 播放声音
input string   Inp_SoundFileBuy       = "buy.wav";   // 做多声音
input string   Inp_SoundFileSell      = "sell.wav";  // 做空声音

input group "=== 显示设置 ==="
input bool     Inp_ShowTrendLine = true;    // 显示趋势强度线
input bool     Inp_ShowVolumeLine= true;    // 显示成交量确认线

//+------------------------------------------------------------------+
//| 指标缓冲区                                                        |
//+------------------------------------------------------------------+
double BufferBuy[];       // 做多信号
double BufferSell[];      // 做空信号
double BufferTrend[];     // 趋势强度
double BufferVolume[];    // 成交量确认度

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
datetime g_LastSignalTime = 0;  // 上次信号时间
int g_SignalCounter = 0;        // 信号计数器

// 用于存储EMA句柄
int g_HandleEMAFastH1 = INVALID_HANDLE;
int g_HandleEMAMidH1 = INVALID_HANDLE;
int g_HandleEMASlowH1 = INVALID_HANDLE;
int g_HandleEMAFastM15 = INVALID_HANDLE;
int g_HandleEMAMidM15 = INVALID_HANDLE;
int g_HandleEMASlowM15 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| 自定义指标初始化函数                                               |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 设置指标缓冲区
   SetIndexBuffer(0, BufferBuy, INDICATOR_DATA);
   SetIndexBuffer(1, BufferSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufferTrend, INDICATOR_DATA);
   SetIndexBuffer(3, BufferVolume, INDICATOR_DATA);
   
   //--- 设置箭头
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // 向上箭头
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // 向下箭头
   
   //--- 设置箭头大小
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -15);
   
   //--- 设置空值
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   //--- 指标名称
   IndicatorSetString(INDICATOR_SHORTNAME, "TripleTF Signal");
   
   //--- 创建EMA指标句柄
   g_HandleEMAFastH1 = iMA(_Symbol, PERIOD_H1, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleEMAMidH1 = iMA(_Symbol, PERIOD_H1, Inp_EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleEMASlowH1 = iMA(_Symbol, PERIOD_H1, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   
   g_HandleEMAFastM15 = iMA(_Symbol, PERIOD_M15, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleEMAMidM15 = iMA(_Symbol, PERIOD_M15, Inp_EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleEMASlowM15 = iMA(_Symbol, PERIOD_M15, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   
   //--- 检查句柄有效性
   if(g_HandleEMAFastH1 == INVALID_HANDLE || g_HandleEMAMidH1 == INVALID_HANDLE || 
      g_HandleEMASlowH1 == INVALID_HANDLE || g_HandleEMAFastM15 == INVALID_HANDLE ||
      g_HandleEMAMidM15 == INVALID_HANDLE || g_HandleEMASlowM15 == INVALID_HANDLE)
   {
      Print("错误: 无法创建EMA指标句柄");
      return(INIT_FAILED);
   }
   
   Print("三重周期信号指标初始化完成");
   Print("H1/M15 EMA趋势 + M3威科夫量价");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 自定义指标反初始化函数                                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- 释放指标句柄
   IndicatorRelease(g_HandleEMAFastH1);
   IndicatorRelease(g_HandleEMAMidH1);
   IndicatorRelease(g_HandleEMASlowH1);
   IndicatorRelease(g_HandleEMAFastM15);
   IndicatorRelease(g_HandleEMAMidM15);
   IndicatorRelease(g_HandleEMASlowM15);
   
   Print("指标已卸载，原因: ", reason);
}

//+------------------------------------------------------------------+
//| 获取EMA趋势方向（使用句柄）                                        |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetEMAsTrend(int handleFast, int handleMid, int handleSlow)
{
   double emaFast[1], emaMid[1], emaSlow[1], close[1];
   
   //--- 复制数据
   if(CopyBuffer(handleFast, 0, 0, 1, emaFast) < 1) return TREND_NONE;
   if(CopyBuffer(handleMid, 0, 0, 1, emaMid) < 1) return TREND_NONE;
   if(CopyBuffer(handleSlow, 0, 0, 1, emaSlow) < 1) return TREND_NONE;
   if(CopyClose(_Symbol, PERIOD_M3, 0, 1, close) < 1) return TREND_NONE;
   
   //--- 检查数据有效性
   if(emaFast[0] == 0 || emaMid[0] == 0 || emaSlow[0] == 0)
      return TREND_NONE;
   
   //--- 多头排列（多头趋势）
   if(close[0] > emaFast[0] && emaFast[0] > emaMid[0] && emaMid[0] > emaSlow[0])
      return TREND_BULL;
   
   //--- 空头排列（空头趋势）
   if(close[0] < emaFast[0] && emaFast[0] < emaMid[0] && emaMid[0] < emaSlow[0])
      return TREND_BEAR;
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| 威科夫量价分析（M3周期）                                           |
//+------------------------------------------------------------------+
bool WyckoffVolumeAnalysis(bool isBull, double &strength)
{
   //--- 获取成交量数据
   long volume[];
   ArraySetAsSeries(volume, true);
   
   if(CopyTickVolume(_Symbol, PERIOD_M3, 0, Inp_VolumeLookback, volume) < Inp_VolumeLookback)
      return false;
   
   //--- 计算平均成交量（不包括当前bar）
   double avgVolume = 0;
   for(int i = 1; i < Inp_VolumeLookback; i++)
      avgVolume += (double)volume[i];
   avgVolume /= (Inp_VolumeLookback - 1);
   
   //--- 当前成交量
   double currVolume = (double)volume[0];
   
   //--- 放量确认（当前成交量 > 平均 * 倍数）
   bool volumeConfirmed = (currVolume > avgVolume * Inp_VolumeRatio);
   
   //--- 获取价格数据（M3周期）
   double m3Open[], m3High[], m3Low[], m3Close[];
   ArraySetAsSeries(m3Open, true);
   ArraySetAsSeries(m3High, true);
   ArraySetAsSeries(m3Low, true);
   ArraySetAsSeries(m3Close, true);
   
   if(CopyOpen(_Symbol, PERIOD_M3, 0, 1, m3Open) < 1) return false;
   if(CopyHigh(_Symbol, PERIOD_M3, 0, 1, m3High) < 1) return false;
   if(CopyLow(_Symbol, PERIOD_M3, 0, 1, m3Low) < 1) return false;
   if(CopyClose(_Symbol, PERIOD_M3, 0, 1, m3Close) < 1) return false;
   
   double range = m3High[0] - m3Low[0];
   double body = MathAbs(m3Close[0] - m3Open[0]);
   
   if(range == 0) return false;
   
   double volumeFactor = currVolume / avgVolume;
   double bodyFactor = body / range;
   strength = volumeFactor * bodyFactor;
   
   //=========================================
   // 威科夫做多逻辑
   //=========================================
   if(isBull)
   {
      // 1. 大阳线（实体占K线60%以上）
      bool strongBody = (m3Close[0] > m3Open[0]) && (body / range > Inp_BodyRatio);
      
      // 2. 收盘在高位（> 60%范围）
      bool strongClose = (m3Close[0] - m3Low[0]) / range > Inp_BodyRatio;
      
      // 3. 弹簧效应（下影线 > 实体，测试支撑后反弹）
      double lowerShadow = MathMin(m3Open[0], m3Close[0]) - m3Low[0];
      bool spring = lowerShadow > body * 0.5;
      
      return (strongBody && strongClose && volumeConfirmed);
   }
   //=========================================
   // 威科夫做空逻辑
   //=========================================
   else
   {
      // 1. 大阴线（实体占K线60%以上）
      bool strongBody = (m3Close[0] < m3Open[0]) && (body / range > Inp_BodyRatio);
      
      // 2. 收盘在低位（< 40%范围）
      bool weakClose = (m3High[0] - m3Close[0]) / range > Inp_BodyRatio;
      
      // 3. 上推效应（上影线 > 实体，测试阻力后回落）
      double upperShadow = m3High[0] - MathMax(m3Open[0], m3Close[0]);
      bool upthrust = upperShadow > body * 0.5;
      
      return (strongBody && weakClose && volumeConfirmed);
   }
}

//+------------------------------------------------------------------+
//| 检查信号冷却                                                      |
//+------------------------------------------------------------------+
bool IsSignalCooldown(datetime currentTime)
{
   if(g_LastSignalTime == 0)
      return true;
   
   //--- 计算距离上次信号的bar数
   int barsSinceLast = iBarShift(_Symbol, PERIOD_M3, g_LastSignalTime);
   
   return (barsSinceLast >= Inp_SignalCooldown || barsSinceLast < 0);
}

//+------------------------------------------------------------------+
//| 发送信号提醒                                                      |
//+------------------------------------------------------------------+
void SendSignalAlert(string direction, double strength, double price)
{
   string symbol = _Symbol;
   string timeframe = "M3";
   
   //--- 构造消息
   string message = StringFormat(
      "【%s】%s %s 信号\n" +
      "价格: %.2f\n" +
      "强度: %.2f\n" +
      "趋势: H1/M15 EMA排列确认",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      symbol,
      direction,
      price,
      strength
   );
   
   //--- 弹窗提醒
   if(Inp_AlertEnabled)
   {
      Alert(message);
   }
   
   //--- 手机推送
   if(Inp_SendNotification)
   {
      SendNotification(message);
   }
   
   //--- 声音提醒
   if(Inp_PlaySound)
   {
      if(direction == "做多")
         PlaySound(Inp_SoundFileBuy);
      else
         PlaySound(Inp_SoundFileSell);
   }
   
   //--- 记录到日志
   Print("信号触发: ", direction, " 强度=", strength, " 价格=", price);
}

//+------------------------------------------------------------------+
//| 自定义指标迭代函数                                                 |
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
   //--- 计算起始位置
   int start = prev_calculated == 0 ? 200 : prev_calculated - 1;
   
   //--- 主循环
   for(int i = start; i < rates_total; i++)
   {
      //--- 清空当前位置的值
      BufferBuy[i]    = EMPTY_VALUE;
      BufferSell[i]   = EMPTY_VALUE;
      BufferTrend[i]  = 0;
      BufferVolume[i] = 0;
      
      //=========================================
      // STEP 1: H1趋势判断
      //=========================================
      ENUM_TREND_DIRECTION h1Trend = GetEMAsTrend(g_HandleEMAFastH1, g_HandleEMAMidH1, g_HandleEMASlowH1);
      if(h1Trend == TREND_NONE)
         continue;
      
      //=========================================
      // STEP 2: M15趋势确认
      //=========================================
      ENUM_TREND_DIRECTION m15Trend = GetEMAsTrend(g_HandleEMAFastM15, g_HandleEMAMidM15, g_HandleEMASlowM15);
      if(m15Trend == TREND_NONE || m15Trend != h1Trend)
         continue;
      
      //=========================================
      // STEP 3: M3威科夫量价进场
      //=========================================
      datetime currentTime = time[i];
      
      //--- 检查信号冷却
      if(g_LastSignalTime != 0)
      {
         int barsSinceLast = iBarShift(_Symbol, PERIOD_M3, g_LastSignalTime);
         if(barsSinceLast < Inp_SignalCooldown && barsSinceLast >= 0)
            continue;
      }
      
      double strength = 0;
      
      //--- H1和M15都是多头，找M3做多信号
      if(h1Trend == TREND_BULL && m15Trend == TREND_BULL)
      {
         if(WyckoffVolumeAnalysis(true, strength))
         {
            BufferBuy[i] = low[i] - 20 * _Point;  // 箭头位置
            BufferTrend[i] = strength;
            BufferVolume[i] = strength;
            
            //--- 只在最新bar发送提醒
            if(i == rates_total - 1)
            {
               SendSignalAlert("做多", strength, close[i]);
               g_LastSignalTime = currentTime;
               g_SignalCounter++;
            }
         }
      }
      //--- H1和M15都是空头，找M3做空信号
      else if(h1Trend == TREND_BEAR && m15Trend == TREND_BEAR)
      {
         if(WyckoffVolumeAnalysis(false, strength))
         {
            BufferSell[i] = high[i] + 20 * _Point;  // 箭头位置
            BufferTrend[i] = -strength;
            BufferVolume[i] = strength;
            
            //--- 只在最新bar发送提醒
            if(i == rates_total - 1)
            {
               SendSignalAlert("做空", strength, close[i]);
               g_LastSignalTime = currentTime;
               g_SignalCounter++;
            }
         }
      }
   }
   
   //--- 返回
   return(rates_total);
}
//+------------------------------------------------------------------+
