# 反马丁EA技术规格书（给AI程序员）

> 版本：v3.0 - AI编程专用版
> 目标：直接转换为MQL4/MQL5代码
> 格式：结构化输入/输出/状态/伪代码

---

## 一、系统概述

### 1.1 输入
- 首仓订单：由人工在MT4/MT5手动开仓
- 市场数据：Bid, Ask, 时间

### 1.2 输出
- 加仓订单（同向）
- 止损修改
- 平仓指令

### 1.3 核心规则
```
RULE #1: 只在首仓盈利时加仓（顺势）
RULE #2: 每次加仓手数递减（系数0.8）
RULE #3: 亏损绝不加仓
RULE #4: 整体成本价上移后触发保本止损
RULE #5: 账户浮亏≥3%时强制全部平仓
```

---

## 二、数据结构

### 2.1 全局变量
```cpp
// 首仓信息
int FirstTicket;           // 首仓订单号
datetime FirstOpenTime;    // 首仓开仓时间
int FirstType;             // 首仓类型 OP_BUY/OP_SELL
double FirstOpenPrice;     // 首仓开仓价
double FirstLots;          // 首仓手数
double FirstSL;            // 首仓止损价

// EA状态
int State;                 // 0=待机 1=监控 2=加仓中 3=已保本 4=冷却
int AddCount;              // 已加仓次数
double LastAddPrice;       // 上次加仓价格
bool IsBreakeven;          // 是否已保本
double HighestPrice;       // 最高价（追踪止损用）
double LowestPrice;        // 最低价（追踪止损用）
datetime LastTradeTime;    // 上次交易时间（冷却期用）

// 整体成本
double TotalCostPrice;     // 整体成本价
double TotalLots;          // 总持仓手数
```

### 2.2 配置参数（Input）
```cpp
input int AddStartPips = 150;           // 首仓盈利多少点开始第1次加仓
input int AddSpacingPips = 100;         // 每次加仓间距（点）
input double AddLotRatio = 0.8;         // 加仓手数递减比例
input int MaxAddOrders = 5;             // 最大加仓次数
input double MaxTotalLots = 3.5;        // 总仓位上限（手）
input int StopLossPips = 80;            // 首仓硬止损（点）
input int BreakevenTriggerPips = 50;    // 启动保本止损的盈利点数
input int BreakEvenOffsetPips = 10;     // 保本价偏移
input int TrailingStartPips = 100;      // 启动追踪止损的盈利点数
input int TrailingStepPips = 50;        // 追踪止损步长
input double AccountRiskPercent = 3.0;  // 账户总风险百分比
input int MagicNumber = 20260303;       // EA订单标识
```

---

## 三、状态机（核心）

### 3.1 状态定义
```
STATE_IDLE = 0          // 待机：等待首仓
STATE_MONITORING = 1    // 监控：等待加仓条件
STATE_ADDING = 2        // 加仓中：已加仓，继续监控
STATE_BREAKEVEN = 3     // 已保本：移动止损保护中
STATE_COOLDOWN = 4      // 冷却期：亏损后等待
```

### 3.2 状态转换表
```
当前状态        事件                        新状态              动作
--------------------------------------------------------------------------------
STATE_IDLE      检测到新的手动首仓           STATE_MONITORING    记录首仓信息
STATE_IDLE      未检测到首仓                 STATE_IDLE          无

STATE_MONITORING 首仓触发止损               STATE_COOLDOWN      全部平仓，记录亏损
STATE_MONITORING 时间超时(48h)              STATE_IDLE          全部平仓
STATE_MONITORING 盈利≥AddStartPips          STATE_ADDING        第1次加仓

STATE_ADDING    加仓次数≥MaxAddOrders       STATE_BREAKEVEN     不再加仓，监控保本
STATE_ADDING    最新单盈利≥BreakevenTrigger STATE_BREAKEVEN     全部移止损至保本
STATE_ADDING    间距≥AddSpacingPips         STATE_ADDING        继续加仓
STATE_ADDING    首仓触发止损               STATE_COOLDOWN      全部平仓

STATE_BREAKEVEN 回撤触及保本止损            STATE_COOLDOWN      全部平仓（保本或小盈）
STATE_BREAKEVEN 盈利≥TrailingStart         STATE_BREAKEVEN     启动/更新追踪止损
STATE_BREAKEVEN 回撤触及Trailing           STATE_COOLDOWN      全部平仓（止盈）

STATE_COOLDOWN  冷却时间≥24h               STATE_IDLE          重置，等待新首仓
```

---

## 四、核心函数（伪代码）

### 4.1 主循环
```cpp
void OnTick() {
    // 1. 检查账户总风险（最高优先级）
    if (CheckAccountRisk()) {
        CloseAllOrders();
        State = STATE_COOLDOWN;
        LastTradeTime = TimeCurrent();
        return;
    }
    
    // 2. 状态机处理
    switch(State) {
        case STATE_IDLE:
            DetectFirstOrder();
            break;
        case STATE_MONITORING:
            CheckStopLoss();
            CheckFirstAddCondition();
            CheckTimeExit();
            break;
        case STATE_ADDING:
            CheckStopLoss();
            CheckBreakevenCondition();
            CheckNextAddCondition();
            break;
        case STATE_BREAKEVEN:
            CheckBreakevenStop();
            UpdateTrailingStop();
            break;
        case STATE_COOLDOWN:
            CheckCooldown();
            break;
    }
}
```

### 4.2 检测首仓
```cpp
void DetectFirstOrder() {
    // 遍历所有订单，找MagicNumber=0的手动单
    for (i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderMagicNumber() == 0 && OrderSymbol() == Symbol()) {
                // 检查是否为新单（5分钟内）
                if (TimeCurrent() - OrderOpenTime() <= 300) {
                    FirstTicket = OrderTicket();
                    FirstOpenTime = OrderOpenTime();
                    FirstType = OrderType();
                    FirstOpenPrice = OrderOpenPrice();
                    FirstLots = OrderLots();
                    FirstSL = OrderStopLoss();
                    
                    LastAddPrice = FirstOpenPrice;
                    TotalCostPrice = FirstOpenPrice;
                    TotalLots = FirstLots;
                    
                    State = STATE_MONITORING;
                    break;
                }
            }
        }
    }
}
```

### 4.3 检查首次加仓条件
```cpp
void CheckFirstAddCondition() {
    if (AddCount > 0) return; // 已有加仓，走其他逻辑
    
    double profitPips = CalculateProfitPips(FirstOpenPrice, FirstType);
    
    if (profitPips >= AddStartPips) {
        OpenAddOrder();
    }
}

// 计算盈利点数
double CalculateProfitPips(double openPrice, int type) {
    if (type == OP_BUY) {
        return (Bid - openPrice) / Point;
    } else {
        return (openPrice - Ask) / Point;
    }
}
```

### 4.4 开仓加仓单
```cpp
void OpenAddOrder() {
    // 计算手数：Ln = L0 * r^n
    double lots = FirstLots * MathPow(AddLotRatio, AddCount + 1);
    lots = NormalizeDouble(lots, 2);
    
    // 检查总仓位限制
    double currentLots = GetTotalLots();
    if (currentLots + lots > MaxTotalLots) {
        Print("总仓位限制，无法加仓");
        return;
    }
    
    // 发送订单
    int type = FirstType; // 同向
    double price = (type == OP_BUY) ? Ask : Bid;
    int slippage = 3;
    
    int ticket = OrderSend(Symbol(), type, lots, price, slippage, 
                          0, 0, "AntiMartingale", MagicNumber, 0, clrGreen);
    
    if (ticket > 0) {
        AddCount++;
        LastAddPrice = price;
        UpdateTotalCost(); // 更新整体成本价
        State = STATE_ADDING;
        Print("加仓成功 #", AddCount, " 手数:", lots);
    } else {
        Print("加仓失败，错误:", GetLastError());
    }
}
```

### 4.5 更新整体成本价
```cpp
void UpdateTotalCost() {
    double totalCost = 0;
    double totalLots = 0;
    
    // 首仓
    totalCost += FirstOpenPrice * FirstLots;
    totalLots += FirstLots;
    
    // 所有EA加仓单
    for (i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol()) {
                totalCost += OrderOpenPrice() * OrderLots();
                totalLots += OrderLots();
            }
        }
    }
    
    TotalCostPrice = totalCost / totalLots;
    TotalLots = totalLots;
}
```

### 4.6 检查后续加仓条件
```cpp
void CheckNextAddCondition() {
    if (AddCount >= MaxAddOrders) return;
    
    double spacing = 0;
    if (FirstType == OP_BUY) {
        spacing = (Bid - LastAddPrice) / Point;
    } else {
        spacing = (LastAddPrice - Ask) / Point;
    }
    
    if (spacing >= AddSpacingPips) {
        OpenAddOrder();
    }
}
```

### 4.7 检查保本条件
```cpp
void CheckBreakevenCondition() {
    if (IsBreakeven) return;
    
    // 获取最新加仓单的盈利
    double latestProfit = GetLatestAddOrderProfit();
    
    if (latestProfit >= BreakevenTriggerPips) {
        MoveToBreakeven();
    }
}

// 移动所有订单止损至保本价+偏移
void MoveToBreakeven() {
    UpdateTotalCost(); // 确保成本价最新
    
    double newSL;
    if (FirstType == OP_BUY) {
        newSL = TotalCostPrice + BreakEvenOffsetPips * Point;
    } else {
        newSL = TotalCostPrice - BreakEvenOffsetPips * Point;
    }
    
    // 修改首仓止损
    if (FirstType == OP_BUY && newSL > FirstSL) {
        OrderModify(FirstTicket, FirstOpenPrice, newSL, OrderTakeProfit(), 0, clrBlue);
    } else if (FirstType == OP_SELL && newSL < FirstSL) {
        OrderModify(FirstTicket, FirstOpenPrice, newSL, OrderTakeProfit(), 0, clrBlue);
    }
    
    // 修改所有EA加仓单止损
    for (i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol()) {
                OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue);
            }
        }
    }
    
    IsBreakeven = true;
    State = STATE_BREAKEVEN;
    Print("已移至保本止损，价格:", newSL);
}
```

### 4.8 追踪止损
```cpp
void UpdateTrailingStop() {
    if (!IsBreakeven) return;
    
    // 更新最高/最低价
    if (FirstType == OP_BUY) {
        if (Bid > HighestPrice) HighestPrice = Bid;
        
        // 检查是否触发追踪止损移动
        double retrace = (HighestPrice - Bid) / Point;
        if (retrace >= TrailingStepPips) {
            double newSL = HighestPrice - TrailingStepPips * Point;
            double currentSL = GetCurrentSL();
            
            if (newSL > currentSL) {
                ModifyAllSL(newSL);
            }
        }
    } else { // OP_SELL
        if (Ask < LowestPrice) LowestPrice = Ask;
        
        double retrace = (Ask - LowestPrice) / Point;
        if (retrace >= TrailingStepPips) {
            double newSL = LowestPrice + TrailingStepPips * Point;
            double currentSL = GetCurrentSL();
            
            if (newSL < currentSL) {
                ModifyAllSL(newSL);
            }
        }
    }
}
```

### 4.9 检查止损
```cpp
void CheckStopLoss() {
    // 检查首仓是否触发硬止损
    bool hitSL = false;
    
    if (OrderSelect(FirstTicket, SELECT_BY_TICKET)) {
        if (OrderCloseTime() > 0) {
            // 首仓已平仓（被止损）
            hitSL = true;
        }
    }
    
    if (hitSL) {
        // 首仓被止损，EA所有加仓单也平掉
        CloseAllOrders();
        State = STATE_COOLDOWN;
        LastTradeTime = TimeCurrent();
        Print("首仓止损，全部平仓");
    }
}

// 平掉所有EA加仓单
void CloseAllOrders() {
    for (i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol()) {
                int type = OrderType();
                double price = (type == OP_BUY) ? Bid : Ask;
                OrderClose(OrderTicket(), OrderLots(), price, 3, clrRed);
            }
        }
    }
}
```

### 4.10 账户总风险检查
```cpp
bool CheckAccountRisk() {
    double balance = AccountBalance();
    double equity = AccountEquity();
    double loss = balance - equity;
    double lossPercent = (loss / balance) * 100;
    
    if (lossPercent >= AccountRiskPercent) {
        Print("账户风险超限:", lossPercent, "%");
        return true;
    }
    return false;
}
```

### 4.11 时间退出
```cpp
void CheckTimeExit() {
    datetime currentTime = TimeCurrent();
    
    // 检查持仓时间
    if (currentTime - FirstOpenTime >= MaxHoldHours * 3600) {
        // 检查是否有盈利
        double totalProfit = GetTotalProfit();
        if (totalProfit >= MinProfitPips * TotalLots * 10) { // $10 per pip per lot
            CloseAllOrders();
            State = STATE_COOLDOWN;
            Print("时间止盈，全部平仓");
        }
    }
}
```

### 4.12 冷却期检查
```cpp
void CheckCooldown() {
    if (TimeCurrent() - LastTradeTime >= 24 * 3600) {
        // 24小时冷却结束
        ResetAll();
        State = STATE_IDLE;
        Print("冷却期结束，重置EA");
    }
}

void ResetAll() {
    FirstTicket = 0;
    AddCount = 0;
    IsBreakeven = false;
    HighestPrice = 0;
    LowestPrice = 999999;
    TotalCostPrice = 0;
    TotalLots = 0;
}
```

---

## 五、初始化函数

```cpp
int OnInit() {
    // 重置所有状态
    ResetAll();
    State = STATE_IDLE;
    
    Print("反马丁EA启动，MagicNumber:", MagicNumber);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Print("反马丁EA停止");
}
```

---

## 六、关键计算验证

### 6.1 手数计算验证
```
输入：FirstLots=1.0, AddLotRatio=0.8

计算：
第1次：1.0 * 0.8^1 = 0.80
第2次：1.0 * 0.8^2 = 0.64
第3次：1.0 * 0.8^3 = 0.512 ≈ 0.51
第4次：1.0 * 0.8^4 = 0.4096 ≈ 0.41
第5次：1.0 * 0.8^5 = 0.32768 ≈ 0.33

总和：1.0 + 0.8 + 0.64 + 0.51 + 0.41 + 0.33 = 3.69手
```

### 6.2 成本价计算验证
```
输入：
首仓：2900.00 * 1.0
加1：2915.00 * 0.8
加2：2925.00 * 0.64

计算：
总成本 = 2900*1 + 2915*0.8 + 2925*0.64 = 2900 + 2332 + 1872 = 7104
总手数 = 1 + 0.8 + 0.64 = 2.44
成本价 = 7104 / 2.44 = 2911.475
```

---

## 七、给Claude的提示

1. **这是一个MT4/MT5的EA**，使用MQL4/MQL5语言
2. **核心逻辑是反马丁**：只在盈利时加仓，手数递减
3. **状态机是重点**：5个状态之间的转换必须清晰
4. **止损有4层**：首仓硬止损 → 保本止损 → 追踪止损 → 账户总风险
5. **必须先有手动首仓**，EA只负责加仓和管理
6. **MagicNumber用于区分EA单和手动单**

---

## 八、测试清单（给Claude）

写完代码后测试：
- [ ] EA启动后检测到手动首仓
- [ ] 盈利150点后触发第1次加仓
- [ ] 加仓手数为0.8倍首仓
- [ ] 再涨100点后触发第2次加仓
- [ ] 最新加仓单盈利50点后全部移至保本
- [ ] 价格回撤触及保本止损时全部平仓
- [ ] 首仓止损时EA加仓单也全部平仓
- [ ] 账户浮亏3%时强制全部平仓
- [ ] 冷却期24小时后重置

---

*这份规格书可以直接喂给Claude写代码*  
*所有函数都有伪代码，状态机完整，边界情况已定义*
