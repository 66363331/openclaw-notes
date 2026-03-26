//+------------------------------------------------------------------+
//| V6.4 半自动印钞机（精简版）
//| 更新日期: 2026-02-20
//| 保留模块：
//|   1) 自动续开首仓（方向按钮）
//|   2) 金字塔加仓（★方案C：无独立TP，马丁介入后补挂保护TP）
//|   3) 马丁补仓 L1/L2（去掉L0，步距基于最远亏损仓）
//|      L1 = 首仓价跌/涨23美元，手数=首仓×1
//|      L2 = L1开仓价再跌/涨45美元，手数=首仓×2
//|   4) 追踪止盈 / 主止盈
//|   5) 硬止损强平
//| 已移除：
//|   - L0浅位补仓（防补仓过密）
//|   - 金字塔独立TP（方案C取代，顺势时不干扰趋势）
//|   - 所有冻结闸门（累计波幅/暴力K/RSI极值）
//|   - 所有清仓保护（H1破位/MACD翻转/V反熔断/H1贴线）
//|   - 状态机（BAN/COOLDOWN）
//|   - 波动率冷却
//|   - MACD/ATR/RSI 信号过滤
//|   - 趋势确认锁
//|   - 账号绑定
//|   - 复杂日志系统
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

const string EA_VERSION = "V6.11";

//+------------------------------------------------------------------+
//| 枚举                                                              |
//+------------------------------------------------------------------+
enum ENUM_LOT_PRESET {
   LOT_0_01=1, LOT_0_02=2, LOT_0_03=3, LOT_0_04=4, LOT_0_05=5,
   LOT_0_06=6, LOT_0_07=7, LOT_0_08=8, LOT_0_09=9, LOT_0_10=10
};
enum ENUM_AUTO_DIR { AUTO_DIR_OFF=0, AUTO_DIR_BUY=1, AUTO_DIR_SELL=2 };
enum ENUM_EXIT_PRESET { EXIT_ASIA=0, EXIT_EUUS=1 }; // 出场预设：亚盘/欧美
enum ENUM_PANEL_POS  { PANEL_TOP=0, PANEL_MID=1, PANEL_BOTTOM=2 }; // 面板位置：右上/右中/右下


//+------------------------------------------------------------------+
//| 参数                                                              |
//+------------------------------------------------------------------+
input group "G01 基础"
input int             InpMagicNumber     = 998877;    // 魔术号
input bool            InpManageManual    = true;       // 管理手动仓位(magic=0)

input group "G02 自动续开首仓"
// AUTO_DIR_OFF  = 纯手动，EA只接管加仓/补仓/止盈
// AUTO_DIR_BUY  = 空仓后自动做多，止盈后持续循环
// AUTO_DIR_SELL = 空仓后自动做空，止盈后持续循环
input ENUM_AUTO_DIR   InpAutoDirection   = AUTO_DIR_OFF; // 续开方向(关/持续做多/持续做空)
input int             InpAutoDelayMs     = 3000;       // 止盈后等待毫秒再续开
input double          InpMaxSpreadUSD    = 1.5;        // 续开最大点差(美元)

input group "G03 手数"
input ENUM_LOT_PRESET InpLotPreset       = LOT_0_01;   // 首仓手数(0.01~0.10)
input double          InpBaseLot         = 0.01;       // 基准手数(缩放基数)

input group "G04 金字塔加仓（浮盈>0且步距满足即加仓，百分比追踪统一出场）"
input double          InpPyrStep         = 3.0;        // 加仓步距(美元)
input int             InpPyrMax          = 8;          // 最大加仓层数（每层=首仓手数）
// ★ 金字塔加仓后篮子保本SL说明：
//   SL设在：均价 + InpPyrBESLOffset（做多向上偏，做空向下偏）
//   设0 = SL卡在均价，理论保本，实际因点差约亏0.3$
//   设正值（如0.5）= SL在均价上方0.5$，最差亏损约-0.3$（点差）
//   设负值 = SL在均价下方，必然亏损，不建议
input double          InpPyrBESLOffset   = 0.0;        // 金字塔保本SL偏移(相对均价，正=盈利方向)

input group "G05 马丁补仓（L1=首仓x1；L2=L1后再触发，首仓x2）"
// 示例：首仓5000做空，L1跌23触发4977补首仓x1；L1后再跌45触发4932补首仓x2
input double          InpL1Dist          = 23.0;       // L1触发距离(美元，从最远亏损仓算)
input double          InpL2Dist          = 45.0;       // L2触发距离(美元，从L1开仓价算)
input double          InpL2Mult          = 2.0;        // L2手数=首仓x本倍率(默认2)

input group "G06 止盈"
input ENUM_EXIT_PRESET InpExitPreset   = EXIT_ASIA;   // 出场预设(亚盘/欧美)
// 追踪逻辑：峰值回撤 >= 峰值xInpTrailPct 全仓出场；主止盈gTPDist为追踪启动前兜底
input double          InpTrailPct      = 0.20;        // 峰值回撤百分比出场(默认20%)
input int             InpTrailTicks    = 2;           // 回撤确认次数(防抖)
input double          InpTrailBuf      = 0.5;         // SL缓冲(防贴太近)
input bool            InpExitTweakOn   = false;       // 允许微调(在预设基础上加减)
input double          InpTweakTP       = 0.0;         // 微调-主止盈(美元)
input double          InpTweakLockTrig = 0.0;         // 微调-锁定触发(美元)
input double          InpTweakLockProfit=0.0;         // 微调-锁定利润(美元)
input double          InpTweakTrailStart=0.0;         // 微调-追踪启动(美元)

input group "G07 硬止损"
// 硬止损自动跟随首仓手数：实际止损 = InpHardLoss × (首仓手数 / 0.01)
// 示例：首仓0.01→220$，首仓0.02→440$，首仓0.08→1760$（无需手动修改）
input double          InpHardLoss        = 220.0;      // 基准硬止损(美元，基于0.01手)

input group "G08 强平"
input int             InpFlattenRounds   = 15;         // 强平最大轮次
input int             InpFlattenSleep    = 120;        // 轮次间隔(毫秒)

input group "G09 提醒"
input bool            InpUsePush         = true;       // 推送通知
input bool            InpUseSound        = true;       // 声音提醒

input group "G10 面板"
input int              InpFontSize        = 11;         // 面板字体大小
// 右上=不遮K线顶部趋势，右中=不遮中间主体，右下=不遮底部指标区
input ENUM_PANEL_POS   InpPanelPos        = PANEL_TOP;  // 面板位置(右上/右中/右下)

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
CTrade        m_trade;
CPositionInfo m_pos;

// 锚仓
ulong  m_anchor_ticket = 0;
double m_anchor_price  = 0.0;
int    m_anchor_type   = -1;

// 节流
ulong  m_last_tick     = 0;
ulong  m_last_action   = 0;

// 追踪止盈
double m_peak_delta      = 0.0;
bool   m_trailing        = false;
bool   m_locked          = false;
double m_last_volume     = 0.0;
int    m_trail_hits      = 0;
ulong  m_last_sl_log_ms   = 0;   // 止损抬升日志节流
ulong  m_last_autoseed_log = 0;  // 续开跳过原因日志节流（约每10秒一条）

// 强平
bool   m_force_flatten   = false;
string m_force_reason    = "";

// 续开控制
bool     g_round_open       = false;  // 本轮首仓已开
datetime g_last_close_time  = 0;      // 上次清仓时间

// 金字塔保本SL待处理标志（加仓后下一tick执行，避免Sleep阻塞）
bool   m_pyr_be_pending  = false;     // 是否有待执行的保本SL

// 缩放
double gSeedLot = 0.01;
double gScale   = 1.0;

// 运行时止盈参数（缩放后）
double gTPDist     = 9.0;
double gLockDist   = 3.8;
double gLockSL     = 1.7;
double gTrailStart = 5.0;
double gTrailDD    = 2.2;
double gTrailBuf   = 0.5;
int    gTrailTicks = 2;

//+------------------------------------------------------------------+
//| 工具函数                                                          |
//+------------------------------------------------------------------+
double PresetToLot(ENUM_LOT_PRESET p){ return NormalizeDouble(((int)p)*0.01, 2); }
string ExitPresetName(){
   return (InpExitPreset==EXIT_ASIA) ? "亚盘行情" : "欧美行情";
}

void PrintExitPreset(string when){
   Print("[", EA_VERSION, "] ", when,
         " 出场预设=", ExitPresetName(),
         " | TP=", DoubleToString(gTPDist,1),
         " | 锁触=", DoubleToString(gLockDist,1),
         " | 锁利=", DoubleToString(gLockSL,1),
         " | 追启=", DoubleToString(gTrailStart,1),
         " | 回撤=", DoubleToString(gTrailDD,1),
         " | 确认=", IntegerToString(gTrailTicks),
         " | 缓冲=", DoubleToString(gTrailBuf,1),
         (InpExitTweakOn ? " | 微调=开" : " | 微调=关"),
         (InpExitTweakOn ? ("(TP"+DoubleToString(InpTweakTP,1)+
                            ",锁触"+DoubleToString(InpTweakLockTrig,1)+
                            ",锁利"+DoubleToString(InpTweakLockProfit,1)+
                            ",追启"+DoubleToString(InpTweakTrailStart,1)+")") : "")
   );
}


void ApplyScale(){
   gSeedLot = PresetToLot(InpLotPreset);
   gScale   = (InpBaseLot > 0) ? gSeedLot / InpBaseLot : 1.0;
   if(gScale <= 0) gScale = 1.0;

   // 两套预设（单位：价格美元距离）
   if(InpExitPreset == EXIT_ASIA){
      gTPDist     = 9.0;
      gLockDist   = 4.0;   // 微调对齐 (原3.8)
      gLockSL     = 1.7;
      gTrailStart = 5.0;
      gTrailDD    = 4.0;   // 数据优化：避免单根M15均幅11.9$震出 (原2.8)
   }else{ // EXIT_EUUS
      gTPDist     = 13.0;
      gLockDist   = 5.0;
      gLockSL     = 2.5;
      gTrailStart = 8.0;
      gTrailDD    = 5.0;   // 数据优化：欧美M15均幅10.7$ (原3.5)
   }

   // 允许在预设基础上微调（加减）
   if(InpExitTweakOn){
      gTPDist     += InpTweakTP;
      gLockDist   += InpTweakLockTrig;
      gLockSL     += InpTweakLockProfit;
      gTrailStart += InpTweakTrailStart;
   }

   // 最小保护：避免被调成非正数导致逻辑崩
   if(gTPDist < 0.1)     gTPDist = 0.1;
   if(gLockDist < 0.1)   gLockDist = 0.1;
   if(gLockSL < 0.0)     gLockSL = 0.0;
   if(gTrailStart < 0.1) gTrailStart = 0.1;
   if(gTrailDD < 0.1)    gTrailDD = 0.1;

   gTrailBuf   = InpTrailBuf;
   gTrailTicks = InpTrailTicks;
}

bool IsManagedMagic(ulong magic){
   if(magic == (ulong)InpMagicNumber) return true;
   if(InpManageManual && magic == 0)  return true;
   return false;
}

int CountPos(){
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      cnt++;
   }
   return cnt;
}

bool IsPyramid(ulong ticket){
   if(!m_pos.SelectByTicket(ticket)) return false;
   return StringFind(m_pos.Comment(), "Pyramid") >= 0;
}

// ★ L0已移除，仅保留L1/L2
bool HasAbyssLayer(int layer){
   string tag = (layer==1) ? "Abyss_L1" : "Abyss_L2";
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      if(StringFind(m_pos.Comment(), tag) >= 0) return true;
   }
   return false;
}

// 最近一次加仓是否为金字塔（用于分场景峰值规则：金字塔保留峰值，马丁不保留）
bool IsNewestPositionPyramid(){
   datetime latest = 0;
   ulong   ticket  = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      if(m_pos.Time() > latest){ latest = m_pos.Time(); ticket = m_pos.Ticket(); }
   }
   if(ticket == 0) return false;
   if(!m_pos.SelectByTicket(ticket)) return false;
   return (StringFind(m_pos.Comment(), "Pyramid") >= 0);
}

// 篮子：均价/总量/方向/浮盈(美元)
bool CalcBasket(double &vol, double &be, int &type, double &delta){
   vol=0; be=0; type=-1; delta=0;
   bool hasBuy=false, hasSell=false;
   double sumPV=0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      if(m_pos.PositionType()==POSITION_TYPE_BUY)  hasBuy=true;
      if(m_pos.PositionType()==POSITION_TYPE_SELL) hasSell=true;
      vol   += m_pos.Volume();
      sumPV += m_pos.PriceOpen() * m_pos.Volume();
   }
   if((hasBuy && hasSell) || (!hasBuy && !hasSell)) return false;
   if(vol <= 0) return false;
   type = hasBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   be   = sumPV / vol;
   double mid = (SymbolInfoDouble(_Symbol,SYMBOL_BID) + SymbolInfoDouble(_Symbol,SYMBOL_ASK)) / 2.0;
   delta = (type==POSITION_TYPE_BUY) ? (mid - be) : (be - mid);
   return true;
}

void RaiseBasketSL(int basketType, double slPrice){
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + 2*_Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   // 必须统一所有仓位SL，避免经纪商只平部分、留尾拖入马丁
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      double curSL = m_pos.StopLoss();
      bool valid = (basketType==POSITION_TYPE_BUY) ? (slPrice <= bid - minDist) : (slPrice >= ask + minDist);
      bool needSync = (MathAbs(slPrice - curSL) >= 0.01);  // 与目标不一致则强制同步
      if(valid && needSync && m_trade.PositionModify(m_pos.Ticket(), slPrice, m_pos.TakeProfit())){
         ulong nowMs = GetTickCount64();
         if(nowMs - m_last_sl_log_ms > 800 && MathAbs(slPrice - curSL) >= 0.2){
            m_last_sl_log_ms = nowMs;
            Print("[抬止损] ", (basketType==POSITION_TYPE_BUY?"多":"空"),
                  " 票=", (string)m_pos.Ticket(),
                  " 旧=", DoubleToString(curSL,2), " 新=", DoubleToString(slPrice,2));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 金字塔加仓后设均价保本SL                                          |
//| SL = 均价 + offset（做多向上偏，做空向下偏）                      |
//|   offset=0  → SL卡均价，理论保本（含点差约-0.3$）                 |
//|   offset>0  → SL在均价有利方向，最差接近保本                      |
//| 只往保护方向移动，绝不把已有更好的SL往回拉                         |
//+------------------------------------------------------------------+
void ApplyBreakEvenSL(int basketType, double be){
   double offset  = InpPyrBESLOffset;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + 2*_Point;
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    dig     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // 做多：SL = 均价 + offset（往上，越高越保护）
   // 做空：SL = 均价 - offset（往下，越低越保护）
   double targetSL = (basketType == POSITION_TYPE_BUY)
                     ? NormalizeDouble(be + offset, dig)
                     : NormalizeDouble(be - offset, dig);

   // 验证距当前价的距离满足经纪商最小止损要求
   bool distOK = (basketType == POSITION_TYPE_BUY)
                 ? (targetSL <= bid - minDist)
                 : (targetSL >= ask + minDist);
   if(!distOK) return;  // 价格还在均价附近，暂不挂SL

   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;

      double curSL = m_pos.StopLoss();

      // 只往保护方向移动：做多只抬高SL，做空只压低SL
      bool shouldUpdate = false;
      if(basketType == POSITION_TYPE_BUY)
         shouldUpdate = (targetSL > curSL + 0.01);
      else
         shouldUpdate = (curSL < 0.01 || targetSL < curSL - 0.01);

      if(shouldUpdate){
         if(m_trade.PositionModify(m_pos.Ticket(), targetSL, m_pos.TakeProfit())){
            cnt++;
            Print("[均价保本SL] ", (basketType==POSITION_TYPE_BUY?"多":"空"),
                  " 票=", (string)m_pos.Ticket(),
                  " 均价=", DoubleToString(be,2),
                  " 保本SL=", DoubleToString(targetSL,2),
                  " 旧SL=", DoubleToString(curSL,2));
         }
      }
   }
   if(cnt > 0)
      Print("[均价保本SL] 共更新", cnt, "单 均价=", DoubleToString(be,2),
            " 偏移=+", DoubleToString(offset,2), "$");
}

void Notify(string msg, string type){
   if(InpUsePush)  SendNotification(msg);
   if(InpUseSound) PlaySound((StringFind(type,"清仓")>=0 || StringFind(type,"止损")>=0) ? "stops.wav" : "alert.wav");
   Print("[",type,"] ", msg);
}

bool CloseAll(string reason){
   if(CountPos()==0) return true;
   // 止盈/止损必须全部清仓，不留尾（避免拖入马丁）
   for(int round=0; round<MathMax(1,InpFlattenRounds); round++){
      if(CountPos()==0) return true;
      int closed = 0;
      // 每轮尝试平掉所有仓位（不限制每轮只平一单）
      for(int i=PositionsTotal()-1; i>=0; i--){
         if(!m_pos.SelectByIndex(i)) continue;
         if(m_pos.Symbol()!=_Symbol) continue;
         if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
         if(m_trade.PositionClose(m_pos.Ticket())) closed++;
      }
      if(closed > 0) Sleep(InpFlattenSleep);
      if(CountPos()==0) return true;
   }
   if(CountPos()>0) Print("[CloseAll] 警告: 仍有 ", CountPos(), " 仓未平，原因=", reason);
   return CountPos()==0;
}


//+------------------------------------------------------------------+
//| 面板                                                              |
//+------------------------------------------------------------------+
void PanelRow(string name, int row, string text, color clr=clrWhite){
   int fs    = MathMax(8, InpFontSize);
   int lineH = fs + 6;

   ENUM_BASE_CORNER  corner;
   ENUM_ANCHOR_POINT anch;
   int yOff;

   if(InpPanelPos == PANEL_BOTTOM){
      // 右下角坐标系，行0最靠下，往上排
      int totalRows = 6;
      corner = CORNER_RIGHT_LOWER;
      anch   = ANCHOR_RIGHT_LOWER;
      yOff   = 10 + (totalRows - row) * lineH;
   } else if(InpPanelPos == PANEL_MID){
      // 右上角坐标系，加大Y偏移量到屏幕约1/3处
      corner = CORNER_RIGHT_UPPER;
      anch   = ANCHOR_RIGHT_UPPER;
      yOff   = 280 + row * lineH;
   } else {
      // 右上角（默认）
      corner = CORNER_RIGHT_UPPER;
      anch   = ANCHOR_RIGHT_UPPER;
      yOff   = 10 + row * lineH;
   }

   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anch);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yOff);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetString(0,  name, OBJPROP_FONT,      "微软雅黑");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
}

void UpdatePanel(){
   int    fs = MathMax(8, InpFontSize);

   // ── 计算实际硬止损（面板用）──────────────────────────────────────
   double ancVolHL = gSeedLot;
   if(m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket))
      ancVolHL = m_pos.Volume();
   double lotRatioHL = (InpBaseLot > 0) ? ancVolHL / InpBaseLot : 1.0;
   if(lotRatioHL <= 0) lotRatioHL = 1.0;
   double actualHL = InpHardLoss * lotRatioHL;

   // ── 行0：版本 | 预设 | 续开方向 | 强止损 ─────────────────────────
   string dirStr = (InpAutoDirection==AUTO_DIR_OFF)  ? "手动" :
                   (InpAutoDirection==AUTO_DIR_BUY)   ? "自动多↑" : "自动空↓";
   PanelRow("VP_0", 0,
            EA_VERSION + "  " + ExitPresetName() + "  " + dirStr +
            "  强止损=" + DoubleToString(actualHL,0) + "$",
            (InpAutoDirection==AUTO_DIR_OFF) ? clrSilver :
            (InpAutoDirection==AUTO_DIR_BUY) ? clrLime   : clrOrangeRed);

   // ── 行1：篮子核心状态 ──────────────────────────────────────────────
   double vol=0, be=0, delta=0; int type=-1;
   bool hasBasket = CalcBasket(vol, be, type, delta);
   if(hasBasket){
      string side  = (type==POSITION_TYPE_BUY) ? "多▲" : "空▼";
      string dpStr = (delta>=0 ? "+" : "") + DoubleToString(delta,2) + "$";
      PanelRow("VP_1", 1,
               side + " 量=" + DoubleToString(vol,2) +
               "  均=" + DoubleToString(be,2) +
               "  浮盈=" + dpStr,
               delta >= 0 ? clrLime : clrOrangeRed);
   } else {
      PanelRow("VP_1", 1, "空仓 — 等待开仓", clrSilver);
   }

   // ── 行2：仓位结构（金字塔层数 + 马丁层状态）─────────────────────
   int pyrCnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      if(IsPyramid(m_pos.Ticket())) pyrCnt++;
   }
   bool l1on = HasAbyssLayer(1), l2on = HasAbyssLayer(2);
   string structStr = "金字塔=" + IntegerToString(pyrCnt) + "/" + IntegerToString(InpPyrMax);
   structStr += "  马丁: " + (l1on ? "L1✓" : "L1-") + " " + (l2on ? "L2✓" : "L2-");
   if(m_locked)   structStr += "  [保本锁]";
   if(m_trailing) structStr += "  [追踪中]";
   PanelRow("VP_2", 2, structStr,
            (l1on || l2on) ? clrOrangeRed : clrSilver);

   // ── 行3：止盈状态 ─────────────────────────────────────────────────
   string tpStr;
   if(m_force_flatten){
      tpStr = "⚠ 强平执行中";
   } else if(m_trailing){
      double exitLine = m_peak_delta * (1.0 - InpTrailPct);
      tpStr = "追踪 峰值+" + DoubleToString(m_peak_delta,2) +
              "$  出场≤+" + DoubleToString(exitLine,2) + "$";
   } else {
      tpStr = "等待追踪(启动≥+" + DoubleToString(gTrailStart,1) +
              "$)  主TP=" + DoubleToString(gTPDist,1) + "$";
   }
   PanelRow("VP_3", 3, tpStr,
            m_force_flatten ? clrRed : (m_trailing ? clrLime : clrSilver));

   // ── 行4：马丁预测（触发价 → 出场价，精简一行）───────────────────
   string predStr = "马丁预测: ";
   if(m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket)){
      double ancVol   = m_pos.Volume();
      double ancPrice = m_pos.PriceOpen();
      int    ancType  = (int)m_pos.PositionType();
      double curVol=0, curBE=0, curDelta=0; int curType=-1;

      if(CalcBasket(curVol, curBE, curType, curDelta)){
         double l1Price = (ancType==POSITION_TYPE_BUY) ? ancPrice-InpL1Dist : ancPrice+InpL1Dist;
         double l1VolA  = curVol + ancVol;
         double l1BE    = (curBE*curVol + l1Price*ancVol) / l1VolA;
         double l1Exit  = (ancType==POSITION_TYPE_BUY) ? l1BE+gTPDist : l1BE-gTPDist;

         double l2Price = (ancType==POSITION_TYPE_BUY) ? l1Price-InpL2Dist : l1Price+InpL2Dist;
         double l2Lot   = ancVol * MathMax(0.1, InpL2Mult);
         double l2VolA  = l1VolA + l2Lot;
         double l2BE    = (l1BE*l1VolA + l2Price*l2Lot) / l2VolA;
         double l2Exit  = (ancType==POSITION_TYPE_BUY) ? l2BE+gTPDist : l2BE-gTPDist;

         if(!l1on && !l2on){
            predStr += "L1@" + DoubleToString(l1Price,1) + "→出" + DoubleToString(l1Exit,1) +
                       "  L2@" + DoubleToString(l2Price,1) + "→出" + DoubleToString(l2Exit,1);
         } else if(l1on && !l2on){
            double curExit = (ancType==POSITION_TYPE_BUY) ? curBE+gTPDist : curBE-gTPDist;
            predStr += "L1已开→出" + DoubleToString(curExit,1) +
                       "  L2@" + DoubleToString(l2Price,1) + "→出" + DoubleToString(l2Exit,1);
         } else {
            double curExit = (ancType==POSITION_TYPE_BUY) ? curBE+gTPDist : curBE-gTPDist;
            predStr += "L1+L2已开  均=" + DoubleToString(curBE,1) +
                       "  出场@" + DoubleToString(curExit,1);
         }
      } else {
         predStr += "空仓";
      }
   } else {
      predStr += "无首仓";
   }
   PanelRow("VP_4", 4, predStr, clrYellow);

   // 清除多余行（原行5）
   ObjectDelete(0, "VP_5");
}

void ClearPanel(){
   for(int i=0; i<8; i++) ObjectDelete(0, "VP_"+IntegerToString(i));
}

//+------------------------------------------------------------------+
//| 自动续开首仓                                                      |
//+------------------------------------------------------------------+
void TryAutoSeed(ulong nowMs){
   if(InpAutoDirection == AUTO_DIR_OFF) return;
   if(g_round_open) return;
   if(nowMs <= m_last_action) return;

   // 止盈后等待
   if(g_last_close_time > 0){
      ulong elapsed = (ulong)(TimeCurrent() - g_last_close_time) * 1000;
      if(elapsed < (ulong)MathMax(500, InpAutoDelayMs)) return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return;

   // 点差检查
   double spread = ask - bid;
   if(spread > InpMaxSpreadUSD){
      if(nowMs - m_last_autoseed_log > 10000){
         m_last_autoseed_log = nowMs;
         Print("[续开跳过] 点差过大 当前=", DoubleToString(spread,2), " 最大=", DoubleToString(InpMaxSpreadUSD,1), " 可调大 G02 续开最大点差");
      }
      return;
   }

   bool res = false;
   if(InpAutoDirection == AUTO_DIR_BUY){
      res = m_trade.Buy(gSeedLot, _Symbol, ask, 0, 0, "Seed_Auto");
      if(res){
         g_round_open = true;
         Notify("自动续开做多 " + DoubleToString(gSeedLot,2) + "手 @ " + DoubleToString(ask,2), "开仓");
         m_last_action = nowMs + 1000;
      }
   }else if(InpAutoDirection == AUTO_DIR_SELL){
      res = m_trade.Sell(gSeedLot, _Symbol, bid, 0, 0, "Seed_Auto");
      if(res){
         g_round_open = true;
         Notify("自动续开做空 " + DoubleToString(gSeedLot,2) + "手 @ " + DoubleToString(bid,2), "开仓");
         m_last_action = nowMs + 1000;
      }
   }
}

//+------------------------------------------------------------------+
//| 金字塔加仓                                                        |
//| TP=0，追踪止盈统一管理出场                                        |
//| ★ 加仓成功后立即把篮子所有仓SL设到新均价-缓冲（均价保本）         |
//|   防止加仓后反转导致两单一起被拖入马丁                            |
//+------------------------------------------------------------------+
void TryPyramid(ulong nowMs, int pyrCnt, double delta,
                double highest_pyr_buy, double lowest_pyr_sell){
   if(nowMs <= m_last_action) return;
   if(pyrCnt >= InpPyrMax) return;
   if(delta <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double cur = (m_anchor_type==POSITION_TYPE_BUY) ? bid : ask;

   double ref = 0;
   if(m_anchor_type == POSITION_TYPE_BUY)
      ref = (highest_pyr_buy > 0) ? highest_pyr_buy : m_anchor_price;
   else
      ref = (lowest_pyr_sell < 999999.0) ? lowest_pyr_sell : m_anchor_price;

   double dist = (m_anchor_type==POSITION_TYPE_BUY) ? (cur - ref) : (ref - cur);
   if(dist < InpPyrStep) return;

   // 手数同步首仓
   double vol = 0.01;
   if(m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket))
      vol = m_pos.Volume();
   if(vol <= 0) vol = gSeedLot;
   vol = NormalizeDouble(vol, 2);
   if(vol <= 0) vol = 0.01;

   // TP=0，追踪止盈统一管理
   bool res = false;
   if(m_anchor_type==POSITION_TYPE_BUY)
      res = m_trade.Buy(vol,  _Symbol, ask, 0, 0, "Pyramid");
   else
      res = m_trade.Sell(vol, _Symbol, bid, 0, 0, "Pyramid");

   if(res){
      Notify("金字塔加仓 " + DoubleToString(vol,2) + "手 层=" + IntegerToString(pyrCnt+1), "加仓");
      m_last_action    = nowMs + 1000;
      m_pyr_be_pending = true;   // ★ 标记下一tick执行保本SL，避免Sleep阻塞
   }
}


// 获取锚仓(首仓)手数，用于金字塔/马丁与首仓同量或倍数
double GetAnchorVolume(){
   if(m_anchor_ticket == 0 || !m_pos.SelectByTicket(m_anchor_ticket)) return gSeedLot;
   double v = m_pos.Volume();
   return (v > 0) ? v : gSeedLot;
}

//+------------------------------------------------------------------+
//| 马丁补仓（★ 已去L0；L1=首仓×1；L2=首仓×L2Mult）                 |
//|                                                                  |
//| 步距逻辑说明：                                                    |
//|   distFarthest = 所有仓中最远亏损价 到 当前价 的距离              |
//|   L1触发：distFarthest >= InpL1Dist(23)，以首仓价起算             |
//|   L2触发：HasAbyssLayer(1)已补 && distFarthest >= InpL2Dist(45)   |
//|           此时最远仓是L1，distFarthest是从L1价起算，              |
//|           即L1开仓后再跌45美元触发 ✓ 符合马丁逻辑                |
//|                                                                  |
//| 手数逻辑说明：                                                    |
//|   anchorVol = 首仓实际手数（GetAnchorVolume）                     |
//|   L1 = anchorVol × 1（1:1）                                      |
//|   L2 = anchorVol × InpL2Mult（默认2，即首仓×2）                  |
//+------------------------------------------------------------------+
void TryAbyss(ulong nowMs, double distFarthest){
   if(nowMs <= m_last_action) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double anchorVol = GetAnchorVolume();

   // L2手数 = 首仓 × InpL2Mult（默认2）
   double lotL2 = NormalizeDouble(anchorVol * MathMax(0.1, InpL2Mult), 2);
   if(lotL2 <= 0) lotL2 = 0.01;

   // ★ L0 已移除

   // L1 = 首仓手数 × 1（1:1），从最远仓起跌/涨 InpL1Dist(23美元) 触发
   if(!HasAbyssLayer(1) && distFarthest >= InpL1Dist){
      bool res = (m_anchor_type==POSITION_TYPE_BUY) ?
                  m_trade.Buy(anchorVol,  _Symbol, ask, 0, 0, "Abyss_L1") :
                  m_trade.Sell(anchorVol, _Symbol, bid, 0, 0, "Abyss_L1");
      if(res){
         Notify("L1补仓 " + DoubleToString(anchorVol,2) + "手(首仓×1) 距=" + DoubleToString(distFarthest,1) + "$", "补仓");
         m_last_action = nowMs + 1000;
         return;
      }
   }

   // L2 = 首仓手数 × 2，在L1开仓后再跌/涨 InpL2Dist(45美元) 触发
   // （此时 distFarthest 从 L1 开仓价起算，故等价于"L1基础上再跌45"）
   if(HasAbyssLayer(1) && !HasAbyssLayer(2) && distFarthest >= InpL2Dist){
      bool res = (m_anchor_type==POSITION_TYPE_BUY) ?
                  m_trade.Buy(lotL2,  _Symbol, ask, 0, 0, "Abyss_L2") :
                  m_trade.Sell(lotL2, _Symbol, bid, 0, 0, "Abyss_L2");
      if(res){
         Notify("L2补仓 " + DoubleToString(lotL2,2) + "手(首仓×" + DoubleToString(InpL2Mult,1) + ") 距=" + DoubleToString(distFarthest,1) + "$", "补仓");
         m_last_action = nowMs + 1000;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| 止盈模块                                                          |
//| 返回 true = 已触发全仓清仓                                        |
//|                                                                  |
//| 核心逻辑（两条规则，互相独立）：                                  |
//|   ① 追踪启动后：delta <= peak × (1 - InpTrailPct) → CloseAll    |
//|      即峰值回撤20%全部出场，峰值越大容忍回撤越大，顺势博趋势      |
//|   ② 追踪未启动（delta < gTrailStart）：delta >= gTPDist → CloseAll|
//|      主止盈兜底，防止小行情不触追踪但已超止盈线时无法出场         |
//|                                                                  |
//| 马丁补仓后峰值重置为当前delta（敏感止盈，均价已下移）             |
//| 金字塔加仓保留峰值（顺势，不应被震出）                            |
//+------------------------------------------------------------------+
bool CheckTP(double vol, double be, int bType, double delta){
   // ===== 仓量变化处理 =====
   if(MathAbs(vol - m_last_volume) > 0.000001){
      if(vol > m_last_volume){
         if(IsNewestPositionPyramid()){
            // 金字塔加仓：保留峰值，续博趋势
            m_last_volume = vol;
         }else{
            // 马丁补仓：峰值重置为当前delta，敏感止盈
            m_peak_delta  = delta;
            m_last_volume = vol;
            m_trail_hits  = 0;
         }
      }else{
         // 减仓：只更新仓量，保留峰值
         m_last_volume = vol;
      }
   }
   if(delta > m_peak_delta) m_peak_delta = delta;

   // ===== 锁定保护（浮盈达gLockDist，给全部仓位挂保本SL）=====
   if(!m_locked && delta >= gLockDist){
      double slP = (bType==POSITION_TYPE_BUY) ? (be + gLockSL) : (be - gLockSL);
      RaiseBasketSL(bType, slP);
      m_locked = true;
   }

   // ===== 追踪启动 =====
   if(!m_trailing && delta >= gTrailStart){
      m_trailing = true; m_trail_hits = 0;
      Print("[追踪启动] 预设=", ExitPresetName(),
            " 浮盈=", DoubleToString(delta,2), "$",
            " 启动阈=", DoubleToString(gTrailStart,1), "$",
            " 出场线=峰值x", DoubleToString(1.0-InpTrailPct,2));
   }

   bool   trigClose   = false;
   string closeReason = "";

   if(m_trailing){
      // ★ 百分比追踪：峰值回撤20%全仓出场
      // 动态SL同步上移（视觉上锁利润，实际出场靠EA的CloseAll）
      double lockDelta = m_peak_delta * (1.0 - InpTrailPct) - gTrailBuf;
      if(lockDelta > 0){
         double dynSL = (bType==POSITION_TYPE_BUY) ? (be + lockDelta) : (be - lockDelta);
         RaiseBasketSL(bType, dynSL);
      }
      // 出场判断：当前delta <= 峰值 × (1 - 20%)
      if(delta <= m_peak_delta * (1.0 - InpTrailPct)){
         m_trail_hits++;
         if(m_trail_hits >= MathMax(1, gTrailTicks)){
            trigClose   = true;
            closeReason = "百分比追踪止盈 峰值+" + DoubleToString(m_peak_delta,2) +
                          "$ 回撤" + DoubleToString(InpTrailPct*100,0) + "% 出场+" +
                          DoubleToString(delta,2) + "$";
         }
      }else{
         m_trail_hits = 0;
      }
   }else{
      // 追踪未启动：主止盈兜底
      m_trail_hits = 0;
      if(delta >= gTPDist){
         trigClose   = true;
         closeReason = "主止盈 +" + DoubleToString(delta,2) + "$";
      }
   }

   if(trigClose){
      Notify(closeReason, "清仓");
      CloseAll(closeReason);
      g_last_close_time = TimeCurrent();
      g_round_open      = false;
      m_force_flatten   = false;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit(){
   // 本策略仅用于 XAUUSD（黄金）
   if(StringFind(_Symbol, "XAUUSD") < 0 && _Symbol != "GOLD"){
      Alert("本EA仅用于 XAUUSD，当前品种: ", _Symbol);
      return INIT_FAILED;
   }
   if(_Period != PERIOD_M15){ Alert("EA须在M15运行"); return INIT_FAILED; }
   ApplyScale();
   if(gSeedLot <= 0){ Alert("首仓手数无效"); return INIT_FAILED; }
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetTypeFillingBySymbol(_Symbol);
   m_trade.SetDeviationInPoints(50);
   Print("[", EA_VERSION, "] 启动 首仓=", DoubleToString(gSeedLot,2), " 缩放=", DoubleToString(gScale,2));
   PrintExitPreset("启动");
   Print("[", EA_VERSION, "] 马丁配置: L1=首仓×1@", DoubleToString(InpL1Dist,1),
         "$ | L2=首仓×", DoubleToString(InpL2Mult,1), "@L1后再跌", DoubleToString(InpL2Dist,1), "$");
   Print("[", EA_VERSION, "] 止盈: 百分比追踪", DoubleToString(InpTrailPct*100,0), "% | 追踪启动阈=", DoubleToString(gTrailStart,1), "$ | 主止盈兜底=", DoubleToString(gTPDist,1), "$");
   Print("[", EA_VERSION, "] 金字塔保本SL: 加仓后SL=均价+", DoubleToString(InpPyrBESLOffset,1), "$ | 步距=", DoubleToString(InpPyrStep,1), "$ | 最大层=", IntegerToString(InpPyrMax));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){ ClearPanel(); Comment(""); }

//+------------------------------------------------------------------+
//| OnTick 主循环                                                     |
//+------------------------------------------------------------------+
void OnTick(){
   // 节流 200ms
   ulong nowMs = GetTickCount64();
   if(nowMs - m_last_tick < 200) return;
   m_last_tick = nowMs;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;

   // 强平续执
   if(m_force_flatten){
      if(CloseAll(m_force_reason)){
         g_last_close_time = TimeCurrent();
         g_round_open      = false;
         m_force_flatten   = false;
      }
      UpdatePanel();
      return;
   }

   // ===== 统计持仓 =====
   int    total_cnt   = 0;
   int    pyr_cnt     = 0;
   double net_profit  = 0;
   double low_buy     = 9999999.0;   // 多头中最低开仓价（补仓参考）
   double high_sell   = 0.0;         // 空头中最高开仓价（补仓参考）
   double high_pyr_buy  = 0.0;       // 金字塔最高买入价
   double low_pyr_sell  = 999999.0;  // 金字塔最低卖出价
   datetime earliest   = D'2099.01.01';
   ulong   cur_anchor  = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;

      total_cnt++;
      net_profit += m_pos.Profit() + m_pos.Commission() + m_pos.Swap();

      if(m_pos.Time() < earliest){ earliest = m_pos.Time(); cur_anchor = m_pos.Ticket(); }

      if(m_pos.PositionType()==POSITION_TYPE_BUY){
         if(m_pos.PriceOpen() < low_buy)  low_buy  = m_pos.PriceOpen();
      }else{
         if(m_pos.PriceOpen() > high_sell) high_sell = m_pos.PriceOpen();
      }
   }

   // ===== 空仓分支 =====
   if(total_cnt == 0){
      g_round_open = false;
      m_anchor_ticket = 0; m_anchor_price = 0; m_anchor_type = -1;
      m_peak_delta = 0; m_trailing = false; m_locked = false;
      m_last_volume = 0; m_trail_hits = 0;
      m_pyr_be_pending = false;   // 清除保本SL待处理标志


      TryAutoSeed(nowMs);
      UpdatePanel();
      return;
   }

   // 有仓：标记首仓已开
   if(!g_round_open) g_round_open = true;

   // 确定锚仓
   if(cur_anchor != 0 && m_pos.SelectByTicket(cur_anchor)){
      m_anchor_ticket = cur_anchor;
      m_anchor_price  = m_pos.PriceOpen();
      m_anchor_type   = (int)m_pos.PositionType();
   }else{
      m_anchor_ticket = 0;
   }
   if(m_anchor_ticket == 0){ UpdatePanel(); return; }

   // ===== 硬止损（跟随实际首仓手数自动缩放）=====
   double ancVolForHL = (m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket))
                        ? m_pos.Volume() : gSeedLot;
   double lotRatio  = (InpBaseLot > 0) ? ancVolForHL / InpBaseLot : 1.0;
   if(lotRatio <= 0) lotRatio = 1.0;
   double hardLoss  = InpHardLoss * lotRatio;
   if(hardLoss > 0 && net_profit <= -hardLoss){
      string reason = "硬止损 亏损=" + DoubleToString(net_profit,2) + "$";
      Notify(reason, "止损");
      m_force_flatten = true;
      m_force_reason  = reason;
      CloseAll(reason);
      g_last_close_time = TimeCurrent();
      g_round_open      = false;
      m_force_flatten   = false;
      m_last_action     = nowMs + 1000;
      UpdatePanel();
      return;
   }

   // 统计金字塔层数与价格
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      ulong tk = m_pos.Ticket();
      if(tk == m_anchor_ticket) continue;
      if(IsPyramid(tk)){
         pyr_cnt++;
         if(m_anchor_type==POSITION_TYPE_BUY && m_pos.PriceOpen() > high_pyr_buy)
            high_pyr_buy = m_pos.PriceOpen();
         if(m_anchor_type==POSITION_TYPE_SELL && m_pos.PriceOpen() < low_pyr_sell)
            low_pyr_sell = m_pos.PriceOpen();
      }
   }

   // ===== 篮子指标 =====
   double bVol=0, bBE=0, bDelta=0; int bType=-1;
   if(!CalcBasket(bVol, bBE, bType, bDelta)){ UpdatePanel(); return; }

   // ===== 金字塔保本SL（加仓后下一tick执行，确保新仓已在篮子里）=====
   if(m_pyr_be_pending){
      m_pyr_be_pending = false;
      ApplyBreakEvenSL(bType, bBE);
   }

   // ===== 止盈检查（优先） =====
   if(CheckTP(bVol, bBE, bType, bDelta)){
      UpdatePanel();
      return;
   }

   // ===== 交易冷却检查 =====
   if(nowMs <= m_last_action){ UpdatePanel(); return; }

   // ===== 补仓距离（从最远亏损仓位计算） =====
   double distFarthest = 0;
   double curP = (m_anchor_type==POSITION_TYPE_BUY) ?
                  SymbolInfoDouble(_Symbol,SYMBOL_BID) :
                  SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(low_buy  == 9999999.0) low_buy  = m_anchor_price;
   if(high_sell == 0.0)      high_sell = m_anchor_price;
   distFarthest = (m_anchor_type==POSITION_TYPE_BUY) ?
                   (low_buy  - curP) : (curP - high_sell);

   // ===== 金字塔加仓 =====
   TryPyramid(nowMs, pyr_cnt, bDelta, high_pyr_buy, low_pyr_sell);

   // ===== 马丁补仓 =====
   TryAbyss(nowMs, distFarthest);

   UpdatePanel();
}
