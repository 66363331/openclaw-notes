# 三重周期 EA 完整测试工作流
# 使用 day-trading-skill + rho-telegram-alerts

## 🎯 测试目标
验证 EA 在不同市场条件下的表现，并通过 Telegram 实时接收交易提醒

---

## 📦 已安装 Skills

| Skill | 用途 | 状态 |
|-------|------|------|
| day-trading-skill 💹 | 风险评估、策略验证 | ✅ 就绪 |
| rho-telegram-alerts 📱 | 交易提醒、日报 | ✅ 就绪 |
| coding-agent 🧩 | 代码生成、调试 | ✅ 就绪 |

---

## 🔧 Step 1: 配置 Telegram 提醒

### 1.1 创建 Bot
```
1. Telegram 搜索 @BotFather
2. 发送 /newbot
3. 命名: honeyray_gold_bot
4. 复制 Token: 123456789:ABCdef...
```

### 1.2 获取 Chat ID
```
1. 给 bot 发消息: /start
2. 浏览器访问:
   https://api.telegram.org/bot<TOKEN>/getUpdates
3. 找到 "chat":{"id":123456789
```

### 1.3 配置 EA 参数
```mql5
// 在 TripleTimeframe_EA.mq5 中添加
input string Inp_TelegramBotToken = "123456789:YOUR_TOKEN";  
input string Inp_TelegramChatID   = "123456789";
input bool   Inp_TelegramEnabled  = true;
```

---

## 🧪 Step 2: 模拟账户测试流程

### Phase 1: 基础功能测试 (1-3天)

**目标**: 验证信号生成逻辑

```
□ 加载 TripleTimeframe_Signal.mq5 指标
□ 观察 H1 EMA 排列
□ 等待 M15 确认同向
□ 记录 M3 出现的威科夫形态
□ 验证信号准确性
```

**使用 day-trading-skill 分析**:
```
"分析过去10个信号，计算胜率"
"这个进场点的风险回报比是否合理？"
"威科夫弹簧形态的识别准确率如何？"
```

**Telegram 接收示例**:
```
📈 SIGNAL DETECTED

Asset: XAU/USD
Pattern: 弹簧(Spring)
Direction: BULLISH
Strength: 8.2/10
Price: 5278.50

_2026-03-01 14:30_
```

---

### Phase 2: 风险管理测试 (1周)

**目标**: 验证风控系统

```
□ 故意触发止损，验证止损执行
□ 测试最大每日交易次数限制
□ 测试交易时段过滤
□ 验证追踪止盈功能
```

**使用 day-trading-skill**:
```
"计算连续5次亏损后的账户回撤"
"当前仓位大小对于$10,000账户是否合适？"
"如何设置动态仓位管理？"
```

**Telegram 风控提醒**:
```
⚠️ STOP LOSS WARNING

Asset: XAU/USD
Current: 5275.20
Stop Loss: 5273.50
Remaining: 17.0 pips

_Consider manual intervention_
```

---

### Phase 3: 全流程自动交易测试 (2周)

**目标**: 验证完整的自动交易流程

```
□ 加载 TripleTimeframe_EA.mq5
□ 设置 Inp_AutoTrading = true
□ 设置小手数 0.01
□ 记录所有交易
□ 分析结果
```

**每日 Telegram 日报**:
```
📊 DAILY TRADING SUMMARY

Total Trades: 3
Wins: 2
Losses: 1
Win Rate: 66.7%
Net P&L: 🟢 $45.50
Max Drawdown: 1.2%

_2026-03-01_
```

---

## 📊 Step 3: 数据分析

### 收集的数据

| 指标 | 目标值 | 实际值 |
|------|--------|--------|
| 胜率 | >50% | ? |
| 盈亏比 | >1.5:1 | ? |
| 最大回撤 | <5% | ? |
| 月均交易 | 20-30 | ? |
| 净利润 | >5%/月 | ? |

### 使用 day-trading-skill 优化

```
"根据这些回测数据，如何优化 VolumeRatio 参数？"
"当前胜率48%，需要调整哪些参数提升到55%？"
"分析亏损交易，找出共同特征"
```

---

## 🚀 Step 4: 逐步上线

### 阶段1: 小资金实盘 (1个月)
```
- 资金: $1,000
- 手数: 0.01
- 严格风控
- 每日复盘
```

### 阶段2: 加仓 (月盈利 >5%)
```
- 资金: $5,000
- 手数: 0.02-0.03
- 继续监控
```

### 阶段3: 标准仓位 (连续3月盈利)
```
- 资金: $10,000+
- 手数: 0.05
- 完全自动化
```

---

## ⚠️ 风险警示 (day-trading-skill 提醒)

### 必须遵守的规则:

1. ❌ **永远不要**在连续亏损3次后报复性加仓
2. ❌ **必须**在模拟账户验证至少2周才能实盘
3. ❌ **禁止**超过每日最大交易次数
4. ✅ **每次**交易前检查风险回报比
5. ✅ **亏损日**强制停止交易
6. ✅ **每周**使用 day-trading-skill 复盘

---

## 📱 Telegram 提醒配置清单

```
□ Bot Token 已配置
□ Chat ID 已获取
□ EA参数已设置
□ 测试消息已发送
□ 每日日报已启用
□ 风控提醒已启用
```

---

## 📝 测试记录模板

```markdown
## 测试日期: 2026-03-XX

### 市场条件
- 趋势: 多头/空头/震荡
- 波动率: 高/中/低
- 重要事件: 无/非农数据/利率决议

### 信号统计
- 总信号: X
- 做多: X
- 做空: X
- 正确: X
- 错误: X

### 问题记录
- [ ] 问题1
- [ ] 问题2

### 优化建议
- 
```

---

## ✅ 测试通过标准

- [ ] 信号准确率 > 50%
- [ ] 盈亏比 > 1.5:1
- [ ] 最大回撤 < 5%
- [ ] Telegram 提醒正常
- [ ] 连续2周稳定运行
- [ ] day-trading-skill 风险评估通过

---

**准备开始测试了吗？** 🌸
