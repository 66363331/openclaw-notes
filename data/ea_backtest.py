#!/usr/bin/env python3
"""
EA 参数回测分析脚本
对比参数组 A 和参数组 B
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# 加载 tick 数据
DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

# 参数组定义
PARAMS_A = {
    'name': '参数组 A',
    'gTPDist': 13.0,        # 主止盈 13$
    'gLockDist': 3.0,       # 锁定触发 3$
    'gLockSL': 1.0,         # 锁定利润 1$
    'gTrailStart': 10.0,    # 追踪启动 10$
    'trailPct': 0.30,       # 回撤 30%
    'pyrStep': 3.0,         # 金字塔步距
    'pyrMax': 8,            # 最大层数
    'l1Dist': 23.0,         # L1距离
    'l2Dist': 45.0,         # L2距离
    'l2Mult': 2.0,          # L2倍率
    'hardLoss': 220.0,      # 硬止损
    'seedLot': 0.01,        # 首仓手数
}

PARAMS_B = {
    'name': '参数组 B',
    'gTPDist': 9.0,         # 主止盈 9$
    'gLockDist': 4.0,       # 锁定触发 4$
    'gLockSL': 1.2,         # 锁定利润 1.2$
    'gTrailStart': 8.0,     # 追踪启动 8$
    'trailPct': 0.20,       # 回撤 20%
    'pyrStep': 3.0,
    'pyrMax': 8,
    'l1Dist': 23.0,
    'l2Dist': 45.0,
    'l2Mult': 2.0,
    'hardLoss': 220.0,
    'seedLot': 0.01,
}

def load_data():
    """加载 tick 数据"""
    print("加载数据...")
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    print(f"数据范围: {df['datetime'].min()} 至 {df['datetime'].max()}")
    print(f"总数据量: {len(df):,} 条")
    return df

def calculate_pip_value(lots, price):
    """计算每点价值 (XAUUSD: 1点 = 0.01美元 = 1 pip)"""
    # 标准手: 1手 = 100盎司
    # 0.01手 = 1盎司
    # 价格变动 0.01美元 = 1 pip = $0.01 per ounce
    return lots * 100 * 0.01  # 简化计算

class EABacktest:
    """EA 回测引擎"""
    def __init__(self, params, df):
        self.params = params
        self.df = df
        self.trades = []
        self.daily_pnl = []
        
    def run(self):
        """运行回测"""
        print(f"\n{'='*60}")
        print(f"回测: {self.params['name']}")
        print(f"{'='*60}")
        
        # 简化回测逻辑：模拟每日交易
        # 按天聚合数据
        self.df['date'] = self.df['datetime'].dt.date
        
        total_profit = 0
        total_loss = 0
        win_count = 0
        loss_count = 0
        
        # 简化的交易模拟
        # 假设每天开仓一次，根据参数决定出场
        for date, group in self.df.groupby('date'):
            if len(group) < 100:
                continue
                
            # 模拟首仓
            entry_price = group.iloc[0]['mid']
            direction = 1  # 假设做多（简化）
            
            # 计算当日最高浮盈
            if direction == 1:
                max_delta = (group['mid'].max() - entry_price)
                final_delta = group.iloc[-1]['mid'] - entry_price
            else:
                max_delta = (entry_price - group['mid'].min())
                final_delta = entry_price - group.iloc[-1]['mid']
            
            # 检查是否触发止盈
            pnl = self.simulate_trade(entry_price, direction, group)
            
            if pnl > 0:
                total_profit += pnl
                win_count += 1
            else:
                total_loss += abs(pnl)
                loss_count += 1
                
        # 计算指标
        total_trades = win_count + loss_count
        win_rate = win_count / total_trades * 100 if total_trades > 0 else 0
        profit_factor = total_profit / total_loss if total_loss > 0 else float('inf')
        net_profit = total_profit - total_loss
        
        return {
            'name': self.params['name'],
            'total_trades': total_trades,
            'win_count': win_count,
            'loss_count': loss_count,
            'win_rate': win_rate,
            'profit_factor': profit_factor,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'net_profit': net_profit,
        }
    
    def simulate_trade(self, entry_price, direction, price_series):
        """模拟单笔交易"""
        p = self.params
        
        # 简化模拟：追踪止盈逻辑
        if direction == 1:  # 做多
            prices = price_series['mid'].values
            deltas = prices - entry_price
        else:  # 做空
            prices = price_series['mid'].values
            deltas = entry_price - prices
            
        peak_delta = 0
        trailing = False
        
        for i, delta in enumerate(deltas):
            if delta > peak_delta:
                peak_delta = delta
                
            # 检查追踪启动
            if not trailing and delta >= p['gTrailStart']:
                trailing = True
                
            # 检查追踪出场
            if trailing:
                exit_threshold = peak_delta * (1 - p['trailPct'])
                if delta <= exit_threshold:
                    return delta * p['seedLot'] * 100  # 简化盈亏计算
                    
            # 检查主止盈
            if not trailing and delta >= p['gTPDist']:
                return p['gTPDist'] * p['seedLot'] * 100
                
            # 检查硬止损
            if delta <= -p['hardLoss'] / (p['seedLot'] * 100):
                return -p['hardLoss']
                
        # 未触发任何条件，按收盘结算
        return deltas[-1] * p['seedLot'] * 100

def print_results(result):
    """打印回测结果"""
    print(f"\n📊 {result['name']} 回测结果")
    print("-" * 40)
    print(f"总交易次数: {result['total_trades']}")
    print(f"盈利次数: {result['win_count']}")
    print(f"亏损次数: {result['loss_count']}")
    print(f"胜率: {result['win_rate']:.2f}%")
    print(f"盈利因子: {result['profit_factor']:.2f}")
    print(f"总盈利: ${result['total_profit']:.2f}")
    print(f"总亏损: ${result['total_loss']:.2f}")
    print(f"净利润: ${result['net_profit']:.2f}")

def main():
    # 加载数据
    df = load_data()
    
    # 运行回测 - 参数组 A
    backtest_a = EABacktest(PARAMS_A, df)
    result_a = backtest_a.run()
    print_results(result_a)
    
    # 运行回测 - 参数组 B
    backtest_b = EABacktest(PARAMS_B, df)
    result_b = backtest_b.run()
    print_results(result_b)
    
    # 对比分析
    print(f"\n{'='*60}")
    print("📈 参数对比分析")
    print(f"{'='*60}")
    
    print(f"\n盈利因子对比:")
    print(f"  参数组 A: {result_a['profit_factor']:.2f}")
    print(f"  参数组 B: {result_b['profit_factor']:.2f}")
    winner_pf = 'A' if result_a['profit_factor'] > result_b['profit_factor'] else 'B'
    print(f"  🏆  winner: 参数组 {winner_pf}")
    
    print(f"\n净利润对比:")
    print(f"  参数组 A: ${result_a['net_profit']:.2f}")
    print(f"  参数组 B: ${result_b['net_profit']:.2f}")
    winner_np = 'A' if result_a['net_profit'] > result_b['net_profit'] else 'B'
    print(f"  🏆  winner: 参数组 {winner_np}")
    
    print(f"\n胜率对比:")
    print(f"  参数组 A: {result_a['win_rate']:.2f}%")
    print(f"  参数组 B: {result_b['win_rate']:.2f}%")
    
    # 推荐最优参数
    print(f"\n{'='*60}")
    print("🎯 最优参数推荐")
    print(f"{'='*60}")
    
    if result_a['profit_factor'] > result_b['profit_factor'] and result_a['net_profit'] > result_b['net_profit']:
        print("推荐: 参数组 A (全面领先)")
        print("特点: 更高的追踪回撤容忍度(30%)，更晚启动追踪，更大的止盈空间")
    elif result_b['profit_factor'] > result_a['profit_factor'] and result_b['net_profit'] > result_a['net_profit']:
        print("推荐: 参数组 B (全面领先)")
        print("特点: 更保守的追踪回撤(20%)，更早启动追踪，更快锁定利润")
    else:
        print("各有优势，根据风险偏好选择:")
        print(f"  - 追求高盈利因子: 参数组 {winner_pf}")
        print(f"  - 追求稳定收益: 参数组 {'B' if winner_pf == 'A' else 'A'}")

if __name__ == "__main__":
    main()
