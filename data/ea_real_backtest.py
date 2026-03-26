#!/usr/bin/env python3
"""
EA 真实交易模拟回测
包含：合理开仓条件 + 马丁补仓 + 金字塔加仓 + 真实止盈止损
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

DATA_FILE = "/home/lilei/.openclaw/workspace/data/dukascopy/ms_aligned/XAUUSD_tick_combined_ms_aligned.csv"

# 参数
PARAMS = {
    'trailPct': 0.30,      # 回撤30%
    'gTrailStart': 10.0,   # 追踪启动10$
    'gTPDist': 13.0,       # 主止盈13$
    'gLockDist': 3.0,      # 锁定触发3$
    'gLockSL': 1.0,        # 锁定利润1$
    'pyrStep': 3.0,        # 金字塔步距3$
    'pyrMax': 8,           # 最大层数
    'l1Dist': 23.0,        # L1距离23$
    'l2Dist': 45.0,        # L2距离45$
    'l2Mult': 2.0,         # L2倍率
    'hardLoss': 220.0,     # 硬止损
    'seedLot': 0.01,       # 首仓0.01手
}

def simulate_real_trading(df):
    """模拟真实交易过程"""
    print("🔍 真实交易模拟...")
    print(f"参数: 回撤{PARAMS['trailPct']*100:.0f}% | 启动{PARAMS['gTrailStart']:.0f}$ | 止盈{PARAMS['gTPDist']:.0f}$ | 硬损{PARAMS['hardLoss']:.0f}$\n")
    
    trades = []  # 记录每笔完整交易
    trade_id = 0
    
    # 按天模拟（每天一个独立交易周期）
    df['date'] = df['datetime'].dt.date
    
    for date, day_df in df.groupby('date'):
        if len(day_df) < 1000:  # 跳过数据不足的天
            continue
            
        prices = day_df['mid'].values
        times = day_df['datetime'].values
        
        # === 开仓条件：趋势判断 ===
        # 用前30分钟判断趋势方向
        warmup = min(180, len(prices)//10)  # 约30分钟tick数
        if warmup < 30:
            continue
            
        early_prices = prices[:warmup]
        trend = prices[warmup] - early_prices[0]  # 正=上涨，负=下跌
        
        if abs(trend) < 2.0:  # 趋势不明显，不开仓
            continue
            
        direction = 1 if trend > 0 else -1  # 1=做多，-1=做空
        
        # === 开始一笔交易 ===
        trade_id += 1
        entry_price = prices[warmup]
        entry_time = times[warmup]
        
        # 持仓状态
        positions = [{'type': 'seed', 'price': entry_price, 'lot': PARAMS['seedLot']}]  # 首仓
        total_lots = PARAMS['seedLot']
        breakeven = entry_price
        
        # 追踪状态
        peak_delta = 0
        trailing = False
        
        # 补仓状态
        l1_opened = False
        l2_opened = False
        highest_buy = entry_price if direction == 1 else 0
        lowest_sell = entry_price if direction == -1 else 999999
        
        exit_reason = ""
        exit_price = 0
        pnl = 0
        
        # === 遍历价格 ===
        for i in range(warmup, len(prices)):
            price = prices[i]
            
            # 计算当前浮盈（基于均价）
            if direction == 1:  # 做多
                delta = price - breakeven
                # 金字塔加仓检查
                if delta > 0 and len([p for p in positions if p['type']=='pyramid']) < PARAMS['pyrMax']:
                    ref_price = max(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if price - ref_price >= PARAMS['pyrStep']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': PARAMS['seedLot']})
                        total_lots += PARAMS['seedLot']
                        highest_buy = max(highest_buy, price)
                        # 更新均价
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                
                # 马丁补仓检查（基于最远亏损仓）
                lowest_entry = min(p['price'] for p in positions)
                dist_from_lowest = price - lowest_entry
                if not l1_opened and dist_from_lowest <= -PARAMS['l1Dist']:
                    positions.append({'type': 'l1', 'price': price, 'lot': PARAMS['seedLot']})
                    total_lots += PARAMS['seedLot']
                    l1_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                elif l1_opened and not l2_opened and dist_from_lowest <= -PARAMS['l2Dist']:
                    l2_lot = PARAMS['seedLot'] * PARAMS['l2Mult']
                    positions.append({'type': 'l2', 'price': price, 'lot': l2_lot})
                    total_lots += l2_lot
                    l2_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                    
            else:  # 做空
                delta = breakeven - price
                # 金字塔加仓
                if delta > 0 and len([p for p in positions if p['type']=='pyramid']) < PARAMS['pyrMax']:
                    ref_price = min(p['price'] for p in positions if p['type'] in ['seed','pyramid'])
                    if ref_price - price >= PARAMS['pyrStep']:
                        positions.append({'type': 'pyramid', 'price': price, 'lot': PARAMS['seedLot']})
                        total_lots += PARAMS['seedLot']
                        lowest_sell = min(lowest_sell, price)
                        breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                
                # 马丁补仓
                highest_entry = max(p['price'] for p in positions)
                dist_from_highest = highest_entry - price
                if not l1_opened and dist_from_highest <= -PARAMS['l1Dist']:
                    positions.append({'type': 'l1', 'price': price, 'lot': PARAMS['seedLot']})
                    total_lots += PARAMS['seedLot']
                    l1_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
                elif l1_opened and not l2_opened and dist_from_highest <= -PARAMS['l2Dist']:
                    l2_lot = PARAMS['seedLot'] * PARAMS['l2Mult']
                    positions.append({'type': 'l2', 'price': price, 'lot': l2_lot})
                    total_lots += l2_lot
                    l2_opened = True
                    breakeven = sum(p['price']*p['lot'] for p in positions) / total_lots
            
            # 更新峰值
            if delta > peak_delta:
                peak_delta = delta
            
            # 检查追踪启动
            if not trailing and delta >= PARAMS['gTrailStart']:
                trailing = True
            
            # 检查追踪止盈
            if trailing:
                exit_line = peak_delta * (1 - PARAMS['trailPct'])
                if delta <= exit_line:
                    exit_reason = f"追踪止盈(回撤{PARAMS['trailPct']*100:.0f}%)"
                    exit_price = price
                    pnl = delta * total_lots * 100  # 简化：1手=100盎司
                    break
            
            # 检查主止盈
            if not trailing and delta >= PARAMS['gTPDist']:
                exit_reason = f"主止盈({PARAMS['gTPDist']:.0f}$)"
                exit_price = price
                pnl = PARAMS['gTPDist'] * total_lots * 100
                break
            
            # 检查硬止损
            if delta <= -PARAMS['hardLoss'] / (total_lots * 100):
                exit_reason = f"硬止损(-{PARAMS['hardLoss']:.0f}$)"
                exit_price = price
                pnl = -PARAMS['hardLoss']
                break
            
            # 收盘强制平仓
            if i == len(prices) - 1:
                exit_reason = "收盘平仓"
                exit_price = price
                pnl = delta * total_lots * 100
        
        # 记录交易
        trades.append({
            'trade_id': trade_id,
            'date': date,
            'direction': '多' if direction == 1 else '空',
            'entry': entry_price,
            'exit': exit_price,
            'pnl': pnl,
            'reason': exit_reason,
            'positions': len(positions),
            'total_lots': total_lots,
            'has_l1': l1_opened,
            'has_l2': l2_opened,
        })
        
        if trade_id <= 5:  # 打印前5笔交易详情
            print(f"交易#{trade_id} {date} {direction}: 入{entry_price:.2f} 出{exit_price:.2f} 盈亏${pnl:.2f} [{exit_reason}] 仓位{len(positions)}层")
    
    return pd.DataFrame(trades)

def analyze_trades(trades_df):
    """分析交易结果"""
    print(f"\n{'='*70}")
    print("📊 交易统计分析")
    print(f"{'='*70}\n")
    
    total = len(trades_df)
    wins = len(trades_df[trades_df['pnl'] > 0])
    losses = len(trades_df[trades_df['pnl'] <= 0])
    
    total_profit = trades_df[trades_df['pnl'] > 0]['pnl'].sum()
    total_loss = abs(trades_df[trades_df['pnl'] <= 0]['pnl'].sum())
    
    print(f"总交易次数: {total}")
    print(f"盈利次数: {wins} ({wins/total*100:.1f}%)")
    print(f"亏损次数: {losses} ({losses/total*100:.1f}%)")
    print(f"总盈利: ${total_profit:.2f}")
    print(f"总亏损: ${total_loss:.2f}")
    print(f"净利润: ${total_profit - total_loss:.2f}")
    print(f"盈利因子: {total_profit/total_loss:.2f}" if total_loss > 0 else "盈利因子: ∞")
    
    # 出场原因分析
    print(f"\n出场原因分布:")
    for reason, count in trades_df['reason'].value_counts().items():
        avg_pnl = trades_df[trades_df['reason']==reason]['pnl'].mean()
        print(f"  {reason}: {count}次 (平均${avg_pnl:.2f})")
    
    # 马丁补仓统计
    l1_count = trades_df['has_l1'].sum()
    l2_count = trades_df['has_l2'].sum()
    print(f"\n马丁补仓统计:")
    print(f"  触发L1: {l1_count}次 ({l1_count/total*100:.1f}%)")
    print(f"  触发L2: {l2_count}次 ({l2_count/total*100:.1f}%)")
    
    # 连赢连亏分析
    trades_df['win'] = trades_df['pnl'] > 0
    trades_df['streak'] = (trades_df['win'] != trades_df['win'].shift()).cumsum()
    streaks = trades_df.groupby('streak')['win'].agg(['first', 'count'])
    win_streaks = streaks[streaks['first'] == True]['count']
    loss_streaks = streaks[streaks['first'] == False]['count']
    
    print(f"\n连续交易统计:")
    print(f"  最大连赢: {win_streaks.max() if len(win_streaks) > 0 else 0} 次")
    print(f"  最大连亏: {loss_streaks.max() if len(loss_streaks) > 0 else 0} 次")
    
    # 检查最大连亏原因
    if len(loss_streaks) > 0 and loss_streaks.max() >= 2:
        max_loss_streak = loss_streaks.max()
        print(f"\n⚠️ 注意: 最大连亏{max_loss_streak}次")
        print(f"  连亏时通常是触发硬止损或趋势反转")
    
    return {
        'total': total,
        'wins': wins,
        'losses': losses,
        'win_rate': wins/total*100,
        'profit_factor': total_profit/total_loss if total_loss > 0 else 0,
        'net_profit': total_profit - total_loss,
    }

def main():
    df = pd.read_csv(DATA_FILE)
    df['datetime'] = pd.to_datetime(df['datetime'])
    
    print(f"📊 数据: {df['datetime'].min()} 至 {df['datetime'].max()}")
    print(f"   共 {len(df):,} 条 tick 数据\n")
    
    trades_df = simulate_real_trading(df)
    result = analyze_trades(trades_df)
    
    # 保存交易记录
    trades_df.to_csv("/home/lilei/.openclaw/workspace/data/trade_history.csv", index=False)
    print(f"\n✓ 交易记录已保存至: trade_history.csv")

if __name__ == "__main__":
    main()
