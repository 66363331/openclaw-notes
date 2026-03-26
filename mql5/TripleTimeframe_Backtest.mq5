//+------------------------------------------------------------------+
//| 三重周期EA - 回测分析脚本                                         |
//| Triple Timeframe EA - Backtest Analysis Script                  |
//| 用于分析历史信号质量和优化参数                                     |
//+------------------------------------------------------------------+
#property copyright "Jassica for HoneyRay"
#property version   "1.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 4

#include "WyckoffPatterns.mqh"

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input group "=== 回测分析设置 ==="
input int      Inp_TestPeriod    = 500;       // 回测K线数量
input bool     Inp_SaveToFile    = true;      // 保存结果到文件
input string   Inp_OutputFile    = "backtest_results.csv"; // 输出文件名

input group "=== 策略参数 ==="
input int      Inp_EMA_Fast      = 20;
input int      Inp_EMA_Mid       = 50;
input int      Inp_EMA_Slow      = 200;
input int      Inp_VolumeLookback= 20;
input double   Inp_VolumeRatio   = 1.5;
input double   Inp_BodyRatio     = 0.6;

//+------------------------------------------------------------------+
//| 指标缓冲区                                                        |
//+------------------------------------------------------------------+
double BufferSignal[];      // 信号记录
double BufferEMAScore[];    // EMA趋势强度
double BufferVolumeScore[]; // 成交量评分
double BufferPattern[];     // 形态类型

//+------------------------------------------------------------------+
//| 回测数据结构                                                      |
//+------------------------------------------------------------------+
struct SignalRecord
{
   datetime time;           // 信号时间
   int      barIndex;       // K线索引
   bool     isBullish;      // 是否看涨
   string   pattern;        // 形态名称
   double   strength;       // 信号强度
   double   entryPrice;     // 入场价格
   double   emaScore;       // EMA趋势评分
   double   volumeScore;    // 成交量评分
   double   result;         // 结果（正向/负向点数）
};

SignalRecord g_Signals[];
int g_SignalCount = 0;

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferSignal, INDICATOR_DATA);
   SetIndexBuffer(1, BufferEMAScore, INDICATOR_DATA);
   SetIndexBuffer(2, BufferVolumeScore, INDICATOR_DATA);
   SetIndexBuffer(3, BufferPattern, INDICATOR_DATA);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "Backtest Analysis");
   
   ArrayResize(g_Signals, Inp_TestPeriod);
   
   Print("回测分析启动");
   Print("回测周期: ", Inp_TestPeriod, " 根K线");
   
   return(INIT_SUCCEEDED);
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
   //--- 只在初始化时执行一次完整回测
   if(prev_calculated == 0)
   {
      RunBacktest(rates_total, time, open, high, low, close);
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| 执行回测                                                          |
//+------------------------------------------------------------------+
void RunBacktest(int rates_total, const datetime &time[], 
                 const double &open[], const double &high[], 
                 const double &low[], const double &close[])
{
   Print("开始回测分析...");
   
   int startBar = MathMin(Inp_TestPeriod, rates_total - 50);
   
   for(int i = startBar; i >= 0; i--)
   {
      //--- 检查H1趋势
      ENUM_TREND_DIRECTION h1Trend = GetTrendByIndex(PERIOD_H1, i);
      if(h1Trend == TREND_NONE) continue;
      
      //--- 检查M15趋势
      ENUM_TREND_DIRECTION m15Trend = GetTrendByIndex(PERIOD_M15, i);
      if(m15Trend != h1Trend) continue;
      
      //--- 获取M3数据
      double m3Open = iOpen(_Symbol, PERIOD_M3, i);
      double m3High = iHigh(_Symbol, PERIOD_M3, i);
      double m3Low  = iLow(_Symbol, PERIOD_M3, i);
      double m3Close= iClose(_Symbol, PERIOD_M3, i);
      
      //--- 威科夫分析
      double strength = 0;
      string patternName = "";
      bool isBullish = false;
      
      if(h1Trend == TREND_BULL)
      {
         if(AnalyzeBullishPattern(i, strength, patternName))
         {
            isBullish = true;
            RecordSignal(time[i], i, isBullish, patternName, strength, 
                        m3Close, CalculateEMAScore(i), CalculateVolumeScore(i));
         }
      }
      else
      {
         if(AnalyzeBearishPattern(i, strength, patternName))
         {
            isBullish = false;
            RecordSignal(time[i], i, isBullish, patternName, strength,
                        m3Close, CalculateEMAScore(i), CalculateVolumeScore(i));
         }
      }
   }
   
   //--- 分析结果
   AnalyzeResults();
   
   //--- 保存到文件
   if(Inp_SaveToFile)
   {
      SaveResultsToFile();
   }
}

//+------------------------------------------------------------------+
//| 记录信号                                                          |
//+------------------------------------------------------------------+
void RecordSignal(datetime time, int barIndex, bool isBullish, 
                  string pattern, double strength, double price,
                  double emaScore, double volumeScore)
{
   if(g_SignalCount >= ArraySize(g_Signals))
   {
      ArrayResize(g_Signals, ArraySize(g_Signals) + 100);
   }
   
   g_Signals[g_SignalCount].time = time;
   g_Signals[g_SignalCount].barIndex = barIndex;
   g_Signals[g_SignalCount].isBullish = isBullish;
   g_Signals[g_SignalCount].pattern = pattern;
   g_Signals[g_SignalCount].strength = strength;
   g_Signals[g_SignalCount].entryPrice = price;
   g_Signals[g_SignalCount].emaScore = emaScore;
   g_Signals[g_SignalCount].volumeScore = volumeScore;
   
   //--- 模拟计算结果（向后看10根K线）
   g_Signals[g_SignalCount].result = SimulateOutcome(barIndex, isBullish);
   
   g_SignalCount++;
}

//+------------------------------------------------------------------+
//| 模拟交易结果                                                      |
//+------------------------------------------------------------------+
double SimulateOutcome(int barIndex, bool isBullish)
{
   double entry = iClose(_Symbol, PERIOD_M3, barIndex);
   double bestPrice = entry;
   double worstPrice = entry;
   
   //--- 向后看10根K线
   for(int i = 1; i <= 10; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M3, barIndex - i);
      double low  = iLow(_Symbol, PERIOD_M3, barIndex - i);
      
      if(high > bestPrice) bestPrice = high;
      if(low < worstPrice) worstPrice = low;
   }
   
   //--- 计算盈亏（点数）
   if(isBullish)
   {
      return bestPrice - entry;  // 做多：最高价 - 入场价
   }
   else
   {
      return entry - bestPrice;  // 做空：入场价 - 最低价
   }
}

//+------------------------------------------------------------------+
//| 分析结果                                                          |
//+------------------------------------------------------------------+
void AnalyzeResults()
{
   Print("\n========== 回测结果分析 ==========");
   Print("总信号数: ", g_SignalCount);
   
   if(g_SignalCount == 0)
   {
      Print("未生成任何信号，请检查参数设置");
      return;
   }
   
   //--- 统计胜率
   int wins = 0;
   int losses = 0;
   double totalProfit = 0;
   double totalLoss = 0;
   double maxProfit = 0;
   double maxLoss = 0;
   
   for(int i = 0; i < g_SignalCount; i++)
   {
      double result = g_Signals[i].result;
      
      if(result > 0)
      {
         wins++;
         totalProfit += result;
         if(result > maxProfit) maxProfit = result;
      }
      else
      {
         losses++;
         totalLoss += MathAbs(result);
         if(MathAbs(result) > maxLoss) maxLoss = MathAbs(result);
      }
   }
   
   double winRate = (double)wins / g_SignalCount * 100;
   double avgProfit = wins > 0 ? totalProfit / wins : 0;
   double avgLoss = losses > 0 ? totalLoss / losses : 0;
   double profitFactor = totalLoss > 0 ? totalProfit / totalLoss : 0;
   double expectancy = (winRate/100 * avgProfit) - ((100-winRate)/100 * avgLoss);
   
   //--- 打印结果
   Print("\n【基础统计】");
   Print("胜率: ", DoubleToString(winRate, 2), "% (", wins, "胜 / ", losses, "负)");
   Print("总盈利: ", DoubleToString(totalProfit, 2), " 点");
   Print("总亏损: ", DoubleToString(totalLoss, 2), " 点");
   Print("盈亏比: ", DoubleToString(profitFactor, 2));
   Print("期望值: ", DoubleToString(expectancy, 2), " 点/笔");
   
   Print("\n【盈亏分析】");
   Print("平均盈利: ", DoubleToString(avgProfit, 2), " 点");
   Print("平均亏损: ", DoubleToString(avgLoss, 2), " 点");
   Print("最大盈利: ", DoubleToString(maxProfit, 2), " 点");
   Print("最大亏损: ", DoubleToString(maxLoss, 2), " 点");
   
   //--- 形态分析
   AnalyzePatterns();
   
   //--- 优化建议
   PrintOptimizationSuggestions(winRate, profitFactor, expectancy);
}

//+------------------------------------------------------------------+
//| 形态分析                                                          |
//+------------------------------------------------------------------+
void AnalyzePatterns()
{
   Print("\n【形态分布】");
   
   // 统计各形态出现次数和胜率
   string patterns[];
   int patternCounts[];
   int patternWins[];
   
   for(int i = 0; i < g_SignalCount; i++)
   {
      string pat = g_Signals[i].pattern;
      int idx = -1;
      
      // 查找是否已存在
      for(int j = 0; j < ArraySize(patterns); j++)
      {
         if(patterns[j] == pat)
         {
            idx = j;
            break;
         }
      }
      
      // 新增形态
      if(idx == -1)
      {
         int size = ArraySize(patterns);
         ArrayResize(patterns, size + 1);
         ArrayResize(patternCounts, size + 1);
         ArrayResize(patternWins, size + 1);
         
         idx = size;
         patterns[idx] = pat;
         patternCounts[idx] = 0;
         patternWins[idx] = 0;
      }
      
      patternCounts[idx]++;
      if(g_Signals[i].result > 0)
         patternWins[idx]++;
   }
   
   // 打印各形态统计
   for(int i = 0; i < ArraySize(patterns); i++)
   {
      double patWinRate = (double)patternWins[i] / patternCounts[i] * 100;
      Print(patterns[i], ": ", patternCounts[i], "次, 胜率", 
            DoubleToString(patWinRate, 1), "%");
   }
}

//+------------------------------------------------------------------+
//| 优化建议                                                          |
//+------------------------------------------------------------------+
void PrintOptimizationSuggestions(double winRate, double profitFactor, double expectancy)
{
   Print("\n【优化建议】");
   
   if(winRate < 45)
   {
      Print("⚠️ 胜率偏低，建议：");
      Print("   1. 提高 VolumeRatio 至 2.0+（减少信号，提高质量）");
      Print("   2. 增加 EMA 周期至 30/60/250（过滤噪音）");
      Print("   3. 添加趋势强度过滤（ADX > 25）");
   }
   else if(winRate > 60)
   {
      Print("✅ 胜率良好，建议：");
      Print("   1. 可适当降低 VolumeRatio 至 1.3（增加信号数）");
      Print("   2. 尝试增加手数或仓位");
   }
   
   if(profitFactor < 1.5)
   {
      Print("⚠️ 盈亏比偏低，建议：");
      Print("   1. 扩大止盈至 150点");
      Print("   2. 收紧止损至 40点");
      Print("   3. 添加追踪止盈");
   }
   
   if(expectancy < 10)
   {
      Print("⚠️ 期望值偏低，建议重新评估策略");
   }
   else
   {
      Print("✅ 期望值良好，策略可行");
   }
}

//+------------------------------------------------------------------+
//| 保存结果到CSV文件                                                 |
//+------------------------------------------------------------------+
void SaveResultsToFile()
{
   string filename = Inp_OutputFile;
   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   
   if(handle != INVALID_HANDLE)
   {
      // 写入表头
      FileWrite(handle, "Time", "BarIndex", "Direction", "Pattern", 
                "Strength", "EntryPrice", "EMAScore", "VolumeScore", "Result");
      
      // 写入数据
      for(int i = 0; i < g_SignalCount; i++)
      {
         FileWrite(handle, 
            TimeToString(g_Signals[i].time, TIME_DATE|TIME_MINUTES),
            g_Signals[i].barIndex,
            g_Signals[i].isBullish ? "BUY" : "SELL",
            g_Signals[i].pattern,
            DoubleToString(g_Signals[i].strength, 2),
            DoubleToString(g_Signals[i].entryPrice, 2),
            DoubleToString(g_Signals[i].emaScore, 2),
            DoubleToString(g_Signals[i].volumeScore, 2),
            DoubleToString(g_Signals[i].result, 2)
         );
      }
      
      FileClose(handle);
      Print("\n结果已保存至: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", filename);
   }
   else
   {
      Print("保存文件失败，错误码: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| 辅助函数                                                          |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetTrendByIndex(int timeframe, int index)
{
   double emaFast = iMA(_Symbol, timeframe, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, index);
   double emaMid  = iMA(_Symbol, timeframe, Inp_EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, index);
   double emaSlow = iMA(_Symbol, timeframe, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, index);
   double close   = iClose(_Symbol, timeframe, index);
   
   if(emaFast == 0 || emaMid == 0 || emaSlow == 0)
      return TREND_NONE;
   
   if(close > emaFast && emaFast > emaMid && emaMid > emaSlow)
      return TREND_BULL;
   
   if(close < emaFast && emaFast < emaMid && emaMid < emaSlow)
      return TREND_BEAR;
   
   return TREND_NONE;
}

bool AnalyzeBullishPattern(int index, double &strength, string &name)
{
   // 简化版威科夫分析
   double open = iOpen(_Symbol, PERIOD_M3, index);
   double high = iHigh(_Symbol, PERIOD_M3, index);
   double low  = iLow(_Symbol, PERIOD_M3, index);
   double close= iClose(_Symbol, PERIOD_M3, index);
   
   double range = high - low;
   double body = MathAbs(close - open);
   
   if(range == 0) return false;
   
   // 成交量检查
   long volNow = iVolume(_Symbol, PERIOD_M3, index);
   long volAvg = 0;
   for(int i = 1; i <= Inp_VolumeLookback; i++)
      volAvg += iVolume(_Symbol, PERIOD_M3, index + i);
   volAvg /= Inp_VolumeLookback;
   
   bool volumeOK = volNow > volAvg * Inp_VolumeRatio;
   bool bodyOK = body / range > Inp_BodyRatio;
   bool closeOK = (close - low) / range > 0.6;
   bool upMove = close > open;
   
   if(volumeOK && bodyOK && closeOK && upMove)
   {
      strength = (body / range) * ((double)volNow / volAvg);
      name = "Bullish_Thrust";
      return true;
   }
   
   return false;
}

bool AnalyzeBearishPattern(int index, double &strength, string &name)
{
   double open = iOpen(_Symbol, PERIOD_M3, index);
   double high = iHigh(_Symbol, PERIOD_M3, index);
   double low  = iLow(_Symbol, PERIOD_M3, index);
   double close= iClose(_Symbol, PERIOD_M3, index);
   
   double range = high - low;
   double body = MathAbs(close - open);
   
   if(range == 0) return false;
   
   long volNow = iVolume(_Symbol, PERIOD_M3, index);
   long volAvg = 0;
   for(int i = 1; i <= Inp_VolumeLookback; i++)
      volAvg += iVolume(_Symbol, PERIOD_M3, index + i);
   volAvg /= Inp_VolumeLookback;
   
   bool volumeOK = volNow > volAvg * Inp_VolumeRatio;
   bool bodyOK = body / range > Inp_BodyRatio;
   bool closeOK = (high - close) / range > 0.6;
   bool downMove = close < open;
   
   if(volumeOK && bodyOK && closeOK && downMove)
   {
      strength = (body / range) * ((double)volNow / volAvg);
      name = "Bearish_Thrust";
      return true;
   }
   
   return false;
}

double CalculateEMAScore(int index)
{
   double h1Trend = GetTrendByIndex(PERIOD_H1, index);
   double m15Trend = GetTrendByIndex(PERIOD_M15, index);
   
   if(h1Trend == TREND_NONE || m15Trend == TREND_NONE) return 0;
   if(h1Trend != m15Trend) return 0;
   
   return 1.0;  // 趋势一致，满分
}

double CalculateVolumeScore(int index)
{
   long volNow = iVolume(_Symbol, PERIOD_M3, index);
   long volAvg = 0;
   for(int i = 1; i <= Inp_VolumeLookback; i++)
      volAvg += iVolume(_Symbol, PERIOD_M3, index + i);
   volAvg /= Inp_VolumeLookback;
   
   return (double)volNow / volAvg;
}
//+------------------------------------------------------------------+
