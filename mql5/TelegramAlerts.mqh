//+------------------------------------------------------------------+
//| Telegram 交易提醒模块                                            |
//| Telegram Alerts Module for Triple Timeframe EA                   |
//| 配合 rho-telegram-alerts skill 使用                              |
//+------------------------------------------------------------------+

#ifndef TELEGRAM_ALERTS_MQH
#define TELEGRAM_ALERTS_MQH

#include <WinInet.mqh>

//+------------------------------------------------------------------+
//| Telegram Bot 配置                                                 |
//+------------------------------------------------------------------+
input group "=== Telegram 提醒设置 ==="
input string   Inp_TelegramBotToken = "";        // Bot Token (从@BotFather获取)
input string   Inp_TelegramChatID   = "";        // Chat ID
input bool     Inp_TelegramEnabled  = true;      // 启用Telegram提醒

//+------------------------------------------------------------------+
//| Telegram 提醒类                                                   |
//+------------------------------------------------------------------+
class CTelegramAlerts
{
private:
   string   m_botToken;
   string   m_chatID;
   bool     m_enabled;
   int      m_internetHandle;
   
public:
   // 构造函数
   CTelegramAlerts(string botToken, string chatID, bool enabled)
   {
      m_botToken = botToken;
      m_chatID = chatID;
      m_enabled = enabled;
      m_internetHandle = 0;
   }
   
   // 析构函数
   ~CTelegramAlerts()
   {
      if(m_internetHandle != 0)
         InternetCloseHandle(m_internetHandle);
   }
   
   //+--------------------------------------------------------------+
   //| 发送交易开仓提醒                                                |
   //+--------------------------------------------------------------+
   void SendTradeOpen(string symbol, bool isBuy, double entryPrice, 
                      double stopLoss, double takeProfit, double lotSize)
   {
      if(!m_enabled || m_botToken == "" || m_chatID == "")
         return;
      
      string direction = isBuy ? "LONG" : "SHORT";
      string emoji = isBuy ? "🟢" : "🔴";
      
      double risk = MathAbs(entryPrice - stopLoss) * lotSize * 100; // 约等于
      double reward = MathAbs(takeProfit - entryPrice) * lotSize * 100;
      double rr = reward / risk;
      
      string message = emoji + " *TRADE OPENED*\n\n" +
         "*Asset:* " + symbol + " | " + direction + "\n" +
         "*Entry:* " + DoubleToString(entryPrice, 2) + "\n" +
         "*Stop:* " + DoubleToString(stopLoss, 2) + "\n" +
         "*Target:* " + DoubleToString(takeProfit, 2) + "\n" +
         "*Lot:* " + DoubleToString(lotSize, 2) + "\n" +
         "*Risk/Reward:* 1:" + DoubleToString(rr, 1) + "\n\n" +
         "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "_";
      
      SendMessage(message);
   }
   
   //+--------------------------------------------------------------+
   //| 发送交易平仓提醒                                                |
   //+--------------------------------------------------------------+
   void SendTradeClose(string symbol, bool isBuy, double entryPrice, 
                       double exitPrice, double lotSize, double profit)
   {
      if(!m_enabled || m_botToken == "" || m_chatID == "")
         return;
      
      string direction = isBuy ? "LONG" : "SHORT";
      string emoji = profit > 0 ? "✅" : "❌";
      string result = profit > 0 ? "WIN" : "LOSS";
      
      string message = emoji + " *TRADE CLOSED - " + result + "*\n\n" +
         "*Asset:* " + symbol + " | " + direction + "\n" +
         "*Entry:* " + DoubleToString(entryPrice, 2) + "\n" +
         "*Exit:* " + DoubleToString(exitPrice, 2) + "\n" +
         "*P&L:* " + (profit > 0 ? "+$" : "-$") + 
         DoubleToString(MathAbs(profit), 2) + "\n\n" +
         "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "_";
      
      SendMessage(message);
   }
   
   //+--------------------------------------------------------------+
   //| 发送信号提醒                                                    |
   //+--------------------------------------------------------------+
   void SendSignal(string symbol, string pattern, bool isBullish, 
                   double strength, double price)
   {
      if(!m_enabled || m_botToken == "" || m_chatID == "")
         return;
      
      string emoji = isBullish ? "📈" : "📉";
      string direction = isBullish ? "BULLISH" : "BEARISH";
      
      string message = emoji + " *SIGNAL DETECTED*\n\n" +
         "*Asset:* " + symbol + "\n" +
         "*Pattern:* " + pattern + "\n" +
         "*Direction:* " + direction + "\n" +
         "*Strength:* " + DoubleToString(strength, 2) + "/10\n" +
         "*Price:* " + DoubleToString(price, 2) + "\n\n" +
         "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "_";
      
      SendMessage(message);
   }
   
   //+--------------------------------------------------------------+
   //| 发送每日摘要                                                    |
   //+--------------------------------------------------------------+
   void SendDailySummary(int totalTrades, int winTrades, int lossTrades,
                         double totalProfit, double maxDrawdown)
   {
      if(!m_enabled || m_botToken == "" || m_chatID == "")
         return;
      
      double winRate = totalTrades > 0 ? (double)winTrades / totalTrades * 100 : 0;
      string profitEmoji = totalProfit > 0 ? "🟢" : "🔴";
      
      string message = "📊 *DAILY TRADING SUMMARY*\n\n" +
         "*Total Trades:* " + IntegerToString(totalTrades) + "\n" +
         "*Wins:* " + IntegerToString(winTrades) + "\n" +
         "*Losses:* " + IntegerToString(lossTrades) + "\n" +
         "*Win Rate:* " + DoubleToString(winRate, 1) + "%\n" +
         "*Net P&L:* " + profitEmoji + " $" + 
         DoubleToString(totalProfit, 2) + "\n" +
         "*Max Drawdown:* " + DoubleToString(maxDrawdown, 2) + "%\n\n" +
         "_" + TimeToString(TimeCurrent(), TIME_DATE) + "_";
      
      SendMessage(message);
   }
   
   //+--------------------------------------------------------------+
   //| 发送止损警告                                                    |
   //+--------------------------------------------------------------+
   void SendStopLossWarning(string symbol, double currentPrice, 
                            double stopLoss, double remainingPips)
   {
      if(!m_enabled || m_botToken == "" || m_chatID == "")
         return;
      
      string message = "⚠️ *STOP LOSS WARNING*\n\n" +
         "*Asset:* " + symbol + "\n" +
         "*Current:* " + DoubleToString(currentPrice, 2) + "\n" +
         "*Stop Loss:* " + DoubleToString(stopLoss, 2) + "\n" +
         "*Remaining:* " + DoubleToString(remainingPips, 1) + " pips\n\n" +
         "_Consider manual intervention_";
      
      SendMessage(message);
   }
   
private:
   //+--------------------------------------------------------------+
   //| 发送消息到 Telegram                                             |
   //+--------------------------------------------------------------+
   void SendMessage(string message)
   {
      string url = "https://api.telegram.org/bot" + m_botToken + "/sendMessage";
      string headers;
      string data = "chat_id=" + m_chatID + "&text=" + message + "&parse_mode=Markdown";
      
      // URL编码
      StringReplace(data, "\n", "%0A");
      StringReplace(data, " ", "%20");
      StringReplace(data, "*", "%2A");
      StringReplace(data, "_", "%5F");
      
      // 使用WinInet发送HTTP请求
      int handle = InternetOpen("MT5 Telegram Bot", 0, "", "", 0);
      if(handle == 0)
      {
         Print("InternetOpen failed");
         return;
      }
      
      int connect = InternetOpenUrl(handle, url + "?" + data, "", 0, 0, 0);
      if(connect == 0)
      {
         Print("InternetOpenUrl failed");
         InternetCloseHandle(handle);
         return;
      }
      
      InternetCloseHandle(connect);
      InternetCloseHandle(handle);
      
      Print("Telegram message sent successfully");
   }
};

#endif // TELEGRAM_ALERTS_MQH
