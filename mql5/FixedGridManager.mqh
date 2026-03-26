//+------------------------------------------------------------------+
//| 固定网格加仓管理模块                                              |
//| Fixed Grid Position Manager                                     |
//| 替代马丁的安全加仓方案                                           |
//+------------------------------------------------------------------+

#ifndef FIXED_GRID_MANAGER_MQH
#define FIXED_GRID_MANAGER_MQH

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 网格加仓配置结构体                                                |
//+------------------------------------------------------------------+
struct GridConfig
{
   double FixedLotSize;      // 固定加仓手数
   int    GridPips;          // 网格间隔（点数）
   int    MaxLayers;         // 最大加仓层数
   double MaxTotalLot;       // 总手数硬上限
   double HardStopLoss;      // 硬止损金额
   bool   UseTrendFilter;    // 是否使用趋势过滤
};

//+------------------------------------------------------------------+
//| 固定网格加仓管理类                                                |
//+------------------------------------------------------------------+
class CFixedGridManager
{
private:
   CTrade      m_trade;
   GridConfig  m_config;
   int         m_magicNumber;
   
   // 持仓信息
   double      m_totalLot;           // 当前总手数
   int         m_currentLayers;      // 当前层数
   double      m_averagePrice;       // 平均持仓价格
   double      m_lastAddPrice;       // 上次加仓价格
   datetime    m_lastAddTime;        // 上次加仓时间
   double      m_initialEntryPrice;  // 首仓入场价
   
public:
   // 构造函数
   CFixedGridManager(int magicNumber)
   {
      m_magicNumber = magicNumber;
      m_trade.SetExpertMagicNumber(magicNumber);
      ResetState();
   }
   
   // 初始化配置
   void Init(GridConfig &config)
   {
      m_config = config;
      Print("固定网格管理器初始化");
      Print("网格间隔: ", m_config.GridPips, " 点");
      Print("固定手数: ", m_config.FixedLotSize);
      Print("最大层数: ", m_config.MaxLayers);
      Print("总手数上限: ", m_config.MaxTotalLot);
   }
   
   //+--------------------------------------------------------------+
   //| 检查是否应该加仓（亏损方向）                                    |
   //+--------------------------------------------------------------+
   bool ShouldAddOnLoss(bool isLong, double &reason[])
   {
      ArrayResize(reason, 0);
      
      // 1. 检查总手数上限（最重要！）
      if(m_totalLot >= m_config.MaxTotalLot)
      {
         ArrayResize(reason, 1);
         reason[0] = "已达总手数上限";
         return false;
      }
      
      // 2. 检查层数上限
      if(m_currentLayers >= m_config.MaxLayers)
      {
         ArrayResize(reason, 1);
         reason[0] = "已达最大层数";
         return false;
      }
      
      // 3. 检查网格间隔
      double currentPrice = isLong ? 
         SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
         SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      double priceDistance = MathAbs(currentPrice - m_lastAddPrice) / _Point;
      
      if(priceDistance < m_config.GridPips)
      {
         return false;  // 未达到网格间隔
      }
      
      // 4. 检查趋势过滤（可选）
      if(m_config.UseTrendFilter)
      {
         if(!IsTrendValid(isLong))
         {
            ArrayResize(reason, 1);
            reason[0] = "趋势不符";
            return false;
         }
      }
      
      // 5. 检查时间冷却（避免同K线重复加仓）
      if(TimeCurrent() - m_lastAddTime < 60)  // 至少间隔1分钟
      {
         return false;
      }
      
      ArrayResize(reason, 1);
      reason[0] = "满足加仓条件";
      return true;
   }
   
   //+--------------------------------------------------------------+
   //| 执行加仓（固定手数！不是马丁）                                  |
   //+--------------------------------------------------------------+
   bool ExecuteAdd(bool isLong, string comment = "Grid Add")
   {
      double price = isLong ? 
         SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
         SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // 固定手数，绝不倍增！
      double lotSize = m_config.FixedLotSize;
      
      // 检查账户资金是否足够
      if(!CheckMoneyForTrade(_Symbol, lotSize, isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL))
      {
         Print("资金不足，无法加仓");
         return false;
      }
      
      bool success = false;
      
      if(isLong)
      {
         success = m_trade.Buy(lotSize, price, 0, 0, comment);
      }
      else
      {
         success = m_trade.Sell(lotSize, price, 0, 0, comment);
      }
      
      if(success)
      {
         // 更新状态
         m_currentLayers++;
         m_lastAddPrice = price;
         m_lastAddTime = TimeCurrent();
         
         // 重新计算总手数和均价
         UpdatePositionInfo();
         
         Print("网格加仓成功 #", m_currentLayers, 
               " 手数:", lotSize, 
               " 价格:", price,
               " 总手数:", m_totalLot);
         
         return true;
      }
      
      return false;
   }
   
   //+--------------------------------------------------------------+
   //| 初始化首仓（手动开仓后调用）                                    |
//+--------------------------------------------------------------+
   void SetInitialPosition(double entryPrice, double lotSize, bool isLong)
   {
      m_initialEntryPrice = entryPrice;
      m_lastAddPrice = entryPrice;
      m_totalLot = lotSize;
      m_currentLayers = 1;  // 首仓算第1层
      m_lastAddTime = TimeCurrent();
      
      Print("首仓设置完成 价格:", entryPrice, " 手数:", lotSize);
   }
   
   //+--------------------------------------------------------------+
   //| 获取当前总手数                                                  |
   //+--------------------------------------------------------------+
   double GetTotalLot() const
   {
      return m_totalLot;
   }
   
   //+--------------------------------------------------------------+
   //| 获取当前层数                                                    |
   //+--------------------------------------------------------------+
   int GetCurrentLayers() const
   {
      return m_currentLayers;
   }
   
   //+--------------------------------------------------------------+
   //| 获取平均持仓价格                                                |
   //+--------------------------------------------------------------+
   double GetAveragePrice() const
   {
      return m_averagePrice;
   }
   
   //+--------------------------------------------------------------+
   //| 检查是否达到硬止损                                              |
   //+--------------------------------------------------------------+
   bool IsHardStopTriggered(double currentProfit)
   {
      // 亏损达到硬止损金额
      if(currentProfit <= -m_config.HardStopLoss)
      {
         Print("触发硬止损! 当前亏损:", currentProfit);
         return true;
      }
      return false;
   }
   
   //+--------------------------------------------------------------+
   //| 全平所有持仓                                                    |
   //+--------------------------------------------------------------+
   void CloseAllPositions(string reason = "")
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         
         m_trade.PositionClose(ticket);
      }
      
      Print("全部平仓完成 原因:", reason);
      ResetState();
   }
   
   //+--------------------------------------------------------------+
   //| 重置状态                                                        |
   //+--------------------------------------------------------------+
   void ResetState()
   {
      m_totalLot = 0;
      m_currentLayers = 0;
      m_averagePrice = 0;
      m_lastAddPrice = 0;
      m_lastAddTime = 0;
      m_initialEntryPrice = 0;
   }
   
   //+--------------------------------------------------------------+
   //| 打印当前状态                                                    |
   //+--------------------------------------------------------------+
   void PrintStatus()
   {
      Print("=== 网格状态 ===");
      Print("总手数: ", m_totalLot, " / ", m_config.MaxTotalLot);
      Print("当前层数: ", m_currentLayers, " / ", m_config.MaxLayers);
      Print("平均价格: ", m_averagePrice);
      Print("上次加仓价: ", m_lastAddPrice);
   }

private:
   //+--------------------------------------------------------------+
   //| 更新持仓信息                                                    |
   //+--------------------------------------------------------------+
   void UpdatePositionInfo()
   {
      m_totalLot = 0;
      m_averagePrice = 0;
      double totalCost = 0;
      
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         
         double lot = PositionGetDouble(POSITION_VOLUME);
         double price = PositionGetDouble(POSITION_PRICE_OPEN);
         
         m_totalLot += lot;
         totalCost += lot * price;
      }
      
      if(m_totalLot > 0)
      {
         m_averagePrice = totalCost / m_totalLot;
      }
   }
   
   //+--------------------------------------------------------------+
   //| 检查趋势是否有效（可选）                                        |
   //+--------------------------------------------------------------+
   bool IsTrendValid(bool isLong)
   {
      // 简化版：检查H1 EMA方向
      double ema20 = iMA(_Symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
      double ema50 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
      double close = iClose(_Symbol, PERIOD_H1, 0);
      
      if(ema20 == 0 || ema50 == 0) return true;  // 数据不足时允许
      
      if(isLong)
      {
         return close > ema20 && ema20 > ema50;  // 多头排列
      }
      else
      {
         return close < ema20 && ema20 < ema50;  // 空头排列
      }
   }
   
   //+--------------------------------------------------------------+
   //| 检查资金是否充足                                                |
   //+--------------------------------------------------------------+
   bool CheckMoneyForTrade(string symbol, double lot, ENUM_ORDER_TYPE orderType)
   {
      double marginRequired;
      if(!OrderCalcMargin(orderType, symbol, lot, 
         SymbolInfoDouble(symbol, SYMBOL_ASK), marginRequired))
      {
         return false;
      }
      
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      return freeMargin >= marginRequired * 1.5;  // 1.5倍安全垫
   }
};

#endif // FIXED_GRID_MANAGER_MQH
