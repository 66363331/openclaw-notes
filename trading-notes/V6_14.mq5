//+------------------------------------------------------------------+
//| V6.14 半自动印钞机（全参数版）
//| 更新日期: 2026-03-17
//| 改动：
//|   A) 均价保本SL增加开关+0真关闭
//|   B) 删除旧马丁模式，只保留6档
//|   C) 大波动止血：面板只更新不删建+CloseAll去Sleep+合并仓位扫描
//|   D) PyrBE延迟激活(InpPyrBEDelay分钟)，防止正常回调过早扫出
//|   E) bDelta改用bid/ask（与出场成交价一致），删除distFarthest死代码
//|   F) 默认参数优化：PyrBE=1.0 LockKeep=3.0 TrailStart=4.5
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

const string EA_VERSION = "V6.14";

//+------------------------------------------------------------------+
//| 枚举                                                              |
//+------------------------------------------------------------------+
enum ENUM_LOT_PRESET {
   LOT_0_01=1, LOT_0_02=2, LOT_0_03=3, LOT_0_04=4, LOT_0_05=5,
   LOT_0_06=6, LOT_0_07=7, LOT_0_08=8, LOT_0_09=9, LOT_0_10=10
};
enum ENUM_AUTO_DIR { AUTO_DIR_OFF=0, AUTO_DIR_BUY=1, AUTO_DIR_SELL=2 };
enum ENUM_PANEL_POS { PANEL_TOP=0, PANEL_MID=1, PANEL_BOTTOM=2 };

//+------------------------------------------------------------------+
//| 参数                                                              |
//+------------------------------------------------------------------+
input group "===== 基础设置 ====="
input int             InpMagicNumber     = 99812;     // 魔术号
input bool            InpManageManual    = true;       // 管理手动仓位(magic=0)

input group "===== 自动续开首仓 ====="
input ENUM_AUTO_DIR   InpAutoDirection   = AUTO_DIR_OFF; // 续开方向(关/持续做多/持续做空)
input int             InpAutoDelayMs     = 3000;       // 止盈后等待毫秒再续开
input double          InpMaxSpreadUSD    = 1.5;        // 续开最大点差(美元)

input group "===== 首仓手数 ====="
input ENUM_LOT_PRESET InpLotPreset       = LOT_0_03;   // 首仓手数(0.01~0.10)
input double          InpBaseLot         = 0.03;       // 基准手数(缩放基数)

input group "===== 金字塔加仓（浮盈顺势加仓） ====="
input double          InpPyrStep         = 3.0;        // 加仓步距(美元)
input int             InpPyrMax          = 4;          // 最大加仓层数
input bool            InpPyrBEEnable     = true;       // 加仓后均价保本SL开关
input double          InpPyrBESLOffset   = 1.0;        // 保本SL偏移(0=关闭,正=盈利侧,负=留回撤,$)
input int             InpPyrBEDelay      = 15;         // 保本SL延迟激活(分钟,0=立即)

input group "===== 金字塔-自定义每层手数（0=跳过该层） ====="
input bool            InpPyrCustomLotsEnable = false;  // 开启自定义手数(关=每层等于首仓)
input double          InpPyrLot1         = 0.0;        // 第1次加仓手数(0=跳过此层)
input double          InpPyrLot2         = 0.0;        // 第2次加仓手数(0=跳过此层)
input double          InpPyrLot3         = 0.0;        // 第3次加仓手数(0=跳过此层)
input double          InpPyrLot4         = 0.0;        // 第4次加仓手数(0=跳过此层)
input double          InpPyrLot5         = 0.0;        // 第5次加仓手数(0=跳过此层)
input double          InpPyrLot6         = 0.0;        // 第6次加仓手数(0=跳过此层)
input double          InpPyrLot7         = 0.0;        // 第7次加仓手数(0=跳过此层)
input double          InpPyrLot8         = 0.0;        // 第8次加仓手数(0=跳过此层)

input group "===== 马丁补仓-6档（绝对手数，0=关闭该档） ====="
input double          InpM_Dist1         = 28.0;       // 第1档步距($，0=关闭)
input double          InpM_Lot1          = 0.03;       // 第1档手数(绝对值，0=关闭)
input double          InpM_Dist2         = 45.0;       // 第2档步距($，0=关闭)
input double          InpM_Lot2          = 0.06;       // 第2档手数(绝对值，0=关闭)
input double          InpM_Dist3         = 0.0;        // 第3档步距($，0=关闭)
input double          InpM_Lot3          = 0.0;        // 第3档手数(绝对值，0=关闭)
input double          InpM_Dist4         = 0.0;        // 第4档步距($，0=关闭)
input double          InpM_Lot4          = 0.0;        // 第4档手数(绝对值，0=关闭)
input double          InpM_Dist5         = 0.0;        // 第5档步距($，0=关闭)
input double          InpM_Lot5          = 0.0;        // 第5档手数(绝对值，0=关闭)
input double          InpM_Dist6         = 0.0;        // 第6档步距($，0=关闭)
input double          InpM_Lot6          = 0.0;        // 第6档手数(绝对值，0=关闭)

input group "===== 出场-总控 ====="
input bool            InpExitEnable      = true;       // 出场总开关(关=不做任何自动出场)

input group "===== 出场-主止盈 ====="
input bool            InpTpEnable        = true;       // 主止盈开关
input double          InpTpDist          = 13.0;       // 主止盈距离($，0=关闭)

input group "===== 出场-锁利（浮盈到位后挂保本止损） ====="
input bool            InpLockEnable      = true;       // 锁利开关
input double          InpLockTriggerDist = 3.5;        // 锁利触发距离($，0=关闭)
input double          InpLockKeepDist    = 3.0;        // 锁利保留距离/止损偏移($，0=关闭)

input group "===== 出场-追踪止盈（回撤距离$>0优先；否则用回撤百分比%） ====="
input bool            InpTrailEnable     = true;       // 追踪开关
input double          InpTrailStartDist  = 4.5;        // 追踪启动距离($，0=关闭)
input double          InpTrailDrawdownDist = 0.0;      // 回撤距离($，>0优先生效，0=用百分比)
input double          InpTrailPct        = 0.20;       // 回撤百分比(0.20=20%，仅回撤距离=0时生效)
input int             InpTrailTicks      = 2;          // 回撤确认次数(防抖)
input double          InpTrailBuf        = 0.5;        // 止损缓冲($，防贴太近)

input group "===== 硬止损 ====="
input double          InpHardLoss        = 660.0;      // 基准硬止损(美元，基于0.01手)

input group "===== 强平 ====="
input int             InpFlattenRounds   = 15;         // 强平最大轮次(每tick处理一轮)

input group "===== 提示音（三类声音+独立开关） ====="
input bool            InpSoundEnable     = true;       // 声音总开关
input bool            InpSoundOpenEnable = true;       // 开仓/加仓/补仓 声音
input bool            InpSoundCloseEnable= true;       // 止盈/清仓 声音
input bool            InpSoundStopEnable = true;       // 止损/强制止损 声音
input string          InpSoundOpenFile   = "alert.wav";  // 开仓声音文件
input string          InpSoundCloseFile  = "news.wav";   // 止盈声音文件
input string          InpSoundStopFile   = "stops.wav";  // 止损声音文件

input group "===== 推送 ====="
input bool            InpUsePush         = true;       // 推送通知

input group "===== 面板 ====="
input int              InpFontSize        = 11;        // 面板字体大小
input ENUM_PANEL_POS   InpPanelPos        = PANEL_BOTTOM; // 面板位置(右上/右中/右下)


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
ulong  m_last_panel_ms = 0;   // C1: 面板刷新节流

// 追踪止盈
double m_peak_delta      = 0.0;
double m_peak_price      = 0.0;
bool   m_trailing        = false;
bool   m_locked          = false;
double m_last_volume     = 0.0;
int    m_trail_hits      = 0;
ulong  m_last_sl_log_ms   = 0;
ulong  m_last_autoseed_log = 0;

// 强平（C2: 分tick处理）
bool   m_force_flatten   = false;
string m_force_reason    = "";
int    m_flatten_round   = 0;   // 当前强平轮次

// 续开控制
bool     g_round_open       = false;
datetime g_last_close_time  = 0;

// 金字塔保本SL待处理标志
bool     m_pyr_be_pending     = false;
datetime m_pyr_be_delay_start = 0;      // 延迟激活计时起点

// 缩放
double gSeedLot = 0.01;
double gScale   = 1.0;

// 运行时止盈参数
double gTPDist     = 9.0;
double gLockDist   = 4.0;
double gLockSL     = 1.7;
double gTrailStart = 5.0;
double gTrailDD    = 0.0;
double gTrailBuf   = 0.5;
int    gTrailTicks = 2;
bool   gTrailUseDistance = false;

// 马丁6档数组
double gM_Dist[6];
double gM_Lot[6];

// 金字塔自定义手数数组
double gPyrLot[8];

// 声音文件（运行时使用，经过校验/回退）
string gSoundOpenFile  = "alert.wav";
string gSoundCloseFile = "news.wav";
string gSoundStopFile  = "stops.wav";

// ===== C3: 仓位扫描缓存（每tick开头填充一次）=====
struct PosCache {
   int    totalCnt;
   double netProfit;
   double lowBuy;
   double highSell;
   double highPyrBuy;
   double lowPyrSell;
   datetime earliest;
   ulong  anchorTicket;
   // 篮子
   double bVol;
   double bBE;
   int    bType;
   double bDelta;
   bool   basketValid;
   // 马丁槽位
   bool   abyOpened[6];
   double abyPrice[6];
   int    abyFilled;
   // 金字塔槽位
   bool   pyrOpened[8];
   int    pyrCnt;
};
PosCache g_cache;

//+------------------------------------------------------------------+
//| 工具函数                                                          |
//+------------------------------------------------------------------+
double PresetToLot(ENUM_LOT_PRESET p){ return NormalizeDouble(((int)p)*0.01, 2); }

bool IsManagedMagic(ulong magic){
   if(magic == (ulong)InpMagicNumber) return true;
   if(InpManageManual && magic == 0)  return true;
   return false;
}

//+------------------------------------------------------------------+
//| C3: 一次性仓位扫描，填充g_cache                                   |
//+------------------------------------------------------------------+
void ScanAllPositions(){
   g_cache.totalCnt    = 0;
   g_cache.netProfit   = 0;
   g_cache.lowBuy      = 9999999.0;
   g_cache.highSell    = 0.0;
   g_cache.highPyrBuy  = 0.0;
   g_cache.lowPyrSell  = 999999.0;
   g_cache.earliest    = D'2099.01.01';
   g_cache.anchorTicket= 0;
   g_cache.bVol        = 0;
   g_cache.bBE         = 0;
   g_cache.bType       = -1;
   g_cache.bDelta      = 0;
   g_cache.basketValid = false;
   g_cache.abyFilled   = 0;
   g_cache.pyrCnt      = 0;

   ArrayInitialize(g_cache.abyOpened, false);
   ArrayInitialize(g_cache.abyPrice, 0.0);
   ArrayInitialize(g_cache.pyrOpened, false);

   bool hasBuy = false, hasSell = false;
   double sumPV = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;

      g_cache.totalCnt++;
      g_cache.netProfit += m_pos.Profit() + m_pos.Commission() + m_pos.Swap();

      double opPrice = m_pos.PriceOpen();
      double vol     = m_pos.Volume();
      int    pType   = (int)m_pos.PositionType();
      string cmt     = m_pos.Comment();
      ulong  tk      = m_pos.Ticket();

      // 锚仓（最早）
      if(m_pos.Time() < g_cache.earliest){
         g_cache.earliest     = m_pos.Time();
         g_cache.anchorTicket = tk;
      }

      // 方向+篮子数据
      if(pType == POSITION_TYPE_BUY){
         hasBuy = true;
         if(opPrice < g_cache.lowBuy) g_cache.lowBuy = opPrice;
      } else {
         hasSell = true;
         if(opPrice > g_cache.highSell) g_cache.highSell = opPrice;
      }
      g_cache.bVol += vol;
      sumPV += opPrice * vol;

      // 金字塔识别
      int pyrPos = StringFind(cmt, "PYR_L");
      if(pyrPos >= 0){
         g_cache.pyrCnt++;
         string pyrNum = StringSubstr(cmt, pyrPos+5, 1);
         int pyrLayer = (int)StringToInteger(pyrNum);
         if(pyrLayer >= 1 && pyrLayer <= 8)
            g_cache.pyrOpened[pyrLayer-1] = true;
         // 金字塔价格统计（排除锚仓在后面做）
      } else if(StringFind(cmt, "Pyramid") >= 0){
         g_cache.pyrCnt++;
      }

      // 马丁识别
      int abyPos = StringFind(cmt, "ABY_L");
      if(abyPos < 0) abyPos = StringFind(cmt, "Abyss_L");
      if(abyPos >= 0){
         int numStart = abyPos + ((StringFind(cmt, "ABY_L") >= 0) ? 5 : 7);
         string abyNum = StringSubstr(cmt, numStart, 1);
         int abyLayer = (int)StringToInteger(abyNum);
         if(abyLayer >= 1 && abyLayer <= 6){
            g_cache.abyOpened[abyLayer-1] = true;
            g_cache.abyPrice[abyLayer-1]  = opPrice;
         }
      }
   }

   // 马丁已补档数
   for(int k=0; k<6; k++) if(g_cache.abyOpened[k]) g_cache.abyFilled++;

   // 篮子有效性
   if((hasBuy && hasSell) || (!hasBuy && !hasSell) || g_cache.bVol <= 0){
      g_cache.basketValid = false;
   } else {
      g_cache.basketValid = true;
      g_cache.bType = hasBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      g_cache.bBE   = sumPV / g_cache.bVol;
      double exitP = (g_cache.bType==POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      g_cache.bDelta = (g_cache.bType==POSITION_TYPE_BUY) ? (exitP - g_cache.bBE) : (g_cache.bBE - exitP);
   }
}

// 补充金字塔价格统计（需要锚仓信息，在确定锚仓后调用）
void CachePyrPrices(){
   g_cache.highPyrBuy = 0;
   g_cache.lowPyrSell = 999999.0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      ulong tk = m_pos.Ticket();
      if(tk == m_anchor_ticket) continue;
      string cmt = m_pos.Comment();
      if(StringFind(cmt, "PYR_L") >= 0 || StringFind(cmt, "Pyramid") >= 0){
         if(m_anchor_type==POSITION_TYPE_BUY && m_pos.PriceOpen() > g_cache.highPyrBuy)
            g_cache.highPyrBuy = m_pos.PriceOpen();
         if(m_anchor_type==POSITION_TYPE_SELL && m_pos.PriceOpen() < g_cache.lowPyrSell)
            g_cache.lowPyrSell = m_pos.PriceOpen();
      }
   }
}

//+------------------------------------------------------------------+
//| 声音文件校验                                                      |
//+------------------------------------------------------------------+
string ResolveSoundFile(string wantFile, string roleName){
   string trimmed = wantFile;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(StringLen(trimmed) == 0){
      Print("[声音] ", roleName, " 文件名为空，回退为 alert.wav");
      return "alert.wav";
   }
   string relPath = "..\\..\\Sounds\\" + wantFile;
   if(FileIsExist(relPath)) return wantFile;
   if(FileIsExist(relPath, FILE_COMMON)) return wantFile;
   if(wantFile == "alert.wav" || wantFile == "stops.wav" || wantFile == "news.wav"
      || wantFile == "ok.wav" || wantFile == "connect.wav" || wantFile == "disconnect.wav"
      || wantFile == "email.wav" || wantFile == "expert.wav" || wantFile == "tick.wav"
      || wantFile == "timeout.wav" || wantFile == "wait.wav")
      return wantFile;
   Print("[声音] ", roleName, " 文件 '", wantFile, "' 未确认存在，回退为 alert.wav");
   return "alert.wav";
}

//+------------------------------------------------------------------+
//| 声音播放                                                          |
//+------------------------------------------------------------------+
void PlayOpenSound(){
   if(!InpSoundEnable || !InpSoundOpenEnable) return;
   PlaySound(gSoundOpenFile);
}
void PlayCloseSound(){
   if(!InpSoundEnable || !InpSoundCloseEnable) return;
   PlaySound(gSoundCloseFile);
}
void PlayStopSound(){
   if(!InpSoundEnable || !InpSoundStopEnable) return;
   PlaySound(gSoundStopFile);
}

void Notify(string msg, string label, string soundType=""){
   if(InpUsePush) SendNotification(msg);
   if(soundType == "open")       PlayOpenSound();
   else if(soundType == "close") PlayCloseSound();
   else if(soundType == "stop")  PlayStopSound();
   Print("[", label, "] ", msg);
}

//+------------------------------------------------------------------+
//| 参数初始化                                                        |
//+------------------------------------------------------------------+
void ApplyScale(){
   gSeedLot = PresetToLot(InpLotPreset);
   gScale   = (InpBaseLot > 0) ? gSeedLot / InpBaseLot : 1.0;
   if(gScale <= 0) gScale = 1.0;

   gTPDist     = InpTpDist;
   gLockDist   = InpLockTriggerDist;
   gLockSL     = InpLockKeepDist;
   gTrailStart = InpTrailStartDist;
   gTrailDD    = InpTrailDrawdownDist;
   gTrailBuf   = InpTrailBuf;
   gTrailTicks = InpTrailTicks;
   gTrailUseDistance = (gTrailDD > 0);

   gM_Dist[0] = InpM_Dist1; gM_Lot[0] = InpM_Lot1;
   gM_Dist[1] = InpM_Dist2; gM_Lot[1] = InpM_Lot2;
   gM_Dist[2] = InpM_Dist3; gM_Lot[2] = InpM_Lot3;
   gM_Dist[3] = InpM_Dist4; gM_Lot[3] = InpM_Lot4;
   gM_Dist[4] = InpM_Dist5; gM_Lot[4] = InpM_Lot5;
   gM_Dist[5] = InpM_Dist6; gM_Lot[5] = InpM_Lot6;

   gPyrLot[0] = InpPyrLot1; gPyrLot[1] = InpPyrLot2;
   gPyrLot[2] = InpPyrLot3; gPyrLot[3] = InpPyrLot4;
   gPyrLot[4] = InpPyrLot5; gPyrLot[5] = InpPyrLot6;
   gPyrLot[6] = InpPyrLot7; gPyrLot[7] = InpPyrLot8;

   gSoundOpenFile  = ResolveSoundFile(InpSoundOpenFile,  "开仓(open)");
   gSoundCloseFile = ResolveSoundFile(InpSoundCloseFile, "止盈(close)");
   gSoundStopFile  = ResolveSoundFile(InpSoundStopFile,  "止损(stop)");
}

//+------------------------------------------------------------------+
//| 参数校验                                                          |
//+------------------------------------------------------------------+
void ValidateExitParams(){
   if(!InpExitEnable){
      Print("[参数校验] 出场总开关=关闭，所有出场模块不执行");
      return;
   }
   if(InpTpEnable && InpTpDist <= 0)
      Print("[参数校验] 警告：主止盈开关=开，但距离<=0，等同关闭");
   if(InpLockEnable){
      if(InpLockTriggerDist <= 0) Print("[参数校验] 警告：锁利开关=开，但触发距离<=0，等同关闭");
      if(InpLockKeepDist <= 0) Print("[参数校验] 警告：锁利开关=开，但保留距离<=0，等同关闭");
   }
   if(InpTrailEnable){
      if(InpTrailStartDist <= 0) Print("[参数校验] 警告：追踪开关=开，但启动距离<=0，等同关闭");
      if(gTrailUseDistance)
         Print("[参数校验] 追踪使用 距离回撤模式 回撤距离=", DoubleToString(gTrailDD,1), "$");
      else if(InpTrailPct > 0 && InpTrailPct < 1.0)
         Print("[参数校验] 追踪使用 百分比回撤模式 回撤比例=", DoubleToString(InpTrailPct*100,0), "%");
      else
         Print("[参数校验] 警告：追踪回撤距离=0且百分比无效，追踪不会触发出场");
   }
}

void ValidateMartinParams(){
   Print("[参数校验] 马丁6档模式:");
   int activeCnt = 0;
   for(int i=0; i<6; i++){
      if(gM_Dist[i] > 0 && gM_Lot[i] > 0){
         activeCnt++;
         Print("  第", (i+1), "档: 步距=", DoubleToString(gM_Dist[i],1), "$ 手数=", DoubleToString(gM_Lot[i],2));
      } else {
         if(gM_Dist[i] > 0 && gM_Lot[i] <= 0) Print("[参数校验] 警告：第", (i+1), "档步距>0但手数<=0，跳过");
         if(gM_Dist[i] <= 0 && gM_Lot[i] > 0) Print("[参数校验] 警告：第", (i+1), "档手数>0但步距<=0，跳过");
      }
   }
   Print("  6档模式有效档位数=", activeCnt);
}

void ValidatePyramidParams(){
   int maxLayer = MathMin(InpPyrMax, 8);
   if(!InpPyrCustomLotsEnable){
      Print("[参数校验] 金字塔手数=等额(与首仓相同)，最大层数=", maxLayer);
      return;
   }
   Print("[参数校验] 金字塔启用自定义手数，最大层数=", maxLayer, ":");
   int nonZeroCnt = 0;
   for(int i=0; i<maxLayer; i++){
      if(gPyrLot[i] > 0){
         nonZeroCnt++;
         Print("  第", (i+1), "层: 手数=", DoubleToString(gPyrLot[i],2));
         if(i > 0 && gPyrLot[i-1] > 0 && gPyrLot[i] > gPyrLot[i-1])
            Print("  [提醒] 第", (i+1), "层手数大于第", i, "层，是否有意递增？");
      } else {
         Print("  第", (i+1), "层: 手数=0(跳过此层)");
      }
   }
   Print("  非零槽位数量=", nonZeroCnt);
}

void ValidateSoundParams(){
   Print("[参数校验] 声音总开关=", (InpSoundEnable ? "开" : "关"));
   if(InpSoundEnable){
      Print("  开仓声音: ", (InpSoundOpenEnable ? "开" : "关"), " 生效文件=", gSoundOpenFile);
      Print("  止盈声音: ", (InpSoundCloseEnable ? "开" : "关"), " 生效文件=", gSoundCloseFile);
      Print("  止损声音: ", (InpSoundStopEnable ? "开" : "关"), " 生效文件=", gSoundStopFile);
   }
}

//+------------------------------------------------------------------+
//| 启动摘要日志                                                      |
//+------------------------------------------------------------------+
void PrintStartupSummary(){
   Print("=== ", EA_VERSION, " 启动参数摘要 ===");
   Print("首仓=", DoubleToString(gSeedLot,2), " 缩放倍数=", DoubleToString(gScale,2));
   Print("0=关闭语义已启用：所有参数<=0等同关闭");
   Print("---");

   Print("[出场模块]");
   if(!InpExitEnable){
      Print("  出场总开关=关闭，不做任何自动出场");
   } else {
      bool tpActive   = InpTpEnable && InpTpDist > 0;
      bool lockActive = InpLockEnable && InpLockTriggerDist > 0 && InpLockKeepDist > 0;
      bool trailActive = InpTrailEnable && InpTrailStartDist > 0;
      Print("  主止盈: ", (tpActive ? "启用" : "关闭"),
            (tpActive ? (" 距离=" + DoubleToString(gTPDist,1) + "$") : ""));
      Print("  锁利: ", (lockActive ? "启用" : "关闭"),
            (lockActive ? (" 触发=" + DoubleToString(gLockDist,1) + "$ 保留=" + DoubleToString(gLockSL,1) + "$") : ""));
      Print("  追踪: ", (trailActive ? "启用" : "关闭"),
            (trailActive ? (" 启动=" + DoubleToString(gTrailStart,1) + "$ 模式=" +
                           (gTrailUseDistance ? ("距离回撤" + DoubleToString(gTrailDD,1) + "$")
                                             : ("百分比回撤" + DoubleToString(InpTrailPct*100,0) + "%")) +
                           " 确认=" + IntegerToString(gTrailTicks) + "次") : ""));
   }
   Print("---");

   // A3: 金字塔均价保本SL摘要
   Print("[金字塔均价保本SL]");
   if(!InpPyrBEEnable){
      Print("  开关=关闭");
   } else if(MathAbs(InpPyrBESLOffset) < 1e-9){
      Print("  开关=开, 偏移=0(等同关闭)");
   } else {
      Print("  开关=开, 偏移=", DoubleToString(InpPyrBESLOffset,2), "$",
            (InpPyrBESLOffset > 0 ? "(盈利侧)" : "(留回撤)"),
            "  延迟=", IntegerToString(InpPyrBEDelay), "分钟",
            (InpPyrBEDelay > 0 ? "" : "(立即)"));
   }
   Print("---");

   Print("[马丁补仓]");
   ValidateMartinParams();
   Print("---");

   Print("[金字塔]");
   ValidatePyramidParams();
   Print("---");

   Print("[声音]");
   ValidateSoundParams();
   Print("=== 摘要结束 ===");
}


//+------------------------------------------------------------------+
//| 出场模块开关                                                      |
//+------------------------------------------------------------------+
bool IsTpActive(){
   return InpExitEnable && InpTpEnable && gTPDist > 0;
}
bool IsLockActive(){
   return InpExitEnable && InpLockEnable && gLockDist > 0 && gLockSL > 0;
}
bool IsTrailActive(){
   if(!InpExitEnable || !InpTrailEnable || gTrailStart <= 0) return false;
   if(gTrailUseDistance) return true;
   if(InpTrailPct > 0 && InpTrailPct < 1.0) return true;
   return false;
}

//+------------------------------------------------------------------+
//| 持仓计数（仅CloseAll用，其余用缓存）                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 判断最新仓是否金字塔                                              |
//+------------------------------------------------------------------+
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
   string cmt = m_pos.Comment();
   return (StringFind(cmt, "PYR_L") >= 0 || StringFind(cmt, "Pyramid") >= 0);
}

//+------------------------------------------------------------------+
//| 止损相关                                                          |
//+------------------------------------------------------------------+
void RaiseBasketSL(int basketType, double slPrice){
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + 2*_Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      double curSL = m_pos.StopLoss();
      bool valid = (basketType==POSITION_TYPE_BUY) ? (slPrice <= bid - minDist) : (slPrice >= ask + minDist);
      bool needSync = (MathAbs(slPrice - curSL) >= 0.01);
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
//| A2: 均价保本SL（开关+0=关闭闸门）                                |
//+------------------------------------------------------------------+
void ApplyBreakEvenSL(int basketType, double be){
   // A2 硬闸
   if(!InpPyrBEEnable) return;
   if(MathAbs(InpPyrBESLOffset) < 1e-9) return;

   double offset  = InpPyrBESLOffset;
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + 2*_Point;
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    dig     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double targetSL = (basketType == POSITION_TYPE_BUY)
                     ? NormalizeDouble(be + offset, dig)
                     : NormalizeDouble(be - offset, dig);

   bool distOK = (basketType == POSITION_TYPE_BUY)
                 ? (targetSL <= bid - minDist)
                 : (targetSL >= ask + minDist);
   if(!distOK) return;

   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;

      double curSL = m_pos.StopLoss();
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
   // A4: 日志偏移带正负号
   if(cnt > 0)
      Print("[均价保本SL] 共更新", cnt, "单 均价=", DoubleToString(be,2),
            " 偏移=", (offset >= 0 ? "+" : ""), DoubleToString(offset,2), "$");
}


//+------------------------------------------------------------------+
//| C2: CloseAll 无Sleep版（每次调用处理一轮，未完返false）           |
//+------------------------------------------------------------------+
bool CloseAll(string reason){
   if(CountPos() == 0) return true;
   int closed = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      if(m_trade.PositionClose(m_pos.Ticket())) closed++;
      if(closed >= 3) break;  // 每轮最多关3笔，避免一次性全堵
   }
   if(CountPos() == 0) return true;
   // 未清完，调用方通过m_force_flatten在下个tick继续
   return false;
}


//+------------------------------------------------------------------+
//| C1: 面板（只创建一次，后续只更新文字）                            |
//+------------------------------------------------------------------+
void PanelRow(string name, int row, string text, color clr=clrWhite){
   int fs    = MathMax(8, InpFontSize);
   int lineH = fs + 6;

   ENUM_BASE_CORNER  corner;
   ENUM_ANCHOR_POINT anch;
   int yOff;

   if(InpPanelPos == PANEL_BOTTOM){
      int totalRows = 6;
      corner = CORNER_RIGHT_LOWER;
      anch   = ANCHOR_RIGHT_LOWER;
      yOff   = 10 + (totalRows - row) * lineH;
   } else if(InpPanelPos == PANEL_MID){
      corner = CORNER_RIGHT_UPPER;
      anch   = ANCHOR_RIGHT_UPPER;
      yOff   = 280 + row * lineH;
   } else {
      corner = CORNER_RIGHT_UPPER;
      anch   = ANCHOR_RIGHT_UPPER;
      yOff   = 10 + row * lineH;
   }

   // C1: 对象不存在才创建，否则只更新文字和颜色
   if(ObjectFind(0, name) < 0){
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    corner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anch);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yOff);
      ObjectSetString(0,  name, OBJPROP_FONT,      "微软雅黑");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   }
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdatePanel(){
   // C1: 面板节流1秒
   ulong nowMs = GetTickCount64();
   if(nowMs - m_last_panel_ms < 1000) return;
   m_last_panel_ms = nowMs;

   double ancVolHL = gSeedLot;
   if(m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket))
      ancVolHL = m_pos.Volume();
   double lotRatioHL = (InpBaseLot > 0) ? ancVolHL / InpBaseLot : 1.0;
   if(lotRatioHL <= 0) lotRatioHL = 1.0;
   double actualHL = InpHardLoss * lotRatioHL;

   // 行0
   string dirStr = (InpAutoDirection==AUTO_DIR_OFF) ? "手动" :
                   (InpAutoDirection==AUTO_DIR_BUY)  ? "自动多↑" : "自动空↓";
   PanelRow("VP_0", 0,
            EA_VERSION + "  马丁6档  " + dirStr +
            "  强止损=" + DoubleToString(actualHL,0) + "$",
            (InpAutoDirection==AUTO_DIR_OFF) ? clrSilver :
            (InpAutoDirection==AUTO_DIR_BUY) ? clrLime   : clrOrangeRed);

   // 行1（使用缓存）
   if(g_cache.basketValid){
      string side  = (g_cache.bType==POSITION_TYPE_BUY) ? "多▲" : "空▼";
      string dpStr = (g_cache.bDelta>=0 ? "+" : "") + DoubleToString(g_cache.bDelta,2) + "$";
      PanelRow("VP_1", 1,
               side + " 量=" + DoubleToString(g_cache.bVol,2) +
               "  均=" + DoubleToString(g_cache.bBE,2) +
               "  浮盈=" + dpStr,
               g_cache.bDelta >= 0 ? clrLime : clrOrangeRed);
   } else {
      PanelRow("VP_1", 1, "空仓 — 等待开仓", clrSilver);
   }

   // 行2（使用缓存）
   string structStr = "金字塔=" + IntegerToString(g_cache.pyrCnt) + "/" + IntegerToString(MathMin(InpPyrMax,8));
   if(InpPyrCustomLotsEnable) structStr += "(自定义)";
   structStr += "  马丁6档: 已补" + IntegerToString(g_cache.abyFilled) + "档";
   if(m_locked)   structStr += "  [保本锁]";
   if(m_trailing) structStr += "  [追踪中]";
   PanelRow("VP_2", 2, structStr, (g_cache.abyFilled > 0) ? clrOrangeRed : clrSilver);

   // 行3
   string tpStr;
   if(!InpExitEnable){
      tpStr = "出场关闭";
   } else if(m_force_flatten){
      tpStr = "⚠ 强平执行中";
   } else if(m_trailing){
      if(gTrailUseDistance){
         tpStr = "追踪(距离) 峰值+" + DoubleToString(m_peak_delta,2) +
                 "$  回撤阈=" + DoubleToString(gTrailDD,1) + "$";
      } else {
         double exitLine = m_peak_delta * (1.0 - InpTrailPct);
         tpStr = "追踪(%) 峰值+" + DoubleToString(m_peak_delta,2) +
                 "$  出场≤+" + DoubleToString(exitLine,2) + "$";
      }
   } else {
      tpStr = "";
      if(IsTrailActive()) tpStr += "追踪待启(≥+" + DoubleToString(gTrailStart,1) + "$)";
      if(IsTpActive()) tpStr += "  主止盈=" + DoubleToString(gTPDist,1) + "$";
      if(tpStr == "") tpStr = "出场模块全部关闭";
   }
   PanelRow("VP_3", 3, tpStr, m_force_flatten ? clrRed : (m_trailing ? clrLime : clrSilver));

   // 行4 马丁预测（使用缓存）
   string predStr = "马丁预测: ";
   if(m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket)){
      if(g_cache.basketValid){
         predStr += "已补" + IntegerToString(g_cache.abyFilled) + "档";
         for(int n=0; n<6; n++){
            if(!g_cache.abyOpened[n] && gM_Dist[n] > 0 && gM_Lot[n] > 0){
               predStr += " 下档=" + IntegerToString(n+1) + "(距" + DoubleToString(gM_Dist[n],1) + "$)";
               break;
            }
         }
      } else {
         predStr += "空仓";
      }
   } else {
      predStr += "无首仓";
   }
   PanelRow("VP_4", 4, predStr, clrYellow);
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
   if(g_last_close_time > 0){
      ulong elapsed = (ulong)(TimeCurrent() - g_last_close_time) * 1000;
      if(elapsed < (ulong)MathMax(500, InpAutoDelayMs)) return;
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return;
   double spread = ask - bid;
   if(spread > InpMaxSpreadUSD){
      if(nowMs - m_last_autoseed_log > 10000){
         m_last_autoseed_log = nowMs;
         Print("[续开跳过] 点差过大 当前=", DoubleToString(spread,2), " 最大=", DoubleToString(InpMaxSpreadUSD,1));
      }
      return;
   }
   bool res = false;
   if(InpAutoDirection == AUTO_DIR_BUY){
      res = m_trade.Buy(gSeedLot, _Symbol, ask, 0, 0, "Seed_Auto");
      if(res){
         g_round_open = true;
         Notify("自动续开做多 " + DoubleToString(gSeedLot,2) + "手 @ " + DoubleToString(ask,2), "开仓", "open");
         m_last_action = nowMs + 1000;
      }
   } else if(InpAutoDirection == AUTO_DIR_SELL){
      res = m_trade.Sell(gSeedLot, _Symbol, bid, 0, 0, "Seed_Auto");
      if(res){
         g_round_open = true;
         Notify("自动续开做空 " + DoubleToString(gSeedLot,2) + "手 @ " + DoubleToString(bid,2), "开仓", "open");
         m_last_action = nowMs + 1000;
      }
   }
}

//+------------------------------------------------------------------+
//| 金字塔加仓（使用缓存的pyrOpened）                                 |
//+------------------------------------------------------------------+
void TryPyramid(ulong nowMs, double delta,
                double highest_pyr_buy, double lowest_pyr_sell){
   if(nowMs <= m_last_action) return;
   if(delta <= 0) return;
   int maxLayer = MathMin(InpPyrMax, 8);

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

   double vol = 0;
   int    targetLayer = 0;
   string tag = "";

   if(InpPyrCustomLotsEnable){
      // 使用缓存pyrOpened
      for(int n=0; n<maxLayer; n++){
         if(!g_cache.pyrOpened[n] && gPyrLot[n] > 0){
            targetLayer = n + 1;
            vol = NormalizeDouble(gPyrLot[n], 2);
            break;
         }
      }
      if(targetLayer == 0) return;
      tag = "PYR_L" + IntegerToString(targetLayer);
   } else {
      if(g_cache.pyrCnt >= maxLayer) return;
      targetLayer = g_cache.pyrCnt + 1;
      vol = 0.01;
      if(m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket))
         vol = m_pos.Volume();
      if(vol <= 0) vol = gSeedLot;
      vol = NormalizeDouble(vol, 2);
      tag = "PYR_L" + IntegerToString(targetLayer);
   }
   if(vol <= 0) vol = 0.01;

   bool res = false;
   if(m_anchor_type==POSITION_TYPE_BUY)
      res = m_trade.Buy(vol, _Symbol, ask, 0, 0, tag);
   else
      res = m_trade.Sell(vol, _Symbol, bid, 0, 0, tag);

   if(res){
      Notify("金字塔加仓 " + DoubleToString(vol,2) + "手 层=" + IntegerToString(targetLayer) +
             "/" + IntegerToString(maxLayer) +
             " 基准价=" + DoubleToString(ref,2) + " 当前价=" + DoubleToString(cur,2) +
             " 距离=" + DoubleToString(dist,1) + "$",
             "加仓", "open");
      m_last_action    = nowMs + 1000;
      m_pyr_be_pending = true;
      m_pyr_be_delay_start = 0;   // 新层开仓，延迟重新计时
   }
}

double GetAnchorVolume(){
   if(m_anchor_ticket == 0 || !m_pos.SelectByTicket(m_anchor_ticket)) return gSeedLot;
   double v = m_pos.Volume();
   return (v > 0) ? v : gSeedLot;
}

//+------------------------------------------------------------------+
//| 马丁补仓-6档（唯一引擎，使用缓存abyOpened/abyPrice）             |
//+------------------------------------------------------------------+
void TryAbyss(ulong nowMs){
   if(nowMs <= m_last_action) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double curP = (m_anchor_type==POSITION_TYPE_BUY) ? bid : ask;

   // 找下一个 未开+参数有效 的档位（使用缓存）
   int nextIdx = -1;
   for(int n=0; n<6; n++){
      if(!g_cache.abyOpened[n] && gM_Dist[n] > 0 && gM_Lot[n] > 0){
         nextIdx = n;
         break;
      }
   }
   if(nextIdx < 0) return;

   // 基准价
   double basePrice = 0;
   if(nextIdx == 0){
      basePrice = m_anchor_price;
      for(int i = PositionsTotal()-1; i >= 0; i--){
         if(!m_pos.SelectByIndex(i)) continue;
         if(m_pos.Symbol() != _Symbol) continue;
         if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
         if(m_anchor_type == POSITION_TYPE_BUY){
            if(m_pos.PriceOpen() < basePrice) basePrice = m_pos.PriceOpen();
         } else {
            if(m_pos.PriceOpen() > basePrice) basePrice = m_pos.PriceOpen();
         }
      }
   } else {
      for(int j = nextIdx-1; j >= 0; j--){
         if(g_cache.abyOpened[j] && g_cache.abyPrice[j] > 0){
            basePrice = g_cache.abyPrice[j];
            break;
         }
      }
      if(basePrice <= 0){
         basePrice = m_anchor_price;
         for(int i = PositionsTotal()-1; i >= 0; i--){
            if(!m_pos.SelectByIndex(i)) continue;
            if(m_pos.Symbol() != _Symbol) continue;
            if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
            if(m_anchor_type == POSITION_TYPE_BUY){
               if(m_pos.PriceOpen() < basePrice) basePrice = m_pos.PriceOpen();
            } else {
               if(m_pos.PriceOpen() > basePrice) basePrice = m_pos.PriceOpen();
            }
         }
      }
   }
   if(basePrice <= 0) return;

   double dist = (m_anchor_type==POSITION_TYPE_BUY) ? (basePrice - curP) : (curP - basePrice);
   if(dist < gM_Dist[nextIdx]) return;

   // 下单前再次实时确认未开过（防并发）
   bool recheck[6]; double recheckP[6];
   ArrayInitialize(recheck, false);
   ArrayInitialize(recheckP, 0.0);
   for(int i = PositionsTotal()-1; i >= 0; i--){
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol() != _Symbol) continue;
      if(!IsManagedMagic((ulong)m_pos.Magic())) continue;
      string cmt = m_pos.Comment();
      int pos = StringFind(cmt, "ABY_L");
      if(pos < 0) pos = StringFind(cmt, "Abyss_L");
      if(pos >= 0){
         int ns = pos + ((StringFind(cmt, "ABY_L") >= 0) ? 5 : 7);
         int ln = (int)StringToInteger(StringSubstr(cmt, ns, 1));
         if(ln >= 1 && ln <= 6) recheck[ln-1] = true;
      }
   }
   if(recheck[nextIdx]) return;

   double lot = NormalizeDouble(gM_Lot[nextIdx], 2);
   if(lot <= 0) lot = 0.01;
   string tag = "ABY_L" + IntegerToString(nextIdx+1);

   bool res = (m_anchor_type==POSITION_TYPE_BUY) ?
               m_trade.Buy(lot, _Symbol, ask, 0, 0, tag) :
               m_trade.Sell(lot, _Symbol, bid, 0, 0, tag);

   if(res){
      Notify("马丁第" + IntegerToString(nextIdx+1) + "档补仓 " + DoubleToString(lot,2) + "手" +
             " 步距=" + DoubleToString(gM_Dist[nextIdx],1) + "$" +
             " 基准价=" + DoubleToString(basePrice,2) +
             " 当前价=" + DoubleToString(curP,2) +
             " 实际距离=" + DoubleToString(dist,1) + "$",
             "补仓", "open");
      m_last_action = nowMs + 1000;
   }
}


//+------------------------------------------------------------------+
//| 止盈模块                                                          |
//+------------------------------------------------------------------+
bool CheckTP(double vol, double be, int bType, double delta){
   if(!InpExitEnable) return false;

   if(MathAbs(vol - m_last_volume) > 0.000001){
      if(vol > m_last_volume){
         if(IsNewestPositionPyramid()){
            m_last_volume = vol;
         } else {
            m_peak_delta  = delta;
            m_peak_price  = (bType==POSITION_TYPE_BUY)
                            ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            m_last_volume = vol;
            m_trail_hits  = 0;
         }
      } else {
         m_last_volume = vol;
      }
   }
   if(delta > m_peak_delta){
      m_peak_delta = delta;
      m_peak_price = (bType==POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   if(IsLockActive()){
      if(!m_locked && delta >= gLockDist){
         double slP = (bType==POSITION_TYPE_BUY) ? (be + gLockSL) : (be - gLockSL);
         RaiseBasketSL(bType, slP);
         m_locked = true;
         Print("[锁利触发] 浮盈=", DoubleToString(delta,2), "$ 触发距离=", DoubleToString(gLockDist,1),
               "$ 锁利SL偏移=", DoubleToString(gLockSL,1), "$");
      }
   }

   if(IsTrailActive()){
      if(!m_trailing && delta >= gTrailStart){
         m_trailing = true; m_trail_hits = 0;
         string modeStr = gTrailUseDistance
                          ? ("距离回撤模式 回撤阈=" + DoubleToString(gTrailDD,1) + "$")
                          : ("百分比回撤模式 出场线=峰值x" + DoubleToString(1.0-InpTrailPct,2));
         Print("[追踪启动] 浮盈=", DoubleToString(delta,2), "$ 启动阈=", DoubleToString(gTrailStart,1), "$ ", modeStr);
      }
   }

   bool   trigClose   = false;
   string closeReason = "";

   if(m_trailing && IsTrailActive()){
      if(gTrailUseDistance){
         double curPrice = (bType==POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double lockSL = (bType==POSITION_TYPE_BUY)
                         ? (m_peak_price - gTrailDD - gTrailBuf)
                         : (m_peak_price + gTrailDD + gTrailBuf);
         if(bType==POSITION_TYPE_BUY && lockSL > be) RaiseBasketSL(bType, lockSL);
         if(bType==POSITION_TYPE_SELL && lockSL < be) RaiseBasketSL(bType, lockSL);

         double drawdown = (bType==POSITION_TYPE_BUY) ? (m_peak_price - curPrice) : (curPrice - m_peak_price);
         if(drawdown >= gTrailDD){
            m_trail_hits++;
            if(m_trail_hits >= MathMax(1, gTrailTicks)){
               trigClose = true;
               closeReason = "距离追踪止盈 峰值价=" + DoubleToString(m_peak_price,2) +
                             " 当前价=" + DoubleToString(curPrice,2) +
                             " 回撤=" + DoubleToString(drawdown,1) + "$(阈=" + DoubleToString(gTrailDD,1) + "$)";
            }
         } else m_trail_hits = 0;
      } else {
         double lockDelta = m_peak_delta * (1.0 - InpTrailPct) - gTrailBuf;
         if(lockDelta > 0){
            double dynSL = (bType==POSITION_TYPE_BUY) ? (be + lockDelta) : (be - lockDelta);
            RaiseBasketSL(bType, dynSL);
         }
         if(delta <= m_peak_delta * (1.0 - InpTrailPct)){
            m_trail_hits++;
            if(m_trail_hits >= MathMax(1, gTrailTicks)){
               trigClose = true;
               closeReason = "百分比追踪止盈 峰值+" + DoubleToString(m_peak_delta,2) +
                             "$ 回撤" + DoubleToString(InpTrailPct*100,0) + "% 出场+" +
                             DoubleToString(delta,2) + "$";
            }
         } else m_trail_hits = 0;
      }
   } else if(!m_trailing && IsTpActive()){
      m_trail_hits = 0;
      if(delta >= gTPDist){
         trigClose = true;
         closeReason = "主止盈 +" + DoubleToString(delta,2) + "$ (阈=" + DoubleToString(gTPDist,1) + "$)";
      }
   }

   if(trigClose){
      Notify(closeReason, "清仓", "close");
      m_force_flatten = true;
      m_force_reason  = closeReason;
      m_flatten_round = 0;
      CloseAll(closeReason);
      if(CountPos() == 0){
         g_last_close_time = TimeCurrent();
         g_round_open      = false;
         m_force_flatten   = false;
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit(){
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

   ValidateExitParams();
   PrintStartupSummary();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ ClearPanel(); Comment(""); }

//+------------------------------------------------------------------+
//| OnTick 主循环                                                     |
//+------------------------------------------------------------------+
void OnTick(){
   ulong nowMs = GetTickCount64();
   if(nowMs - m_last_tick < 200) return;
   m_last_tick = nowMs;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;

   // C2: 强平分tick续执（不阻塞主循环）
   if(m_force_flatten){
      m_flatten_round++;
      if(CloseAll(m_force_reason) || m_flatten_round >= InpFlattenRounds){
         if(CountPos() == 0){
            g_last_close_time = TimeCurrent();
            g_round_open      = false;
         }
         m_force_flatten = false;
         m_flatten_round = 0;
      }
      UpdatePanel();
      return;
   }

   // C3: 一次性扫描所有持仓
   ScanAllPositions();

   // 空仓分支
   if(g_cache.totalCnt == 0){
      g_round_open = false;
      m_anchor_ticket = 0; m_anchor_price = 0; m_anchor_type = -1;
      m_peak_delta = 0; m_peak_price = 0; m_trailing = false; m_locked = false;
      m_last_volume = 0; m_trail_hits = 0;
      m_pyr_be_pending = false;
      m_pyr_be_delay_start = 0;

      TryAutoSeed(nowMs);
      UpdatePanel();
      return;
   }

   if(!g_round_open) g_round_open = true;

   // 确定锚仓
   if(g_cache.anchorTicket != 0 && m_pos.SelectByTicket(g_cache.anchorTicket)){
      m_anchor_ticket = g_cache.anchorTicket;
      m_anchor_price  = m_pos.PriceOpen();
      m_anchor_type   = (int)m_pos.PositionType();
   } else {
      m_anchor_ticket = 0;
   }
   if(m_anchor_ticket == 0){ UpdatePanel(); return; }

   // 补充金字塔价格统计（需要锚仓信息）
   CachePyrPrices();

   // 硬止损
   double ancVolForHL = (m_anchor_ticket != 0 && m_pos.SelectByTicket(m_anchor_ticket))
                        ? m_pos.Volume() : gSeedLot;
   double lotRatio  = (InpBaseLot > 0) ? ancVolForHL / InpBaseLot : 1.0;
   if(lotRatio <= 0) lotRatio = 1.0;
   double hardLoss  = InpHardLoss * lotRatio;
   if(hardLoss > 0 && g_cache.netProfit <= -hardLoss){
      string reason = "硬止损 亏损=" + DoubleToString(g_cache.netProfit,2) + "$ (阈=" + DoubleToString(-hardLoss,2) + "$)";
      Notify(reason, "止损", "stop");
      m_force_flatten = true;
      m_force_reason  = reason;
      m_flatten_round = 0;
      CloseAll(reason);
      if(CountPos() == 0){
         g_last_close_time = TimeCurrent();
         g_round_open      = false;
         m_force_flatten   = false;
      }
      m_last_action = nowMs + 1000;
      UpdatePanel();
      return;
   }

   // 使用缓存的篮子数据
   if(!g_cache.basketValid){ UpdatePanel(); return; }

   // 金字塔保本SL（延迟激活）
   if(m_pyr_be_pending){
      if(InpPyrBEDelay <= 0){
         // 延迟=0：立即激活（兼容旧行为）
         m_pyr_be_pending = false;
         m_pyr_be_delay_start = 0;
         ApplyBreakEvenSL(g_cache.bType, g_cache.bBE);
      } else {
         // 延迟>0：记录起点，等计时到期
         if(m_pyr_be_delay_start == 0)
            m_pyr_be_delay_start = TimeCurrent();
         if(TimeCurrent() - m_pyr_be_delay_start >= InpPyrBEDelay * 60){
            m_pyr_be_pending = false;
            m_pyr_be_delay_start = 0;
            ApplyBreakEvenSL(g_cache.bType, g_cache.bBE);
         }
      }
   }

   // 止盈检查
   if(CheckTP(g_cache.bVol, g_cache.bBE, g_cache.bType, g_cache.bDelta)){
      UpdatePanel();
      return;
   }

   // 交易冷却
   if(nowMs <= m_last_action){ UpdatePanel(); return; }

   // 金字塔加仓
   TryPyramid(nowMs, g_cache.bDelta, g_cache.highPyrBuy, g_cache.lowPyrSell);

   // 马丁补仓（只有6档引擎）
   TryAbyss(nowMs);

   UpdatePanel();
}