# TelegramAlerts.mqh 和 WyckoffPatterns.mqh 详细介绍

---

## 📱 TelegramAlerts.mqh - Telegram 交易提醒模块

### 功能概述

这是一个为MT5 EA设计的Telegram消息推送模块，可以在交易事件发生时自动发送格式化消息到Telegram。

**核心价值：**
- ✅ 实时监控交易状态（无需盯着MT5）
- ✅ 手机推送提醒（随时随地接收信号）
- ✅ 格式化消息（带emoji、Markdown格式）
- ✅ 风控提醒（止损警告、每日摘要）

---

### 类结构

```cpp
class CTelegramAlerts
{
private:
   string   m_botToken;       // Bot Token
   string   m_chatID;         // 聊天ID
   bool     m_enabled;        // 是否启用
   int      m_internetHandle; // 网络连接句柄
   
public:
   // 5个主要提醒方法
   void SendTradeOpen(...);      // 开仓提醒
   void SendTradeClose(...);     // 平仓提醒
   void SendSignal(...);         // 信号提醒
   void SendDailySummary(...);   // 每日摘要
   void SendStopLossWarning(...);// 止损警告
}
```

---

### 方法详解

#### 1. SendTradeOpen - 开仓提醒

**用途：** 当EA开仓时发送提醒

**参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| symbol | string | 交易品种，如"XAU/USD" |
| isBuy | bool | true=做多, false=做空 |
| entryPrice | double | 入场价格 |
| stopLoss | double | 止损价格 |
| takeProfit | double | 止盈价格 |
| lotSize | double | 手数 |

**消息示例：**
```
🟢 TRADE OPENED

Asset: XAU/USD | LONG
Entry: 5278.50
Stop: 5228.50
Target: 5378.50
Lot: 0.01
Risk/Reward: 1:2.0

_2026-03-01 14:30_
```

**应用场景：**
- EA自动开仓后立即通知
- 手动开仓后确认
- 记录交易日志

---

#### 2. SendTradeClose - 平仓提醒

**用途：** 当平仓时发送结果

**参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| symbol | string | 交易品种 |
| isBuy | bool | 方向 |
| entryPrice | double | 入场价 |
| exitPrice | double | 出场价 |
| lotSize | double | 手数 |
| profit | double | 盈亏金额 |

**消息示例（盈利）：**
```
✅ TRADE CLOSED - WIN

Asset: XAU/USD | LONG
Entry: 5278.50
Exit: 5310.20
P&L: +$31.70

_2026-03-01 16:45_
```

**消息示例（亏损）：**
```
❌ TRADE CLOSED - LOSS

Asset: XAU/USD | LONG
Entry: 5278.50
Exit: 5228.50
P&L: -$50.00

_2026-03-01 15:20_
```

**应用场景：**
- 追踪每日盈亏
- 连胜/连败提醒
- 心理风控（防止 tilt）

---

#### 3. SendSignal - 信号提醒

**用途：** 当检测到交易信号时发送

**参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| symbol | string | 品种 |
| pattern | string | 形态名称 |
| isBullish | bool | 是否看涨 |
| strength | double | 信号强度 0-10 |
| price | double | 当前价格 |

**消息示例：**
```
📈 SIGNAL DETECTED

Asset: XAU/USD
Pattern: 弹簧(Spring)
Direction: BULLISH
Strength: 8.2/10
Price: 5278.50

_2026-03-01 14:30_
```

**应用场景：**
- 指标版EA（只提醒不开仓）
- 等待手动确认
- 信号质量评估

---

#### 4. SendDailySummary - 每日摘要

**用途：** 每日交易统计

**参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| totalTrades | int | 总交易数 |
| winTrades | int | 盈利次数 |
| lossTrades | int | 亏损次数 |
| totalProfit | double | 总盈亏 |
| maxDrawdown | double | 最大回撤 |

**消息示例：**
```
📊 DAILY TRADING SUMMARY

Total Trades: 5
Wins: 3
Losses: 2
Win Rate: 60.0%
Net P&L: 🟢 $127.50
Max Drawdown: 2.1%

_2026-03-01_
```

**应用场景：**
- 每日收盘后自动发送
- 长期绩效追踪
- 周末复盘

---

#### 5. SendStopLossWarning - 止损警告

**用途：** 当价格接近止损时预警

**参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| symbol | string | 品种 |
| currentPrice | double | 当前价格 |
| stopLoss | double | 止损价 |
| remainingPips | double | 剩余点数 |

**消息示例：**
```
⚠️ STOP LOSS WARNING

Asset: XAU/USD
Current: 5235.20
Stop Loss: 5228.50
Remaining: 6.7 pips

_Consider manual intervention_
```

**应用场景：**
- 手动干预机会
- 移动止损提醒
- 避免意外止损

---

### 使用方法

#### 步骤1：配置Bot
```mql5
// 在EA参数中添加
input string Inp_TelegramBotToken = "123456789:ABCdef...";
input string Inp_TelegramChatID = "123456789";
input bool Inp_TelegramEnabled = true;
```

#### 步骤2：初始化对象
```mql5
CTelegramAlerts telegram(
   Inp_TelegramBotToken, 
   Inp_TelegramChatID, 
   Inp_TelegramEnabled
);
```

#### 步骤3：在交易事件中调用
```mql5
// 开仓时
void OnTick()
{
   // ... 开仓逻辑 ...
   
   if(positionOpened)
   {
      telegram.SendTradeOpen(
         _Symbol,
         true,           // 做多
         entryPrice,
         stopLoss,
         takeProfit,
         lotSize
      );
   }
}
```

---

### 技术细节

**HTTP请求流程：**
1. 构造Telegram API URL
2. URL编码消息内容
3. 使用WinInet发送GET请求
4. 处理响应

**安全性考虑：**
- Token和ChatID存储在本地
- 通过环境变量传入（更安全）
- 可开关控制

---

## 📊 WyckoffPatterns.mqh - 威科夫形态识别模块

### 功能概述

基于威科夫交易法的6种经典形态识别算法，用于在M3周期识别高概率进场点。

**威科夫理论基础：**
- 市场由大型机构（Composite Man）主导
- 价格行为反映供需关系
- 通过量价分析识别机构意图

**6种形态：**
1. 弹簧 (Spring) - 洗盘后反弹 🟢
2. 上推 (Upthrust) - 假突破回落 🔴
3. 测试 (Test) - 缩量确认 🔵
4. 突破 (Breakout) - 趋势启动 🟢
5. 努力上涨 (Effort Rally) - 上涨遇阻 🟡
6. 努力下跌 (Effort Decline) - 下跌遇撑 🟡

---

### 类结构

```cpp
class CWyckoffPatterns
{
private:
   int    m_VolumeLookback;  // 成交量回看周期
   double m_VolumeRatio;     // 放量倍数
   double m_ShadowRatio;     // 影线比例
   
public:
   // 6种形态检测方法
   bool DetectSpring(double &strength);
   bool DetectUpthrust(double &strength);
   bool DetectTest(bool isSupport, double &strength);
   bool DetectBreakout(bool isBullish, double &strength);
   bool DetectEffortRally(double &strength);
   bool DetectEffortDecline(double &strength);
   
   // 综合检测
   WyckoffPattern DetectStrongestPattern();
}
```

---

### 形态详解

#### 1. 弹簧 (Spring) - 看涨信号

**威科夫逻辑：**
机构故意将价格打到支撑位以下，清洗散户止损，然后快速拉回。

**识别条件：**
| 条件 | 说明 |
|------|------|
| 长下影线 | > 实体2倍 |
| 收盘在高位 | > 60% K线范围 |
| 放量 | > 1.5倍均量 |
| 反转 | 阴线转阳线或下影线极长 |

**图示：**
```
    │
    │     收盘
    │    ╱
    │   ╱  实体
    │  ╱
    │ ╱
    │╱___ 下影线（长，>实体2倍）
    │
   支撑（跌破后快速收回）
```

**强度计算：**
```cpp
strength = (下影线长度 / K线范围) * 成交量比率
```

**应用：**
- 支撑位附近做多
- 止损设在下影线低点下方
- 预期机构吸筹完毕开始拉升

---

#### 2. 上推 (Upthrust) - 看跌信号

**威科夫逻辑：**
机构将价格推到阻力位以上，诱多散户追高，然后回落套住多头。

**识别条件：**
| 条件 | 说明 |
|------|------|
| 长上影线 | > 实体2倍 |
| 收盘在低位 | < 40% K线范围 |
| 放量 | > 1.5倍均量 |
| 反转 | 阳线转阴线上影线极长 |

**图示：**
```
   阻力（突破后回落）
    │
    │‾‾‾ 上影线（长，>实体2倍）
    │   ╲
    │    ╲
    │     ╲ 实体
    │      ╲
    │       ╲
    │        收盘
    │
```

**应用：**
- 阻力位附近做空
- 止损设在上影线高点上方
- 预期机构派发完毕开始下跌

---

#### 3. 测试 (Test) - 确认信号

**威科夫逻辑：**
机构测试支撑位或阻力位的有效性，缩量回踩确认关键位。

**识别条件：**
| 条件 | 说明 |
|------|------|
| 缩量 | < 0.8倍均量 |
| 小实体 | < 40% K线范围 |
| 收盘位置 | 支撑测试收高位/阻力测试收低位 |

**支撑测试图示：**
```
    │
    │    ╱‾ 收盘在高位
    │   ╱
    │  ╱  小实体
    │ ╱
    │╱___ 支撑位
    │
   缩量
```

**应用：**
- 确认支撑/阻力有效后进场
- 低风险的二次进场点
- 常与弹簧/上推配合使用

---

#### 4. 突破 (Breakout) - 趋势启动

**威科夫逻辑：**
机构完成吸筹/派发后，放量突破关键位启动趋势。

**识别条件：**
| 条件 | 说明 |
|------|------|
| 大实体 | > 60% K线范围 |
| 放量 | > 1.5倍均量 |
| 收盘极端 | 突破收高位/下破收低位 |
| 方向 | 阳线突破/阴线下破 |

**应用：**
- 趋势启动时追势进场
- 突破交易策略
- 高胜率但风险较高

---

#### 5. 努力上涨 (Effort Rally)

**威科夫逻辑：**
放量上涨但收盘不在高位，表明上涨遇阻，可能是顶部信号。

**识别条件：**
- 放量（>1.5倍）
- 阳线
- 存在上影线（>30%范围）
- 收盘不在极端高位

**警示意义：**
⚠️ 可能是阶段性顶部，不宜追高

---

#### 6. 努力下跌 (Effort Decline)

**威科夫逻辑：**
放量下跌但收盘不在低位，表明下跌遇撑，可能是底部信号。

**识别条件：**
- 放量（>1.5倍）
- 阴线
- 存在下影线（>30%范围）
- 收盘不在极端低位

**警示意义：**
⚠️ 可能是阶段性底部，不宜追空

---

### 综合使用

#### DetectStrongestPattern 方法

自动检测所有形态，返回**最强**的那个：

```mql5
CWyckoffPatterns wyckoff(20, 1.5, 0.5);
WyckoffPattern pattern = wyckoff.DetectStrongestPattern();

if(pattern.type != PATTERN_NONE)
{
   Print("检测到：", pattern.name);
   Print("强度：", pattern.strength);
   Print("方向：", pattern.isBullish ? "看涨" : "看跌");
   Print("描述：", pattern.description);
}
```

---

### 参数调优

| 参数 | 保守 | 平衡 | 激进 |
|------|------|------|------|
| VolumeLookback | 30 | 20 | 10 |
| VolumeRatio | 2.0 | 1.5 | 1.2 |
| ShadowRatio | 0.6 | 0.5 | 0.4 |

**建议：**
- 新手：保守参数（信号少但准）
- 老手：平衡参数（信号适中）
- 高频：激进参数（信号多需筛选）

---

### 实战应用示例

```mql5
// 初始化
CWyckoffPatterns wyckoff(20, 1.5, 0.5);

// 在OnTick中检测
void OnTick()
{
   // H1和M15趋势一致
   if(h1Trend == TREND_BULL && m15Trend == TREND_BULL)
   {
      WyckoffPattern pattern = wyckoff.DetectStrongestPattern();
      
      // 只交易高概率形态
      if(pattern.type == PATTERN_SPRING || 
         pattern.type == PATTERN_BREAKOUT)
      {
         if(pattern.strength > 7.0)  // 强度>7
         {
            // 做多
            SendBuyOrder();
         }
      }
   }
}
```

---

## 📦 文件清单

| 文件 | 用途 | 大小 |
|------|------|------|
| TelegramAlerts.mqh | Telegram提醒 | 8KB |
| WyckoffPatterns.mqh | 威科夫形态识别 | 14KB |
| TripleTimeframe_Backtest.mq5 | 回测分析脚本 | 16KB |

---

有任何问题随时问我！🌸
