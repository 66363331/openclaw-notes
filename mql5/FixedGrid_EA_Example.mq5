//+------------------------------------------------------------------+
//| 固定网格加仓EA示例                                                |
//| Fixed Grid EA Example - 替代马丁的安全方案                       |
//| 用法：手动开首仓，EA自动管理网格加仓和平仓                        |
//+------------------------------------------------------------------+
#property copyright "Jassica for HoneyRay"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "FixedGridManager.mqh"

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input group "=== 首仓设置 ==="
input bool     Inp_ManualFirstOrder = true;   // true=手动首仓, false=自动首仓

input group "=== 固定网格设置（替代马丁）==="
input double   Inp_FixedLotSize = 0.01;       // 固定加仓手数（绝不倍增！）
input int      Inp_GridPips = 30;             // 网格间隔（点数）
input int      Inp_MaxLayers = 3;             // 最大加仓层数
input double   Inp_MaxTotalLot = 0.05;        // 总手数硬上限
input double   Inp_HardStopLoss = 200;        // 硬止损金额($)
input bool     Inp_UseTrendFilter = true;     // 加仓时检查趋势

input group "=== 止盈设置 ==="
input double   Inp_TakeProfitPips = 50;       // 止盈点数（从均价计算）
input bool     Inp_UseTrailing = true;        // 启用追踪止盈
input double   Inp_TrailingStart = 30;        // 追踪启动点数

input group "=== 其他 ==="
input int      Inp_MagicNumber = 998877;      // 魔术号
input int      Inp_Slippage = 30;             // 滑点

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
CTrade          g_trade;
CFixedGridManager g_gridManager(Inp_MagicNumber);
datetime        g_lastBarTime = 0;
bool            g_hasFirstOrder = false;
bool            g_isLong = true;

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(Inp_MagicNumber);
   g_trade.SetDeviationInPoints(Inp_Slippage);
   g_trade.SetTypeFillingBySymbol(Symbol());
   
   // 初始化网格管理器
   GridConfig config;
   config.FixedLotSize = Inp_FixedLotSize;
   config.GridPips = Inp_GridPips;
   config.MaxLayers = Inp_MaxLayers;
   config.MaxTotalLot = Inp_MaxTotalLot;
   config.HardStopLoss = Inp_HardStopLoss;
   config.UseTrendFilter = Inp_UseTrendFilter;
   
   g_gridManager.Init(config);
   
   // 检查是否已有持仓（手动首仓）
   CheckExistingPosition();
   
   Print("=== 固定网格EA启动 ===");
   Print("首仓模式: ", Inp_ManualFirstOrder ? "手动" : "自动");
   Print("网格间隔: ", Inp_GridPips, " 点");
   Print("固定手数: ", Inp_FixedLotSize, " (绝不倍增!)");
   Print("最大层数: ", Inp_MaxLayers);
   Print("总手数上限: ", Inp_MaxTotalLot);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA停止，原因: ", reason);
}

//+------------------------------------------------------------------+
//| 主循环                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // 检查是否为新K线（避免同K线重复处理）
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;
   
   // 检查是否有首仓
   if(!g_hasFirstOrder)
   {
      if(Inp_ManualFirstOrder)
      {
         // 等待手动开仓
         CheckManualFirstOrder();
      }
      else
      {
         // 自动开首仓（需要你自己的入场逻辑）
         // OpenFirstOrderAuto();
      }
      return;
   }
   
   // 获取当前持仓总盈亏
   double totalProfit = GetTotalProfit();
   
   // 检查硬止损
   if(g_gridManager.IsHardStopTriggered(totalProfit))
   {
      g_gridManager.CloseAllPositions("硬止损");
      g_hasFirstOrder = false;
      return;
   }
   
   // 检查止盈
   if(CheckTakeProfit())
   {
      g_gridManager.CloseAllPositions("止盈");
      g_hasFirstOrder = false;
      return;
   }
   
   // 管理追踪止盈
   if(Inp_UseTrailing)
   {
      ManageTrailingStop();
   }
   
   // 检查是否应该加仓（固定网格，不是马丁！）
   double reasons[];
   if(g_gridManager.ShouldAddOnLoss(g_isLong, reasons))
   {
      // 执行固定手数加仓（绝不倍增）
      if(g_gridManager.ExecuteAdd(g_isLong, "Grid Fixed"))
      {
         Print("网格加仓完成，当前层数: ", g_gridManager.GetCurrentLayers());
      }
   }
}

//+------------------------------------------------------------------+
//| 检查手动首仓                                                      |
//+------------------------------------------------------------------+
void CheckManualFirstOrder()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      // 找到手动开的首仓
      double lot = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      long type = PositionGetInteger(POSITION_TYPE);
      
      g_isLong = (type == POSITION_TYPE_BUY);
      g_hasFirstOrder = true;
      
      // 初始化网格管理器
      g_gridManager.SetInitialPosition(price, lot, g_isLong);
      
      Print("检测到手动首仓! 方向:", g_isLong ? "多" : "空", 
            " 价格:", price, " 手数:", lot);
      break;
   }
}

//+------------------------------------------------------------------+
//| 检查是否已有持仓（用于OnInit）                                    |
//+------------------------------------------------------------------+
void CheckExistingPosition()
{
   CheckManualFirstOrder();
}

//+------------------------------------------------------------------+
//| 获取总盈亏                                                        |
//+------------------------------------------------------------------+
double GetTotalProfit()
{
   double totalProfit = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      
      totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| 检查止盈                                                          |
//+------------------------------------------------------------------+
bool CheckTakeProfit()
{
   double avgPrice = g_gridManager.GetAveragePrice();
   if(avgPrice == 0) return false;
   
   double currentPrice = g_isLong ? 
      SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double profitPips = g_isLong ? 
      (currentPrice - avgPrice) / _Point :
      (avgPrice - currentPrice) / _Point;
   
   if(profitPips >= Inp_TakeProfitPips)
   {
      Print("达到止盈! 盈利:", profitPips, " 点");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 管理追踪止盈                                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double avgPrice = g_gridManager.GetAveragePrice();
   if(avgPrice == 0) return;
   
   double currentPrice = g_isLong ? 
      SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // 计算当前盈利点数
   double profitPips = g_isLong ? 
      (currentPrice - avgPrice) / _Point :
      (avgPrice - currentPrice) / _Point;
   
   // 达到启动条件
   if(profitPips >= Inp_TrailingStart)
   {
      // 这里可以实现移动止损逻辑
      // 简化版：当盈利超过30点后，把止损移到均价+10点
   }
}

//+------------------------------------------------------------------+
//| 信息面板（可选）                                                  |
//+------------------------------------------------------------------+
void ShowInfoPanel()
{
   // 可以在图表上显示当前层数、总手数、均价等信息
   // 使用Comment()或绘制文本对象
   
   string info = StringFormat(
      "固定网格EA | 层数: %d/%d | 总手数: %.2f/%.2f | 均价: %.2f",
      g_gridManager.GetCurrentLayers(),
      Inp_MaxLayers,
      g_gridManager.GetTotalLot(),
      Inp_MaxTotalLot,
      g_gridManager.GetAveragePrice()
   );
   
   Comment(info);
}
//+------------------------------------------------------------------+
