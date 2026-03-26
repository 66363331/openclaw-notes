//+------------------------------------------------------------------+
//| 三重周期交易EA                                                    |
//| Triple Timeframe Expert Advisor                                 |
//| H1/M15 EMA趋势 + M3威科夫量价 + 自动交易                          |
//+------------------------------------------------------------------+
#property copyright "Jassica for HoneyRay"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input group "=== 交易设置 ==="
input bool     Inp_AutoTrading    = false;      // 自动交易（ false=仅提醒, true=自动开仓）
input double   Inp_LotSize        = 0.01;       // 手数
input int      Inp_MagicNumber    = 998877;     // 魔术号
input int      Inp_Slippage       = 30;         // 滑点

input group "=== H1 & M15 EMA 设置 ==="
input int      Inp_EMA_Fast       = 20;         // 快线EMA
input int      Inp_EMA_Mid        = 50;         // 中线EMA
input int      Inp_EMA_Slow       = 200;        // 慢线EMA

input group "=== M3 威科夫量价 ==="
input int      Inp_VolumeLookback = 20;         // 成交量回看周期
input double   Inp_VolumeRatio    = 1.5;        // 放量倍数
input double   Inp_BodyRatio      = 0.6;        // 实体占比
input int      Inp_SignalCooldown = 5;          // 信号冷却(bars)

input group "=== 止盈止损 ==="
input double   Inp_StopLoss       = 50;         // 止损(点数)
input double   Inp_TakeProfit     = 100;        // 止盈(点数)
input bool     Inp_UseTrailing    = true;       // 启用追踪止盈
input double   Inp_TrailingStart  = 30;         // 追踪启动(点数)
input double   Inp_TrailingStop   = 20;         // 追踪止损(点数)

input group "=== 提醒设置 ==="
input bool     Inp_AlertEnabled       = true;   // 弹窗提醒
input bool     Inp_SendNotification   = true;   // 手机推送
input bool     Inp_PlaySound          = true;   // 声音提醒

input group "=== 风控设置 ==="
input int      Inp_MaxDailyTrades = 5;          // 每日最大交易数
input double   Inp_MaxSpread      = 30;         // 最大点差(点数)
input int      Inp_TradingStartHour = 8;        // 交易开始时间(小时)
input int      Inp_TradingEndHour   = 22;       // 交易结束时间(小时)

//+------------------------------------------------------------------+
//| 枚举定义                                                          |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_NONE = 0,
   TREND_BULL = 1,
   TREND_BEAR = -1
};

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
CTrade      m_trade;
CPositionInfo m_position;

datetime    g_LastSignalTime = 0;
int         g_DailyTradeCount = 0;
datetime    g_LastTradeDay = 0;
int         g_SignalCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 初始化交易对象
   m_trade.SetExpertMagicNumber(Inp_MagicNumber);
   m_trade.SetDeviationInPoints(Inp_Slippage);
   m_trade.SetTypeFillingBySymbol(Symbol());
   m_trade.SetAsyncMode(false);
   
   //--- 检查交易权限
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Alert("警告: 交易未允许！请检查EA属性设置。");
   }
   
   //--- 检查自动交易
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("警告: 终端自动交易未启用！");
   }
   
   Print("三重周期EA初始化完成");
   Print("模式: ", Inp_AutoTrading ? "自动交易" : "仅提醒");
   Print("手数: ", Inp_LotSize);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA已停止，原因: ", reason);
   Print("今日信号数: ", g_SignalCounter);
}

//+------------------------------------------------------------------+
//| 获取EMA趋势方向                                                   |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetEMAsTrend(int timeframe)
{
   double emaFast = iMA(_Symbol, timeframe, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaMid  = iMA(_Symbol, timeframe, Inp_EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(_Symbol, timeframe, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 0);
   double close   = iClose(_Symbol, timeframe, 0);
   
   if(emaFast == 0 || emaMid == 0 || emaSlow == 0)
      return TREND_NONE;
   
   if(close > emaFast && emaFast > emaMid && emaMid > emaSlow)
      return TREND_BULL;
   
   if(close < emaFast && emaFast < emaMid && emaMid < emaSlow)
      return TREND_BEAR;
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| 威科夫量价分析                                                    |
//+------------------------------------------------------------------+
bool WyckoffVolumeAnalysis(bool isBull, double &strength)
{
   //--- 成交量分析
   long volume[];
   ArraySetAsSeries(volume, true);
   
   if(CopyTickVolume(_Symbol, PERIOD_M3, 0, Inp_VolumeLookback, volume) < Inp_VolumeLookback)
      return false;
   
   double avgVolume = 0;
   for(int i = 1; i < Inp_VolumeLookback; i++)
      avgVolume += (double)volume[i];
   avgVolume /= (Inp_VolumeLookback - 1);
   
   double currVolume = (double)volume[0];
   bool volumeConfirmed = (currVolume > avgVolume * Inp_VolumeRatio);
   
   //--- 价格行为分析
   double m3High = iHigh(_Symbol, PERIOD_M3, 0);
   double m3Low  = iLow(_Symbol, PERIOD_M3, 0);
   double m3Open = iOpen(_Symbol, PERIOD_M3, 0);
   double m3Close= iClose(_Symbol, PERIOD_M3, 0);
   
   if(m3High == 0 || m3Low == 0) return false;
   
   double range = m3High - m3Low;
   double body = MathAbs(m3Close - m3Open);
   
   if(range == 0) return false;
   
   double volumeFactor = currVolume / avgVolume;
   double bodyFactor = body / range;
   strength = volumeFactor * bodyFactor;
   
   //--- 做多信号
   if(isBull)
   {
      bool strongBody = (m3Close > m3Open) && (body / range > Inp_BodyRatio);
      bool strongClose = (m3Close - m3Low) / range > Inp_BodyRatio;
      return (strongBody && strongClose && volumeConfirmed);
   }
   //--- 做空信号
   else
   {
      bool strongBody = (m3Close < m3Open) && (body / range > Inp_BodyRatio);
      bool weakClose = (m3High - m3Close) / range > Inp_BodyRatio;
      return (strongBody && weakClose && volumeConfirmed);
   }
}

//+------------------------------------------------------------------+
//| 检查交易条件                                                      |
//+------------------------------------------------------------------+
bool CheckTradingConditions()
{
   //--- 检查点差
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > Inp_MaxSpread)
   {
      Print("点差过大: ", spread, " > ", Inp_MaxSpread);
      return false;
   }
   
   //--- 检查交易时间
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < Inp_TradingStartHour || dt.hour >= Inp_TradingEndHour)
   {
      return false;
   }
   
   //--- 检查每日交易次数
   if(dt.day != TimeDay(g_LastTradeDay))
   {
      g_DailyTradeCount = 0;
      g_LastTradeDay = TimeCurrent();
   }
   
   if(g_DailyTradeCount >= Inp_MaxDailyTrades)
   {
      Print("已达到每日最大交易数: ", Inp_MaxDailyTrades);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 获取当前持仓方向                                                  |
//+------------------------------------------------------------------+
int GetCurrentPositionDirection()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY) return 1;
      if(type == POSITION_TYPE_SELL) return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| 平仓所有持仓                                                      |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      m_trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| 执行交易                                                          |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction, double strength)
{
   double price, sl, tp;
   
   if(direction == 1)  // 做多
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = price - Inp_StopLoss * _Point;
      tp = price + Inp_TakeProfit * _Point;
      
      if(Inp_AutoTrading)
      {
         if(m_trade.Buy(Inp_LotSize, price, sl, tp, "TripleTF Buy"))
         {
            g_DailyTradeCount++;
            Print("做多开仓成功 @", price, " SL:", sl, " TP:", tp);
         }
         else
         {
            Print("做多开仓失败: ", GetLastError());
         }
      }
      
      //--- 发送提醒
      string msg = StringFormat("做多信号！价格:%.2f 强度:%.2f", price, strength);
      if(Inp_AlertEnabled) Alert(msg);
      if(Inp_SendNotification) SendNotification(msg);
      if(Inp_PlaySound) PlaySound("buy.wav");
   }
   else  // 做空
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = price + Inp_StopLoss * _Point;
      tp = price - Inp_TakeProfit * _Point;
      
      if(Inp_AutoTrading)
      {
         if(m_trade.Sell(Inp_LotSize, price, sl, tp, "TripleTF Sell"))
         {
            g_DailyTradeCount++;
            Print("做空开仓成功 @", price, " SL:", sl, " TP:", tp);
         }
         else
         {
            Print("做空开仓失败: ", GetLastError());
         }
      }
      
      //--- 发送提醒
      string msg = StringFormat("做空信号！价格:%.2f 强度:%.2f", price, strength);
      if(Inp_AlertEnabled) Alert(msg);
      if(Inp_SendNotification) SendNotification(msg);
      if(Inp_PlaySound) PlaySound("sell.wav");
   }
}

//+------------------------------------------------------------------+
//| 追踪止盈管理                                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!Inp_UseTrailing) return;
   
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      if(type == POSITION_TYPE_BUY)
      {
         double profit = (bid - openPrice) / _Point;
         if(profit >= Inp_TrailingStart)
         {
            double newSL = bid - Inp_TrailingStop * _Point;
            if(newSL > currentSL || currentSL == 0)
            {
               m_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profit = (openPrice - ask) / _Point;
         if(profit >= Inp_TrailingStart)
         {
            double newSL = ask + Inp_TrailingStop * _Point;
            if(newSL < currentSL || currentSL == 0)
            {
               m_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 管理现有持仓（追踪止盈）
   ManageTrailingStop();
   
   //--- 检查交易条件
   if(!CheckTradingConditions())
      return;
   
   //--- 检查是否已有持仓
   if(GetCurrentPositionDirection() != 0)
      return;  // 已有持仓，等待平仓
   
   //=========================================
   // STEP 1: H1趋势判断
   //=========================================
   ENUM_TREND_DIRECTION h1Trend = GetEMAsTrend(PERIOD_H1);
   if(h1Trend == TREND_NONE)
      return;
   
   //=========================================
   // STEP 2: M15趋势确认
   //=========================================
   ENUM_TREND_DIRECTION m15Trend = GetEMAsTrend(PERIOD_M15);
   if(m15Trend == TREND_NONE || m15Trend != h1Trend)
      return;
   
   //=========================================
   // STEP 3: M3威科夫量价进场
   //=========================================
   datetime currentTime = iTime(_Symbol, PERIOD_M3, 0);
   
   //--- 检查信号冷却
   if(g_LastSignalTime != 0)
   {
      int barsSinceLast = iBarShift(_Symbol, PERIOD_M3, g_LastSignalTime);
      if(barsSinceLast < Inp_SignalCooldown && barsSinceLast >= 0)
         return;
   }
   
   double strength = 0;
   
   //--- 做多信号
   if(h1Trend == TREND_BULL && m15Trend == TREND_BULL)
   {
      if(WyckoffVolumeAnalysis(true, strength))
      {
         g_LastSignalTime = currentTime;
         g_SignalCounter++;
         ExecuteTrade(1, strength);
      }
   }
   //--- 做空信号
   else if(h1Trend == TREND_BEAR && m15Trend == TREND_BEAR)
   {
      if(WyckoffVolumeAnalysis(false, strength))
      {
         g_LastSignalTime = currentTime;
         g_SignalCounter++;
         ExecuteTrade(-1, strength);
      }
   }
}
//+------------------------------------------------------------------+
