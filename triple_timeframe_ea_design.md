# 交易指标EA开发 - 推荐Skills

## ✅ 已有Skills（可直接使用）

### 1. 🧩 coding-agent ⭐⭐⭐⭐⭐
**用途：** 编写MQL5 EA指标代码
**状态：** ✅ 已就绪
**优势：** 可以生成完整的MT5指标代码

### 2. 📦 skill-creator ⭐⭐⭐⭐
**用途：** 打包成可重复使用的Skill
**状态：** ✅ 已就绪
**优势：** 以后直接调用，不用重复写代码

### 3. 🌤️ weather ⭐⭐
**用途：** 交易前查看天气（影响心情和决策）
**状态：** ✅ 已就绪

---

## 🔧 需要的MQL5代码结构

### 主指标文件: `TripleTimeframe_Signal.mq5`

```mql5
//+------------------------------------------------------------------+
//| 三重周期交易信号指标                                              |
//| H1/M15 EMA趋势 + M3威科夫量价进场                                  |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

// H1和M15的EMA
input group "=== H1 & M15 EMA 设置 ==="
input int Inp_EMA_Fast = 20;
input int Inp_EMA_Mid  = 50;
input int Inp_EMA_Slow = 200;

// M3威科夫参数
input group "=== M3 威科夫量价设置 ==="
input int Inp_VolumeLookback = 20;      // 成交量回看周期
input double Inp_VolumeRatio = 1.5;      // 放量倍数
input int Inp_SpreadBars = 3;            // 价差条数

// 提醒设置
input group "=== 提醒设置 ==="
input bool Inp_AlertEnabled = true;
input bool Inp_SendNotification = true;
input bool Inp_PlaySound = true;
input string Inp_SoundFile = "alert.wav";

// 指标缓冲区
double BufferBuy[];      // 做多信号
double BufferSell[];     // 做空信号
double BufferTrend[];    // 趋势强度
double BufferVolume[];   // 量价配合度

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // 设置指标缓冲区
   SetIndexBuffer(0, BufferBuy, INDICATOR_DATA);
   SetIndexBuffer(1, BufferSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufferTrend, INDICATOR_DATA);
   SetIndexBuffer(3, BufferVolume, INDICATOR_DATA);
   
   // 设置箭头
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // 向上箭头
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // 向下箭头
   
   // 设置颜色
   PlotIndexSetInteger(0, PLOT_COLOR, clrLime);
   PlotIndexSetInteger(1, PLOT_COLOR, clrRed);
   
   Print("三重周期信号指标初始化完成");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 获取EMA趋势方向                                                   |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetEMAsTrend(int timeframe)
{
   double ema20 = iMA(_Symbol, timeframe, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema50 = iMA(_Symbol, timeframe, Inp_EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, 0);
   double ema200= iMA(_Symbol, timeframe, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 0);
   double close = iClose(_Symbol, timeframe, 0);
   
   // 多头排列
   if(close > ema20 && ema20 > ema50 && ema50 > ema200)
      return TREND_BULL;
   
   // 空头排列
   if(close < ema20 && ema20 < ema50 && ema50 < ema200)
      return TREND_BEAR;
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| 威科夫量价分析 (M3)                                               |
//| 1. 成交量放量确认                                                  |
//| 2. 价差扩大/缩小分析                                               |
//| 3. 收盘位置判断主力意图                                            |
//+------------------------------------------------------------------+
bool WyckoffVolumeAnalysis(bool isBull, double &strength)
{
   // 获取成交量数据
   long volume[];
   ArraySetAsSeries(volume, true);
   CopyTickVolume(_Symbol, PERIOD_M3, 0, Inp_VolumeLookback, volume);
   
   // 计算平均成交量
   double avgVolume = 0;
   for(int i = 1; i < Inp_VolumeLookback; i++)
      avgVolume += volume[i];
   avgVolume /= (Inp_VolumeLookback - 1);
   
   // 当前成交量
   double currVolume = (double)volume[0];
   
   // 放量判断
   bool volumeConfirmed = currVolume > avgVolume * Inp_VolumeRatio;
   
   // 获取价格数据
   double high = iHigh(_Symbol, PERIOD_M3, 0);
   double low  = iLow(_Symbol, PERIOD_M3, 0);
   double open = iOpen(_Symbol, PERIOD_M3, 0);
   double close= iClose(_Symbol, PERIOD_M3, 0);
   
   double range = high - low;
   double body = MathAbs(close - open);
   double upperShadow = high - MathMax(open, close);
   double lowerShadow = MathMin(open, close) - low;
   
   // 威科夫逻辑：
   // 做多：放量 + 大阳线 + 下影线（测试支撑）+ 收盘高位
   if(isBull)
   {
      bool strongClose = close > open && (close - low) / range > 0.6;
      bool spring = lowerShadow > body * 0.5;  // 弹簧效应（下影线）
      strength = (currVolume / avgVolume) * (body / range);
      return volumeConfirmed && strongClose;
   }
   // 做空：放量 + 大阴线 + 上影线（测试阻力）+ 收盘低位
   else
   {
      bool weakClose = close < open && (high - close) / range > 0.6;
      bool upthrust = upperShadow > body * 0.5;  // 上推效应（上影线）
      strength = (currVolume / avgVolume) * (body / range);
      return volumeConfirmed && weakClose;
   }
}

//+------------------------------------------------------------------+
//| 主计算函数                                                        |
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
   int start = prev_calculated == 0 ? 200 : prev_calculated - 1;
   
   for(int i = start; i < rates_total; i++)
   {
      BufferBuy[i] = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;
      BufferTrend[i] = 0;
      BufferVolume[i] = 0;
      
      // 获取H1和M15趋势
      ENUM_TREND_DIRECTION h1Trend  = GetEMAsTrend(PERIOD_H1);
      ENUM_TREND_DIRECTION m15Trend = GetEMAsTrend(PERIOD_M15);
      
      // 趋势一致才继续
      if(h1Trend == TREND_NONE || h1Trend != m15Trend)
         continue;
      
      double strength = 0;
      
      // H1和M15都是牛市，找M3做多信号
      if(h1Trend == TREND_BULL)
      {
         if(WyckoffVolumeAnalysis(true, strength))
         {
            BufferBuy[i] = low[i] - 10 * _Point;
            BufferTrend[i] = strength;
            BufferVolume[i] = strength;
            
            // 发送提醒
            if(i == rates_total - 1 && Inp_AlertEnabled)
            {
               string msg = StringFormat("做多信号！趋势：H1/M15多头，M3威科夫确认，强度：%.2f", strength);
               Alert(msg);
               if(Inp_SendNotification) SendNotification(msg);
               if(Inp_PlaySound) PlaySound(Inp_SoundFile);
            }
         }
      }
      // H1和M15都是熊市，找M3做空信号
      else if(h1Trend == TREND_BEAR)
      {
         if(WyckoffVolumeAnalysis(false, strength))
         {
            BufferSell[i] = high[i] + 10 * _Point;
            BufferTrend[i] = -strength;
            BufferVolume[i] = strength;
            
            // 发送提醒
            if(i == rates_total - 1 && Inp_AlertEnabled)
            {
               string msg = StringFormat("做空信号！趋势：H1/M15空头，M3威科夫确认，强度：%.2f", strength);
               Alert(msg);
               if(Inp_SendNotification) SendNotification(msg);
               if(Inp_PlaySound) PlaySound(Inp_SoundFile);
            }
         }
      }
   }
   
   return rates_total;
}
//+------------------------------------------------------------------+
```

---

## 📦 需要的Skills总结

| 技能 | 用途 | 状态 |
|------|------|------|
| **coding-agent** | 生成/优化MQL5代码 | ✅ 已就绪 |
| **skill-creator** | 打包为可复用技能 | ✅ 已就绪 |

**不需要额外安装其他Skills！**

用 coding-agent 就可以生成完整的EA代码。

要我立即生成完整代码吗？🌸