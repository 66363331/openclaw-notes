//+------------------------------------------------------------------+
//| 威科夫形态识别模块 - 增强版                                       |
//| Wyckoff Pattern Recognition Module                              |
//| 包含：弹簧(Spring)、上推(Upthrust)、测试(Test)、突破(Breakout)    |
//+------------------------------------------------------------------+

#ifndef WYCKOFF_PATTERNS_MQH
#define WYCKOFF_PATTERNS_MQH

//+------------------------------------------------------------------+
//| 威科夫形态枚举                                                    |
//+------------------------------------------------------------------+
enum ENUM_WYCKOFF_PATTERN
{
   PATTERN_NONE = 0,           // 无形态
   PATTERN_SPRING = 1,         // 弹簧（向下洗盘后反弹）
   PATTERN_UPTHRUST = 2,       // 上推（向上假突破后回落）
   PATTERN_TEST = 3,           // 测试（缩量回踩支撑/阻力）
   PATTERN_BREAKOUT = 4,       // 突破（放量突破关键位）
   PATTERN_EFFORT_RALLY = 5,   // 努力上涨（放量上涨）
   PATTERN_EFFORT_DECLINE = 6  // 努力下跌（放量下跌）
};

//+------------------------------------------------------------------+
//| 形态识别结构体                                                    |
//+------------------------------------------------------------------+
struct WyckoffPattern
{
   ENUM_WYCKOFF_PATTERN type;   // 形态类型
   string name;                 // 形态名称
   double strength;             // 形态强度 0-1
   string description;          // 描述
   bool isBullish;              // 是否看涨
};

//+------------------------------------------------------------------+
//| 威科夫形态识别类                                                  |
//+------------------------------------------------------------------+
class CWyckoffPatterns
{
private:
   int    m_VolumeLookback;     // 成交量回看
   double m_VolumeRatio;        // 放量倍数
   double m_ShadowRatio;        // 影线比例
   
public:
   // 构造函数
   CWyckoffPatterns(int volLookback=20, double volRatio=1.5, double shadowRatio=0.5)
   {
      m_VolumeLookback = volLookback;
      m_VolumeRatio = volRatio;
      m_ShadowRatio = shadowRatio;
   }
   
   //+--------------------------------------------------------------+
   //| 1. 弹簧形态 (Spring) - 看涨信号                               |
   //| 特征：价格跌破支撑后快速收回，长下影线，放量                    |
   //+--------------------------------------------------------------+
   bool DetectSpring(double &strength)
   {
      double open = iOpen(_Symbol, PERIOD_M3, 0);
      double high = iHigh(_Symbol, PERIOD_M3, 0);
      double low  = iLow(_Symbol, PERIOD_M3, 0);
      double close = iClose(_Symbol, PERIOD_M3, 0);
      
      double range = high - low;
      double body = MathAbs(close - open);
      double lowerShadow = MathMin(open, close) - low;
      double upperShadow = high - MathMax(open, close);
      
      if(range == 0) return false;
      
      // 弹簧条件：
      // 1. 长下影线（> 实体2倍）
      bool longLowerShadow = lowerShadow > body * 2.0;
      
      // 2. 收盘在高位（> 60%范围）
      bool strongClose = (close - low) / range > 0.6;
      
      // 3. 放量
      bool volumeOK = IsVolumeSpike();
      
      // 4. 阴线转阳线或下影线极长
      bool patternOK = (close > open) || (lowerShadow > range * 0.6);
      
      strength = (lowerShadow / range) * GetVolumeRatio();
      
      return longLowerShadow && strongClose && volumeOK && patternOK;
   }
   
   //+--------------------------------------------------------------+
   //| 2. 上推形态 (Upthrust) - 看跌信号                             |
   //| 特征：价格突破阻力后快速回落，长上影线，放量                    |
   //+--------------------------------------------------------------+
   bool DetectUpthrust(double &strength)
   {
      double open = iOpen(_Symbol, PERIOD_M3, 0);
      double high = iHigh(_Symbol, PERIOD_M3, 0);
      double low  = iLow(_Symbol, PERIOD_M3, 0);
      double close = iClose(_Symbol, PERIOD_M3, 0);
      
      double range = high - low;
      double body = MathAbs(close - open);
      double upperShadow = high - MathMax(open, close);
      double lowerShadow = MathMin(open, close) - low;
      
      if(range == 0) return false;
      
      // 上推条件：
      // 1. 长上影线（> 实体2倍）
      bool longUpperShadow = upperShadow > body * 2.0;
      
      // 2. 收盘在低位（< 40%范围）
      bool weakClose = (close - low) / range < 0.4;
      
      // 3. 放量
      bool volumeOK = IsVolumeSpike();
      
      // 4. 阳线转阴线上影线极长
      bool patternOK = (close < open) || (upperShadow > range * 0.6);
      
      strength = (upperShadow / range) * GetVolumeRatio();
      
      return longUpperShadow && weakClose && volumeOK && patternOK;
   }
   
   //+--------------------------------------------------------------+
   //| 3. 测试形态 (Test) - 确认信号                                  |
   //| 特征：缩量回踩支撑或阻力，确认关键位有效                        |
   //+--------------------------------------------------------------+
   bool DetectTest(bool isSupport, double &strength)
   {
      double open = iOpen(_Symbol, PERIOD_M3, 0);
      double high = iHigh(_Symbol, PERIOD_M3, 0);
      double low  = iLow(_Symbol, PERIOD_M3, 0);
      double close = iClose(_Symbol, PERIOD_M3, 0);
      
      double range = high - low;
      double body = MathAbs(close - open);
      
      if(range == 0) return false;
      
      // 测试条件：
      // 1. 缩量（< 0.8倍均量）
      bool lowVolume = GetVolumeRatio() < 0.8;
      
      // 2. 小实体（< 40%范围）
      bool smallBody = body / range < 0.4;
      
      // 3. 支撑测试：收盘在高位；阻力测试：收盘在低位
      bool closePosition = isSupport ? 
         ((close - low) / range > 0.6) : ((high - close) / range > 0.6);
      
      strength = 1.0 - GetVolumeRatio(); // 缩量越严重，强度越高
      
      return lowVolume && smallBody && closePosition;
   }
   
   //+--------------------------------------------------------------+
   //| 4. 突破形态 (Breakout) - 趋势启动信号                           |
   //| 特征：放量突破关键位，大实体，收盘在极端位置                    |
   //+--------------------------------------------------------------+
   bool DetectBreakout(bool isBullish, double &strength)
   {
      double open = iOpen(_Symbol, PERIOD_M3, 0);
      double high = iHigh(_Symbol, PERIOD_M3, 0);
      double low  = iLow(_Symbol, PERIOD_M3, 0);
      double close = iClose(_Symbol, PERIOD_M3, 0);
      
      double range = high - low;
      double body = MathAbs(close - open);
      
      if(range == 0) return false;
      
      // 突破条件：
      // 1. 大实体（> 60%范围）
      bool largeBody = body / range > 0.6;
      
      // 2. 放量（> 1.5倍）
      bool volumeOK = IsVolumeSpike();
      
      // 3. 收盘极端位置
      bool extremeClose = isBullish ? 
         ((close - low) / range > 0.75) : ((high - close) / range > 0.75);
      
      // 4. 方向正确
      bool directionOK = isBullish ? (close > open) : (close < open);
      
      strength = (body / range) * GetVolumeRatio();
      
      return largeBody && volumeOK && extremeClose && directionOK;
   }
   
   //+--------------------------------------------------------------+
   //| 5. 努力上涨 (Effort to Rally)                                  |
   //| 特征：放量上涨，但收盘不在高位（上涨遇阻）                      |
   //+--------------------------------------------------------------+
   bool DetectEffortRally(double &strength)
   {
      double open = iOpen(_Symbol, PERIOD_M3, 0);
      double high = iHigh(_Symbol, PERIOD_M3, 0);
      double low  = iLow(_Symbol, PERIOD_M3, 0);
      double close = iClose(_Symbol, PERIOD_M3, 0);
      
      double range = high - low;
      double upperShadow = high - close;
      
      if(range == 0) return false;
      
      bool upMove = close > open;
      bool volumeOK = IsVolumeSpike();
      bool rejection = (upperShadow / range) > 0.3; // 上影线存在
      
      strength = GetVolumeRatio() * (1.0 - (close - low) / range);
      
      return upMove && volumeOK && rejection;
   }
   
   //+--------------------------------------------------------------+
   //| 6. 努力下跌 (Effort to Decline)                                |
   //| 特征：放量下跌，但收盘不在低位（下跌遇支撑）                    |
   //+--------------------------------------------------------------+
   bool DetectEffortDecline(double &strength)
   {
      double open = iOpen(_Symbol, PERIOD_M3, 0);
      double high = iHigh(_Symbol, PERIOD_M3, 0);
      double low  = iLow(_Symbol, PERIOD_M3, 0);
      double close = iClose(_Symbol, PERIOD_M3, 0);
      
      double range = high - low;
      double lowerShadow = close - low;
      
      if(range == 0) return false;
      
      bool downMove = close < open;
      bool volumeOK = IsVolumeSpike();
      bool support = (lowerShadow / range) > 0.3; // 下影线存在
      
      strength = GetVolumeRatio() * ((high - close) / range);
      
      return downMove && volumeOK && support;
   }
   
   //+--------------------------------------------------------------+
   //| 综合形态识别 - 返回最强形态                                    |
   //+--------------------------------------------------------------+
   WyckoffPattern DetectStrongestPattern()
   {
      WyckoffPattern pattern;
      pattern.type = PATTERN_NONE;
      pattern.strength = 0;
      
      double strength;
      
      // 检测所有形态，返回最强的
      if(DetectSpring(strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_SPRING;
         pattern.name = "弹簧(Spring)";
         pattern.strength = strength;
         pattern.description = "向下洗盘后快速反弹，长下影线，放量";
         pattern.isBullish = true;
      }
      
      if(DetectUpthrust(strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_UPTHRUST;
         pattern.name = "上推(Upthrust)";
         pattern.strength = strength;
         pattern.description = "向上假突破后回落，长上影线，放量";
         pattern.isBullish = false;
      }
      
      if(DetectTest(true, strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_TEST;
         pattern.name = "测试支撑(Test)";
         pattern.strength = strength;
         pattern.description = "缩量回踩支撑，确认有效";
         pattern.isBullish = true;
      }
      
      if(DetectTest(false, strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_TEST;
         pattern.name = "测试阻力(Test)";
         pattern.strength = strength;
         pattern.description = "缩量回踩阻力，确认有效";
         pattern.isBullish = false;
      }
      
      if(DetectBreakout(true, strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_BREAKOUT;
         pattern.name = "突破(Breakout)";
         pattern.strength = strength;
         pattern.description = "放量突破阻力位，趋势启动";
         pattern.isBullish = true;
      }
      
      if(DetectBreakout(false, strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_BREAKOUT;
         pattern.name = "下破(Breakdown)";
         pattern.strength = strength;
         pattern.description = "放量跌破支撑位，趋势反转";
         pattern.isBullish = false;
      }
      
      if(DetectEffortRally(strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_EFFORT_RALLY;
         pattern.name = "努力上涨(Effort Rally)";
         pattern.strength = strength;
         pattern.description = "放量上涨但遇阻，可能回调";
         pattern.isBullish = false; // 警示信号
      }
      
      if(DetectEffortDecline(strength) && strength > pattern.strength)
      {
         pattern.type = PATTERN_EFFORT_DECLINE;
         pattern.name = "努力下跌(Effort Decline)";
         pattern.strength = strength;
         pattern.description = "放量下跌但遇支撑，可能反弹";
         pattern.isBullish = true; // 警示信号
      }
      
      return pattern;
   }
   
private:
   //+--------------------------------------------------------------+
   //| 检查是否放量                                                    |
   //+--------------------------------------------------------------+
   bool IsVolumeSpike()
   {
      return GetVolumeRatio() > m_VolumeRatio;
   }
   
   //+--------------------------------------------------------------+
   //| 获取当前成交量/均量比                                           |
   //+--------------------------------------------------------------+
   double GetVolumeRatio()
   {
      long volume[];
      ArraySetAsSeries(volume, true);
      
      if(CopyTickVolume(_Symbol, PERIOD_M3, 0, m_VolumeLookback, volume) < m_VolumeLookback)
         return 1.0;
      
      double avgVolume = 0;
      for(int i = 1; i < m_VolumeLookback; i++)
         avgVolume += (double)volume[i];
      avgVolume /= (m_VolumeLookback - 1);
      
      if(avgVolume == 0) return 1.0;
      
      return (double)volume[0] / avgVolume;
   }
};

#endif // WYCKOFF_PATTERNS_MQH
