#!/bin/bash
# MQL5 编译和测试脚本
# 用于编译三重周期EA和指标

echo "==============================================="
echo "  Triple Timeframe EA - 编译测试脚本"
echo "==============================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 路径设置
WORKSPACE="/home/lilei/.openclaw/workspace"
MQL5_DIR="$WORKSPACE/mql5"
METAEDITOR="C:/Program Files/MetaTrader 5/metaeditor64.exe"
MT5_DIR="C:/Program Files/MetaTrader 5/MQL5"

# 检查文件
echo "📁 检查源文件..."
FILES=(
    "TripleTimeframe_Signal.mq5"
    "TripleTimeframe_EA.mq5"
    "WyckoffPatterns.mqh"
)

for file in "${FILES[@]}"; do
    if [ -f "$MQL5_DIR/$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file (缺失)"
    fi
done

echo ""
echo "==============================================="
echo "  手动编译步骤"
echo "==============================================="
echo ""

cat << 'EOF'
在 Windows 上执行以下步骤：

1️⃣ 复制文件到 MT5 目录
   源文件位置：\wsl.localhost\Ubuntu\home\lilei\.openclaw\workspace\mql5\
   
   复制到：
   C:\Program Files\MetaTrader 5\MQL5\Indicators\TripleTimeframe_Signal.mq5
   C:\Program Files\MetaTrader 5\MQL5\Experts\TripleTimeframe_EA.mq5
   C:\Program Files\MetaTrader 5\MQL5\Include\WyckoffPatterns.mqh

2️⃣ 在 MetaEditor 中打开项目
   - 打开 MetaTrader 5
   - 按 F4 打开 MetaEditor
   - 文件 → 打开 → 选择对应文件

3️⃣ 编译 (F7)
   编译 TripleTimeframe_Signal.mq5
   编译 TripleTimeframe_EA.mq5

4️⃣ 检查错误
   查看 "错误" 标签页
   应显示 "0 errors, 0 warnings"

5️⃣ 在 MT5 中加载
   - 指标：导航器 → 技术指标 → 双击 TripleTimeframe_Signal
   - EA：导航器 → 智能交易系统 → 双击 TripleTimeframe_EA

EOF

echo ""
echo "==============================================="
echo "  常见问题解决"
echo "==============================================="
echo ""

cat << 'EOF'
❌ 错误: "Cannot open include file"
✅ 解决: 确保 WyckoffPatterns.mqh 在 MQL5/Include/ 目录

❌ 错误: "Function not defined"
✅ 解决: 重新启动 MetaEditor

❌ 错误: "Trade class not found"
✅ 解决: 确保使用 #include <Trade\Trade.mqh>

❌ 无法加载到图表
✅ 解决: 检查 "自动交易" 按钮是否启用（工具栏绿色按钮）

EOF

echo ""
echo "==============================================="
echo "  测试清单"
echo "==============================================="
echo ""

cat << 'EOF'
✅ 编译通过后，按以下步骤测试：

□ 1. 在模拟账户测试
   文件 → 开新模拟账户

□ 2. 加载指标版本
   - 打开 XAU/USD M3 图表
   - 加载 TripleTimeframe_Signal
   - 观察是否出现箭头信号

□ 3. 检查信号逻辑
   - 等待 H1 和 M15 EMA 同向
   - 观察 M3 出现威科夫形态
   - 确认弹出 Alert 提醒

□ 4. 测试 EA（模拟账户）
   - 加载 TripleTimeframe_EA
   - 设置 Inp_AutoTrading = false（仅提醒模式）
   - 观察信号是否准确
   
□ 5. 开启自动交易（谨慎）
   - 确保是模拟账户
   - 设置小手数 0.01
   - 观察开平仓逻辑

□ 6. 记录测试结果
   - 记录信号数量
   - 记录胜率
   - 记录盈亏比

EOF

echo ""
echo "==============================================="
echo "  参数配置文件"
echo "==============================================="
echo ""

cat << 'EOF'
保存为 optimized_params.set：

[EA Parameters]
EMA_Fast=20
EMA_Mid=50
EMA_Slow=200
VolumeLookback=20
VolumeRatio=1.5
BodyRatio=0.6
SignalCooldown=5
LotSize=0.01
StopLoss=50
TakeProfit=100
UseTrailing=true
TrailingStart=30
TrailingStop=20
MaxDailyTrades=5
MaxSpread=30
AlertEnabled=true
SendNotification=true
EOF

echo ""
echo "==============================================="
echo "  文件位置"
echo "==============================================="
echo ""
echo "📁 源文件: $MQL5_DIR"
echo ""
ls -la "$MQL5_DIR"
echo ""
echo "==============================================="
echo "  完成！"
echo "==============================================="
